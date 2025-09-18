require 'spec_helper'

RSpec.describe RivaProxy::MockServer do
  let(:server) { described_class.new(port: 50052) }
  let(:dummy_audio) { "\x00" * 1024 }
  
  describe '#initialize' do
    it 'sets the port' do
      expect(server.port).to eq(50052)
    end

    it 'uses default port when not specified' do
      default_server = described_class.new
      expect(default_server.port).to eq(50051)
    end
  end

  describe '#recognize' do
    let(:config) do
      Nvidia::Riva::Asr::RecognitionConfig.new(
        encoding: :LINEAR_PCM,
        sample_rate_hertz: 16000,
        language_code: 'en-US'
      )
    end

    let(:request) do
      Nvidia::Riva::Asr::RecognizeRequest.new(
        config: config,
        audio: dummy_audio
      )
    end

    it 'returns a valid response' do
      response = server.recognize(request, nil)
      
      expect(response).to be_a(Nvidia::Riva::Asr::RecognizeResponse)
      expect(response.results).not_to be_empty
      
      result = response.results.first
      expect(result.alternatives).not_to be_empty
      
      alternative = result.alternatives.first
      expect(alternative.transcript).to be_a(String)
      expect(alternative.confidence).to be_a(Float)
      expect(alternative.confidence).to be > 0
    end

    it 'generates words with timing information' do
      response = server.recognize(request, nil)
      alternative = response.results.first.alternatives.first
      
      expect(alternative.words).not_to be_empty
      
      word = alternative.words.first
      expect(word.word).to be_a(String)
      expect(word.start_time).to be_a(Float)
      expect(word.end_time).to be_a(Float)
      expect(word.confidence).to be_a(Float)
      expect(word.speaker_tag).to be_a(Integer)
    end
  end

  describe '#streaming_recognize' do
    let(:config) do
      Nvidia::Riva::Asr::StreamingRecognitionConfig.new(
        config: Nvidia::Riva::Asr::RecognitionConfig.new(
          encoding: :LINEAR_PCM,
          sample_rate_hertz: 16000,
          language_code: 'en-US'
        ),
        interim_results: true
      )
    end

    let(:requests) do
      [
        Nvidia::Riva::Asr::StreamingRecognizeRequest.new(streaming_config: config),
        Nvidia::Riva::Asr::StreamingRecognizeRequest.new(audio_content: dummy_audio),
        Nvidia::Riva::Asr::StreamingRecognizeRequest.new(audio_content: dummy_audio)
      ]
    end

    it 'returns streaming responses' do
      responses = []
      
      server.streaming_recognize(requests, nil).each do |response|
        responses << response
      end
      
      expect(responses).not_to be_empty
      
      responses.each do |response|
        expect(response).to be_a(Nvidia::Riva::Asr::StreamingRecognizeResponse)
        expect(response.results).not_to be_empty
        
        result = response.results.first
        expect(result.alternatives).not_to be_empty
        expect(result.is_final).to be(true).or be(false)
        expect(result.stability).to be_a(Float)
      end
    end
  end

  describe 'private methods' do
    describe '#generate_mock_transcript' do
      it 'generates transcript based on audio length' do
        short_transcript = server.send(:generate_mock_transcript, 100)
        long_transcript = server.send(:generate_mock_transcript, 10000)
        
        expect(short_transcript.split.length).to be <= long_transcript.split.length
      end

      it 'adds ellipsis for interim results' do
        interim_transcript = server.send(:generate_mock_transcript, 1000, interim: true)
        expect(interim_transcript).to end_with('...')
      end
    end

    describe '#generate_mock_words' do
      it 'generates word info for each word in transcript' do
        transcript = "hello world test"
        words = server.send(:generate_mock_words, transcript)
        
        expect(words.length).to eq(3)
        
        words.each do |word|
          expect(word).to be_a(Nvidia::Riva::Asr::WordInfo)
          expect(word.word).to be_a(String)
          expect(word.start_time).to be_a(Float)
          expect(word.end_time).to be_a(Float)
          expect(word.confidence).to be_a(Float)
          expect(word.speaker_tag).to be_a(Integer)
        end
        
        # Check timing progression
        expect(words[1].start_time).to be > words[0].start_time
        expect(words[2].start_time).to be > words[1].start_time
      end
    end
  end
end