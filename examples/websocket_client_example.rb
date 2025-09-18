#!/usr/bin/env ruby

require 'faye/websocket'
require 'eventmachine'
require 'json'
require 'base64'

class WebSocketClient
  def initialize(url)
    @url = url
    @ws = nil
  end

  def connect
    EM.run do
      @ws = Faye::WebSocket::Client.new(@url)

      @ws.on :open do |event|
        puts "Connected to WebSocket server"
        send_config
      end

      @ws.on :message do |event|
        handle_message(event.data)
      end

      @ws.on :close do |event|
        puts "Connection closed: #{event.code} - #{event.reason}"
        EM.stop
      end

      @ws.on :error do |event|
        puts "WebSocket error: #{event.message}"
      end

      # Send test audio data after a short delay
      EM.add_timer(2) do
        send_test_audio
      end

      # Close connection after 10 seconds
      EM.add_timer(10) do
        @ws.close
      end
    end
  end

  private

  def send_config
    config = {
      type: 'config',
      config: {
        encoding: 'LINEAR_PCM',
        sample_rate_hertz: 16000,
        language_code: 'en-US',
        enable_automatic_punctuation: true,
        enable_word_time_offsets: true,
        interim_results: true,
        max_alternatives: 1
      }
    }

    puts "Sending config: #{config}"
    @ws.send(JSON.generate(config))
  end

  def send_test_audio
    # Read the test audio file
    audio_file = File.join(File.dirname(__FILE__), '..', '16k16bit.wav')
    
    if File.exist?(audio_file)
      puts "Reading audio file: #{audio_file}"
      audio_data = read_wav_file(audio_file)
      
      # Split audio into chunks and send
      chunks = split_audio_into_chunks(audio_data, 1024)
      puts "Sending #{chunks.length} audio chunks"
      
      chunks.each_with_index do |chunk, index|
        EM.add_timer(index * 0.1) do  # Send chunks every 100ms
          audio_message = {
            type: 'audio',
            audio: Base64.encode64(chunk).strip
          }
          @ws.send(JSON.generate(audio_message))
        end
      end
    else
      puts "Audio file not found: #{audio_file}"
      # Send dummy audio data
      send_dummy_audio
    end
  end

  def send_dummy_audio
    # Generate some dummy audio data (silence)
    dummy_audio = "\x00" * 1024
    
    5.times do |i|
      EM.add_timer(i * 0.5) do
        audio_message = {
          type: 'audio',
          audio: Base64.encode64(dummy_audio).strip
        }
        puts "Sending dummy audio chunk #{i + 1}"
        @ws.send(JSON.generate(audio_message))
      end
    end
  end

  def handle_message(data)
    begin
      message = JSON.parse(data)
      
      case message['type']
      when 'ready'
        puts "Server ready: #{message['message']}"
      when 'recognition'
        handle_recognition_response(message)
      when 'error'
        puts "Server error: #{message['message']}"
      else
        puts "Unknown message type: #{message['type']}"
      end
    rescue JSON::ParserError => e
      puts "Failed to parse message: #{e.message}"
    end
  end

  def handle_recognition_response(message)
    results = message['results']
    return if results.empty?

    results.each do |result|
      result['alternatives'].each do |alternative|
        transcript = alternative['transcript']
        confidence = alternative['confidence']
        is_final = result['is_final']
        
        status = is_final ? '[FINAL]' : '[INTERIM]'
        puts "#{status} Transcript: #{transcript} (confidence: #{confidence})"
        
        if alternative['words'] && !alternative['words'].empty?
          puts "  Words:"
          alternative['words'].each do |word|
            puts "    #{word['word']} (#{word['start_time']}s - #{word['end_time']}s, confidence: #{word['confidence']})"
          end
        end
      end
    end
  end

  def read_wav_file(file_path)
    File.open(file_path, 'rb') do |file|
      # Read WAV header
      header = file.read(44)
      
      # Validate WAV format
      unless header[0..3] == 'RIFF' && header[8..11] == 'WAVE'
        raise "Invalid WAV file format"
      end
      
      # Read audio data (skip header)
      file.read
    end
  end

  def split_audio_into_chunks(audio_data, chunk_size)
    chunks = []
    offset = 0
    
    while offset < audio_data.length
      chunk = audio_data[offset, chunk_size]
      chunks << chunk
      offset += chunk_size
    end
    
    chunks
  end
end

# Usage
if __FILE__ == $0
  url = ARGV[0] || 'ws://localhost:8080'
  puts "Connecting to WebSocket server at: #{url}"
  
  client = WebSocketClient.new(url)
  client.connect
end