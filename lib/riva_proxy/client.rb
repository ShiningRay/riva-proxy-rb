require 'grpc'
require_relative 'streaming_session'

module RivaProxy
  class Client
    DEFAULT_HOST = 'localhost'
    DEFAULT_PORT = 50051
    DEFAULT_TIMEOUT = 30

    attr_reader :host, :port, :timeout, :stub

    def initialize(host: DEFAULT_HOST, port: DEFAULT_PORT, timeout: DEFAULT_TIMEOUT, credentials: nil)
      @host = host
      @port = port
      @timeout = timeout
      @credentials = credentials || :this_channel_is_insecure
      
      connect!
    end

    # Non-streaming speech recognition
    def recognize(audio_data, config = {})
      request = build_recognize_request(audio_data, config)
      
      begin
        response = stub.recognize(request, deadline: Time.now + timeout)
        response
      rescue GRPC::BadStatus => e
        raise RecognitionError, "Recognition failed: #{e.message}"
      rescue => e
        raise ConnectionError, "Connection failed: #{e.message}"
      end
    end

    # Streaming speech recognition
    def streaming_recognize(audio_stream = nil, config = {}, &block)
      requests = build_streaming_requests(audio_stream, config)
      
      begin
        responses = stub.streaming_recognize(requests, deadline: Time.now + timeout)
        
        if block_given?
          responses.each { |response| yield(response) }
        else
          responses.to_a
        end
      rescue GRPC::BadStatus => e
        raise RecognitionError, "Streaming recognition failed: #{e.message}"
      rescue => e
        raise ConnectionError, "Connection failed: #{e.message}"
      end
    end

    # Create a managed streaming session
    def create_streaming_session(config = {}, &response_handler)
      StreamingSession.new(self, config, &response_handler)
    end

    # Test connection
    def ping
      config = Nvidia::Riva::Asr::RecognitionConfig.new(
        encoding: :LINEAR_PCM,
        sample_rate_hertz: 16000,
        language_code: 'en-US'
      )
      
      request = Nvidia::Riva::Asr::RecognizeRequest.new(
        config: config,
        audio: "\x00" * 1024  # Dummy audio data
      )
      
      begin
        stub.recognize(request, deadline: Time.now + 5)
        true
      rescue
        false
      end
    end

    private

    def connect!
      address = "#{host}:#{port}"
      @stub = Nvidia::Riva::Asr::RivaSpeechRecognition::Stub.new(address, @credentials)
    end

    def build_recognize_request(audio_data, config)
      recognition_config = build_recognition_config(config)
      
      Nvidia::Riva::Asr::RecognizeRequest.new(
        config: recognition_config,
        audio: audio_data
      )
    end

    def build_streaming_requests(audio_stream, config)
      Enumerator.new do |yielder|
        # First request with config
        streaming_config = build_streaming_config(config)
        puts streaming_config.inspect
        yielder << Nvidia::Riva::Asr::StreamingRecognizeRequest.new(
          streaming_config: streaming_config
        )
        
        # Subsequent requests with audio data
        if audio_stream
          if audio_stream.respond_to?(:each)
            audio_stream.each do |chunk|
              yielder << Nvidia::Riva::Asr::StreamingRecognizeRequest.new(
                audio_content: chunk
              )
            end
          else
            yielder << Nvidia::Riva::Asr::StreamingRecognizeRequest.new(
              audio_content: audio_stream
            )
          end
        end
      end
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