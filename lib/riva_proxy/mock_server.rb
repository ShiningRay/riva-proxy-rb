require 'grpc'

module RivaProxy
  class MockServer < Nvidia::Riva::Asr::RivaSpeechRecognition::Service
    DEFAULT_PORT = 50051
    
    attr_reader :port, :server

    def initialize(port: DEFAULT_PORT)
      @port = port
      @server = nil
    end

    # Start the mock server
    def start(blocking: true)
      @server = GRPC::RpcServer.new
      @server.add_http2_port("0.0.0.0:#{port}", :this_port_is_insecure)
      @server.handle(self)
      
      puts "Mock Riva ASR server starting on port #{port}..."
      
      if blocking
        @server.run_till_terminated_or_interrupted([1, 'int', 'SIGQUIT'])
      else
        Thread.new { @server.run_till_terminated_or_interrupted([1, 'int', 'SIGQUIT']) }
        sleep(0.1) # Give server time to start
      end
    end

    # Stop the mock server
    def stop
      @server&.stop
    end

    # Non-streaming recognition implementation
    def recognize(request, _call)
      puts "Received recognize request for language: #{request.config.language_code}"
      
      # Mock response with dummy transcript
      transcript = generate_mock_transcript(request.audio.length)
      
      alternative = Nvidia::Riva::Asr::SpeechRecognitionAlternative.new(
        transcript: transcript,
        confidence: 0.95,
        words: generate_mock_words(transcript)
      )
      
      result = Nvidia::Riva::Asr::SpeechRecognitionResult.new(
        alternatives: [alternative],
        channel_tag: 0,
        audio_processed: "#{request.audio.length} bytes"
      )
      
      Nvidia::Riva::Asr::RecognizeResponse.new(results: [result])
    end

    # Streaming recognition implementation
    def streaming_recognize(requests, _call)
      puts "Starting streaming recognition..."
      
      Enumerator.new do |yielder|
        config = nil
        audio_chunks = []
        
        requests.each do |request|
          if request.streaming_config
            config = request.streaming_config
            puts "Received streaming config for language: #{config.config.language_code}"
          elsif request.audio_content
            audio_chunks << request.audio_content
            
            # Send interim results if enabled
            if config&.interim_results && audio_chunks.length % 3 == 0
              transcript = generate_mock_transcript(audio_chunks.join.length, interim: true)
              yielder << create_streaming_response(transcript, false, config)
            end
            
            # Send final result every 10 chunks
            if audio_chunks.length % 10 == 0
              transcript = generate_mock_transcript(audio_chunks.join.length)
              yielder << create_streaming_response(transcript, true, config)
            end
          end
        end
        
        # Send final response
        unless audio_chunks.empty?
          transcript = generate_mock_transcript(audio_chunks.join.length)
          yielder << create_streaming_response(transcript, true, config)
        end
      end
    end

    private

    def generate_mock_transcript(audio_length, interim: false)
      base_words = [
        "Hello", "world", "this", "is", "a", "test", "of", "the", 
        "speech", "recognition", "system", "working", "correctly"
      ]
      
      # Generate transcript based on audio length
      word_count = [audio_length / 1000, 1].max
      words = base_words.sample(word_count)
      
      transcript = words.join(" ")
      transcript += "..." if interim
      transcript
    end

    def generate_mock_words(transcript)
      words = transcript.split
      start_time = 0.0
      
      words.map do |word|
        word_duration = word.length * 0.1 + rand(0.1..0.3)
        
        word_info = Nvidia::Riva::Asr::WordInfo.new(
          word: word,
          start_time: start_time,
          end_time: start_time + word_duration,
          confidence: 0.9 + rand(0.1),
          speaker_tag: rand(1..2)
        )
        
        start_time += word_duration + 0.1
        word_info
      end
    end

    def create_streaming_response(transcript, is_final, config)
      alternative = Nvidia::Riva::Asr::SpeechRecognitionAlternative.new(
        transcript: transcript,
        confidence: is_final ? 0.95 : 0.7,
        words: is_final ? generate_mock_words(transcript) : []
      )
      
      result = Nvidia::Riva::Asr::StreamingRecognitionResult.new(
        alternatives: [alternative],
        is_final: is_final,
        stability: is_final ? 1.0 : 0.5,
        channel_tag: 0,
        audio_processed: "#{transcript.length * 100} bytes"
      )
      
      Nvidia::Riva::Asr::StreamingRecognizeResponse.new(
        results: [result],
        error: ""
      )
    end
  end
end