#!/usr/bin/env ruby

require 'faye/websocket'
require 'eventmachine'
require 'json'
require 'base64'

# Simple WebSocket client that sends base64 audio data directly
class SimpleAudioClient
  def initialize(url = 'ws://localhost:8080')
    @url = url
    @config_sent = false
  end

  def connect
    EM.run do
      @ws = Faye::WebSocket::Client.new(@url)

      @ws.on :open do |event|
        puts "Connected to WebSocket server"
        send_config
      end

      @ws.on :message do |event|
        handle_response(event.data)
      end

      @ws.on :close do |event|
        puts "Connection closed: #{event.code} - #{event.reason}"
        EM.stop
      end

      @ws.on :error do |event|
        puts "WebSocket error: #{event.message}"
        EM.stop
      end

      # Send test audio data every 100ms after config is sent
      EM.add_periodic_timer(0.1) do
        send_test_audio if @config_sent
      end

      # Stop after 5 seconds
      EM.add_timer(5) do
        puts "Stopping client..."
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
        interim_results: true
      }
    }
    
    puts "Sending config..."
    @ws.send(JSON.generate(config))
  end

  def send_test_audio
    # Generate a simple sine wave (1 second at 16kHz, 16-bit)
    sample_rate = 16000
    duration = 0.1  # 100ms chunks
    frequency = 440  # A4 note
    
    samples = []
    (sample_rate * duration).to_i.times do |i|
      # Generate sine wave sample
      sample = (Math.sin(2 * Math::PI * frequency * i / sample_rate) * 32767).to_i
      # Convert to 16-bit little-endian
      samples << [sample].pack('s<')
    end
    
    audio_data = samples.join
    base64_audio = Base64.strict_encode64(audio_data)
    
    puts "Sending raw base64 audio data (#{audio_data.length} bytes)"
    @ws.send(base64_audio)
  end

  def handle_response(data)
    begin
      response = JSON.parse(data)
      case response['type']
      when 'ready'
        puts "Server ready: #{response['message']}"
        @config_sent = true
      when 'recognition'
        if response['results'] && !response['results'].empty?
          result = response['results'].first
          if result['alternatives'] && !result['alternatives'].empty?
            transcript = result['alternatives'].first['transcript']
            confidence = result['alternatives'].first['confidence']
            puts "Recognition: '#{transcript}' (confidence: #{confidence})"
          end
        end
      when 'error'
        puts "Error: #{response['message']}"
      else
        puts "Unknown response: #{response}"
      end
    rescue JSON::ParserError => e
      puts "Failed to parse response: #{e.message}"
      puts "Raw response: #{data}"
    end
  end
end

if __FILE__ == $0
  url = ARGV[0] || 'ws://localhost:8080'
  puts "Connecting to #{url}..."
  puts "This client will:"
  puts "1. Send configuration as JSON"
  puts "2. Send audio data directly as base64 (no JSON wrapper)"
  puts ""
  
  client = SimpleAudioClient.new(url)
  client.connect
end