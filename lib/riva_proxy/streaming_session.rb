require 'grpc'

module RivaProxy
  class StreamingSession
    attr_reader :client, :config, :response_handler, :stream, :request_queue

    def initialize(client, config, &response_handler)
      @client = client
      @config = config
      @response_handler = response_handler
      @request_queue = Queue.new
      @stream = nil
      @closed = false
      @response_thread = nil
      # Retry policy for transient gRPC errors (e.g., DEADLINE_EXCEEDED, UNAVAILABLE)
      @max_retries = (ENV['RIVA_STREAMING_MAX_RETRIES'] || 3).to_i
      @base_delay = (ENV['RIVA_STREAMING_RETRY_BASE_DELAY'] || 0.5).to_f
      @retries = 0

      start_session
    end

    def send_audio(audio_data)
      return if @closed

      request = Nvidia::Riva::Asr::StreamingRecognizeRequest.new(
        audio_content: audio_data
      )

      @request_queue << request
    end

    def close
      return if @closed

      @closed = true
      @request_queue << :close

      # Wait for response thread to finish
      @response_thread&.join(5) # 5 second timeout

      # Do not call close on Enumerator-based stream; it will finish after :close is seen
      @stream = nil
    end

    def closed?
      @closed
    end

    private

    def start_session
      create_stream

      # Start response handling thread
      @response_thread = Thread.new { handle_responses }
    end

    # Create request enumerator for the stream (starts with config message)
    def build_request_enum
      Enumerator.new do |yielder|
        # First request with config
        streaming_config = build_streaming_config(@config)
        yielder << Nvidia::Riva::Asr::StreamingRecognizeRequest.new(
          streaming_config: streaming_config
        )

        # Process queued requests
        loop do
          request = @request_queue.pop
          break if request == :close

          yielder << request
        end
      end
    end

    # Open a new gRPC streaming call without a strict deadline (long-lived stream)
    def create_stream
      request_enum = build_request_enum
      # NOTE: do not pass `deadline:` here for long-lived bidi streaming
      # to avoid premature DEADLINE_EXCEEDED. Timeouts can be enforced externally if needed.
      @stream = @client.stub.streaming_recognize(request_enum)
      true
    end

    def handle_responses
      return unless @stream

      loop do
        break if @closed

        begin
          @stream.each do |response|
            break if @closed

            @response_handler&.call(response)
          end
          # Stream finished without error
          break
        rescue StandardError => e
          break if @closed

          if retryable_grpc_error?(e) && @retries < @max_retries
            delay = backoff_delay(@retries)
            @retries += 1
            warn "gRPC stream error: #{e.class}: #{e.message}. Retrying ##{@retries} in #{format('%.2f', delay)}s..."
            sleep delay
            begin
              create_stream
              next # continue loop with new stream
            rescue StandardError => open_err
              # If reopening stream itself fails, decide whether to retry again or exit
              next if retryable_grpc_error?(open_err) && @retries < @max_retries

              @response_handler&.call(error: open_err) if @response_handler
              break
            end
          else
            # Not retryable or retries exhausted
            @response_handler&.call(error: e) if @response_handler
            break
          end
        end
      end
    ensure
      @closed = true
    end

    def retryable_grpc_error?(error)
      return false unless error.is_a?(GRPC::BadStatus) || error.is_a?(StandardError)

      code = (error.respond_to?(:code) ? error.code : nil)
      # Ruby gRPC codes are integers via GRPC::Core::StatusCodes, sometimes symbolized depending on version
      code_int =
        case code
        when Integer then code
        when Symbol
          case code
          when :DEADLINE_EXCEEDED then GRPC::Core::StatusCodes::DEADLINE_EXCEEDED
          when :UNAVAILABLE then GRPC::Core::StatusCodes::UNAVAILABLE
          when :UNKNOWN then GRPC::Core::StatusCodes::UNKNOWN
          when :CANCELLED then GRPC::Core::StatusCodes::CANCELLED
          else -1
          end
        else
          # Fallback: inspect message for common transient patterns
          if error.message =~ /Deadline Exceeded/i
            GRPC::Core::StatusCodes::DEADLINE_EXCEEDED
          elsif error.message =~ /UNAVAILABLE|Unavailable/i
            GRPC::Core::StatusCodes::UNAVAILABLE
          else
            -1
          end
        end

      [
        GRPC::Core::StatusCodes::DEADLINE_EXCEEDED,
        GRPC::Core::StatusCodes::UNAVAILABLE,
        GRPC::Core::StatusCodes::UNKNOWN,
        GRPC::Core::StatusCodes::CANCELLED
      ].include?(code_int)
    rescue NameError
      # If GRPC::Core::StatusCodes isn't available for some reason, best-effort fallback
      error.message =~ /(Deadline Exceeded|UNAVAILABLE|Unavailable|CANCELLED|Canceled)/i
    end

    def backoff_delay(retry_count)
      # Exponential backoff with jitter
      (@base_delay * (2**retry_count)) + (rand * 0.2)
    end

    def build_streaming_config(config)
      recognition_config = build_recognition_config(config)

      Nvidia::Riva::Asr::StreamingRecognitionConfig.new(
        config: recognition_config,
        interim_results: config[:interim_results] || false,
        max_alternatives: config[:max_alternatives] || 1,
        enable_word_time_offsets: config[:enable_word_time_offsets] || false,
        enable_automatic_punctuation: config[:enable_automatic_punctuation] || false,
        enable_separate_recognition_per_channel: config[:enable_separate_recognition_per_channel] || false,
        custom_configuration: config[:custom_configuration] || ''
      )
    end

    def build_recognition_config(config)
      Nvidia::Riva::Asr::RecognitionConfig.new(
        encoding: config[:encoding] || :LINEAR_PCM,
        sample_rate_hertz: config[:sample_rate_hertz] || 16_000,
        language_code: config[:language_code] || 'en-US',
        max_alternatives: config[:max_alternatives] || 1,
        enable_automatic_punctuation: config[:enable_automatic_punctuation] || false,
        enable_separate_recognition_per_channel: config[:enable_separate_recognition_per_channel] || false,
        enable_word_time_offsets: config[:enable_word_time_offsets] || false,
        audio_channel_count: config[:audio_channel_count] || 1,
        model: config[:model] || '',
        diarization_config: build_diarization_config(config[:diarization]),
        custom_configuration: config[:custom_configuration] || ''
      )
    end

    def build_diarization_config(diarization_config)
      return nil unless diarization_config

      Nvidia::Riva::Asr::SpeakerDiarizationConfig.new(
        enable_speaker_diarization: diarization_config[:enable_speaker_diarization] || false,
        min_speaker_count: diarization_config[:min_speaker_count] || 2,
        max_speaker_count: diarization_config[:max_speaker_count] || 8
      )
    end
  end
end
