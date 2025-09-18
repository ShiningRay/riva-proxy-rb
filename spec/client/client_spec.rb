require 'spec_helper'

RSpec.describe RivaProxy::Client do
  let(:client) { described_class.new(host: 'localhost', port: 50051) }
  let(:dummy_audio) { "\x00" * 1024 }
  
  describe '#initialize' do
    it 'sets default values' do
      expect(client.host).to eq('localhost')
      expect(client.port).to eq(50051)
      expect(client.timeout).to eq(30)
    end

    it 'accepts custom values' do
      custom_client = described_class.new(
        host: 'example.com',
        port: 8080,
        timeout: 60
      )
      
      expect(custom_client.host).to eq('example.com')
      expect(custom_client.port).to eq(8080)
      expect(custom_client.timeout).to eq(60)
    end
  end

  describe '#recognize' do
    let(:config) do
      {
        encoding: :LINEAR_PCM,
        sample_rate_hertz: 16000,
        language_code: 'en-US'
      }
    end

    it 'builds correct recognition request' do
      # Mock the stub to avoid actual network calls
      stub = double('stub')
      allow(client).to receive(:stub).and_return(stub)
      
      expected_response = Nvidia::Riva::Asr::RecognizeResponse.new
      expect(stub).to receive(:recognize).and_return(expected_response)
      
      result = client.recognize(dummy_audio, config)
      expect(result).to eq(expected_response)
    end

    it 'handles GRPC errors' do
      stub = double('stub')
      allow(client).to receive(:stub).and_return(stub)
      
      expect(stub).to receive(:recognize).and_raise(GRPC::BadStatus.new(1, 'Test error'))
      
      expect {
        client.recognize(dummy_audio, config)
      }.to raise_error(RivaProxy::RecognitionError, /Recognition failed/)
    end
  end

  describe '#streaming_recognize' do
    let(:config) do
      {
        encoding: :LINEAR_PCM,
        sample_rate_hertz: 16000,
        language_code: 'en-US',
        interim_results: true
      }
    end

    it 'builds correct streaming requests' do
      stub = double('stub')
      allow(client).to receive(:stub).and_return(stub)
      
      audio_chunks = [dummy_audio, dummy_audio]
      expected_responses = [
        Nvidia::Riva::Asr::StreamingRecognizeResponse.new,
        Nvidia::Riva::Asr::StreamingRecognizeResponse.new
      ]
      
      expect(stub).to receive(:streaming_recognize).and_return(expected_responses)
      
      results = []
      client.streaming_recognize(audio_chunks, config) do |response|
        results << response
      end
      
      expect(results).to eq(expected_responses)
    end
  end

  describe 'private methods' do
    describe '#build_recognition_config' do
      it 'builds config with default values' do
        config = client.send(:build_recognition_config, {})
        
        expect(config.encoding).to eq(:LINEAR_PCM)
        expect(config.sample_rate_hertz).to eq(16000)
        expect(config.language_code).to eq('en-US')
        expect(config.max_alternatives).to eq(1)
      end

      it 'builds config with custom values' do
        custom_config = {
          encoding: :FLAC,
          sample_rate_hertz: 44100,
          language_code: 'zh-CN',
          max_alternatives: 3,
          enable_automatic_punctuation: true
        }
        
        config = client.send(:build_recognition_config, custom_config)
        
        expect(config.encoding).to eq(:FLAC)
        expect(config.sample_rate_hertz).to eq(44100)
        expect(config.language_code).to eq('zh-CN')
        expect(config.max_alternatives).to eq(3)
        expect(config.enable_automatic_punctuation).to be true
      end
    end

    describe '#build_diarization_config' do
      it 'returns nil when no diarization config provided' do
        result = client.send(:build_diarization_config, nil)
        expect(result).to be_nil
      end

      it 'builds diarization config with custom values' do
        diarization_config = {
          enable_speaker_diarization: true,
          min_speaker_count: 3,
          max_speaker_count: 6
        }
        
        config = client.send(:build_diarization_config, diarization_config)
        
        expect(config.enable_speaker_diarization).to be true
        expect(config.min_speaker_count).to eq(3)
        expect(config.max_speaker_count).to eq(6)
      end
    end
  end
end