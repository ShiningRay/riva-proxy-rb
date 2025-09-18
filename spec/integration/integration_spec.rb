require 'spec_helper'

RSpec.describe 'Integration Tests', :integration do
  let(:server_port) { 50053 }
  let(:server) { RivaProxy::MockServer.new(port: server_port) }
  let(:client) { RivaProxy::Client.new(host: 'localhost', port: server_port) }
  let(:dummy_audio) { "\x00" * 16000 }  # 1 second of audio

  before(:all) do
    @server = RivaProxy::MockServer.new(port: 50053)
    @server_thread = Thread.new { @server.start(blocking: false) }
    sleep(1) # Give server time to start
  end

  after(:all) do
    @server.stop
    @server_thread.kill if @server_thread&.alive?
  end

  describe 'Client-Server Communication' do
    it 'performs non-streaming recognition successfully' do
      config = {
        encoding: :LINEAR_PCM,
        sample_rate_hertz: 16000,
        language_code: 'en-US',
        enable_automatic_punctuation: true,
        enable_word_time_offsets: true
      }

      response = client.recognize(dummy_audio, config)
      
      expect(response).to be_a(Nvidia::Riva::Asr::RecognizeResponse)
      expect(response.results).not_to be_empty
      
      result = response.results.first
      expect(result.alternatives).not_to be_empty
      
      alternative = result.alternatives.first
      expect(alternative.transcript).to be_a(String)
      expect(alternative.transcript.length).to be > 0
      expect(alternative.confidence).to be_between(0, 1)
      
      # Check word timing information
      expect(alternative.words).not_to be_empty
      alternative.words.each do |word|
        expect(word.start_time).to be >= 0
        expect(word.end_time).to be > word.start_time
        expect(word.confidence).to be_between(0, 1)
      end
    end

    it 'performs streaming recognition successfully' do
      config = {
        encoding: :LINEAR_PCM,
        sample_rate_hertz: 16000,
        language_code: 'en-US',
        interim_results: true,
        max_alternatives: 2
      }

      audio_chunks = Array.new(10) { "\x00" * 1600 }  # 10 chunks of 0.1 seconds each
      responses = []

      client.streaming_recognize(audio_chunks, config) do |response|
        responses << response
      end

      expect(responses).not_to be_empty
      
      # Check that we got both interim and final results
      interim_results = responses.select { |r| r.results.any? { |res| !res.is_final } }
      final_results = responses.select { |r| r.results.any? { |res| res.is_final } }
      
      expect(interim_results).not_to be_empty
      expect(final_results).not_to be_empty
      
      # Check response structure
      responses.each do |response|
        expect(response).to be_a(Nvidia::Riva::Asr::StreamingRecognizeResponse)
        expect(response.results).not_to be_empty
        
        response.results.each do |result|
          expect(result.stability).to be_between(0, 1)
          expect(result.alternatives).not_to be_empty
          
          result.alternatives.each do |alternative|
            expect(alternative.transcript).to be_a(String)
            expect(alternative.confidence).to be_between(0, 1)
          end
        end
      end
    end

    it 'handles speaker diarization' do
      config = {
        encoding: :LINEAR_PCM,
        sample_rate_hertz: 16000,
        language_code: 'en-US',
        diarization: {
          enable_speaker_diarization: true,
          min_speaker_count: 2,
          max_speaker_count: 4
        }
      }

      response = client.recognize(dummy_audio, config)
      
      expect(response.results).not_to be_empty
      
      result = response.results.first
      alternative = result.alternatives.first
      
      # Check that speaker tags are assigned
      expect(alternative.words).not_to be_empty
      alternative.words.each do |word|
        expect(word.speaker_tag).to be_a(Integer)
        expect(word.speaker_tag).to be > 0
      end
    end

    it 'handles different audio encodings' do
      encodings = [:LINEAR_PCM, :FLAC, :MULAW, :ALAW]
      
      encodings.each do |encoding|
        config = {
          encoding: encoding,
          sample_rate_hertz: 16000,
          language_code: 'en-US'
        }

        expect {
          response = client.recognize(dummy_audio, config)
          expect(response.results).not_to be_empty
        }.not_to raise_error
      end
    end

    it 'handles different languages' do
      languages = ['en-US', 'zh-CN', 'es-ES', 'fr-FR']
      
      languages.each do |language|
        config = {
          encoding: :LINEAR_PCM,
          sample_rate_hertz: 16000,
          language_code: language
        }

        expect {
          response = client.recognize(dummy_audio, config)
          expect(response.results).not_to be_empty
        }.not_to raise_error
      end
    end
  end

  describe 'Error Handling' do
    it 'handles connection timeout gracefully' do
      timeout_client = RivaProxy::Client.new(
        host: 'localhost',
        port: server_port,
        timeout: 0.001  # Very short timeout
      )

      expect {
        timeout_client.recognize(dummy_audio)
      }.to raise_error(RivaProxy::Error)
    end
  end

  describe 'Performance' do
    it 'processes recognition requests efficiently' do
      config = {
        encoding: :LINEAR_PCM,
        sample_rate_hertz: 16000,
        language_code: 'en-US'
      }

      start_time = Time.now
      
      10.times do
        response = client.recognize(dummy_audio, config)
        expect(response.results).not_to be_empty
      end
      
      end_time = Time.now
      total_time = end_time - start_time
      
      # Should process 10 requests in reasonable time (less than 5 seconds)
      expect(total_time).to be < 5.0
    end
  end
end