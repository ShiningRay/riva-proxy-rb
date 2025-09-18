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
      
      # Close the stream
      @stream&.close
    end

    def closed?
      @closed
    end

    private

    def start_session
      # Create request enumerator
      request_enum = Enumerator.new do |yielder|
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
      
      # Start streaming recognition
      begin
        @stream = @client.stub.streaming_recognize(
          request_enum, 
          deadline: Time.now + @client.timeout
        )
        
        # Start response handling thread
        @response_thread = Thread.new { handle_responses }
        
      rescue => e
        @closed = true
        raise e
      end
    end

    def handle_responses
      return unless @stream
      
      begin
        @stream.each do |response|
          break if @closed
          @response_handler&.call(response)
        end
      rescue => e
        # Handle stream errors
        @response_handler&.call(error: e) if @response_handler
      ensure
        @closed = true
      end
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
        sample_rate_hertz: config[:sample_rate_hertz] || 16000,
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