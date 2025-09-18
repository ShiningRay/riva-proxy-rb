#!/usr/bin/env ruby

require_relative '../lib/riva_proxy'

# Example usage of RivaProxy::Client

def read_wav_file(file_path)
  # Read WAV file and extract audio data
  # This is a simple WAV reader that skips the header and reads raw PCM data
  File.open(file_path, 'rb') do |file|
    # Read WAV header (44 bytes for standard WAV)
    header = file.read(44)
    
    # Verify it's a WAV file
    unless header[0..3] == 'RIFF' && header[8..11] == 'WAVE'
      raise "Not a valid WAV file: #{file_path}"
    end
    
    # Extract format information from header
    format_chunk = header[20..23]
    channels = header[22..23].unpack('v')[0]
    sample_rate = header[24..27].unpack('V')[0]
    bits_per_sample = header[34..35].unpack('v')[0]
    
    puts "WAV file info:"
    puts "  Channels: #{channels}"
    puts "  Sample rate: #{sample_rate} Hz"
    puts "  Bits per sample: #{bits_per_sample}"
    
    # Read the rest of the file as audio data
    audio_data = file.read
    
    {
      audio_data: audio_data,
      sample_rate: sample_rate,
      channels: channels,
      bits_per_sample: bits_per_sample
    }
  end
end

def split_audio_into_chunks(audio_data, chunk_size = 3200)
  # Split audio data into chunks for streaming
  chunks = []
  offset = 0
  
  while offset < audio_data.length
    chunk = audio_data[offset, chunk_size]
    chunks << chunk
    offset += chunk_size
  end
  
  chunks
end

def main
  # Initialize client
  client = RivaProxy::Client.new(
    host: '192.168.66.139',
    port: 50051,
    timeout: 30
  )

  puts "Testing connection..."
  if client.ping
    puts "✓ Connection successful"
  else
    puts "✗ Connection failed"
    # return
  end

  # Read the WAV file
  wav_file_path = File.join(__dir__, '..', '16k16bit.wav')
  puts "\nReading WAV file: #{wav_file_path}"
  
  begin
    wav_data = read_wav_file(wav_file_path)
    audio_data = wav_data[:audio_data]
    sample_rate = wav_data[:sample_rate]
    
    puts "Audio data size: #{audio_data.length} bytes"
    puts "Duration: #{(audio_data.length.to_f / (sample_rate * 2)).round(2)} seconds"
  rescue => e
    puts "Error reading WAV file: #{e.message}"
    return
  end

  # Example 1: Non-streaming recognition
  puts "\n=== Non-streaming Recognition Example ==="
  
  config = {
    encoding: :LINEAR_PCM,
    sample_rate_hertz: sample_rate,
    language_code: 'zh-CN',
    enable_automatic_punctuation: true,
    enable_word_time_offsets: true
  }
  
  begin
    response = client.recognize(audio_data, config)
    
    response.results.each_with_index do |result, i|
      puts "Result #{i + 1}:"
      result.alternatives.each_with_index do |alternative, j|
        puts "  Alternative #{j + 1}: #{alternative.transcript} (confidence: #{alternative.confidence})"
        
        if alternative.words.any?
          puts "  Words with timing:"
          alternative.words.each do |word|
            puts "    #{word.word} (#{word.start_time}s - #{word.end_time}s, confidence: #{word.confidence})"
          end
        end
      end
    end
  rescue RivaProxy::Error => e
    puts "Recognition error: #{e.message}"
  end

  # Example 2: Streaming recognition
  puts "\n=== Streaming Recognition Example ==="
  
  # Split audio data into chunks for streaming
  audio_chunks = split_audio_into_chunks(audio_data, 3200)
  puts "Split audio into #{audio_chunks.length} chunks"
  
  streaming_config = config.merge(
    interim_results: true,
    max_alternatives: 2
  )
  
  begin
    client.streaming_recognize(audio_chunks, streaming_config) do |response|
      response.results.each do |result|
        status = result.is_final ? "FINAL" : "INTERIM"
        stability = result.stability.round(2)
        
        puts "[#{status}] Stability: #{stability}"
        result.alternatives.each_with_index do |alternative, i|
          puts "  #{i + 1}. #{alternative.transcript} (confidence: #{alternative.confidence.round(2)})"
        end
        puts
      end
    end
  rescue RivaProxy::Error => e
    puts "Streaming recognition error: #{e.message}"
  end

  # Example 3: Recognition with speaker diarization
  puts "\n=== Speaker Diarization Example ==="
  
  diarization_config = config.merge(
    diarization: {
      enable_speaker_diarization: true,
      min_speaker_count: 2,
      max_speaker_count: 4
    }
  )
  
  begin
    response = client.recognize(audio_data, diarization_config)
    
    response.results.each do |result|
      result.alternatives.each do |alternative|
        puts "Transcript: #{alternative.transcript}"
        
        if alternative.words.any?
          puts "Speaker information:"
          alternative.words.each do |word|
            puts "  Speaker #{word.speaker_tag}: #{word.word} (#{word.start_time}s - #{word.end_time}s)"
          end
        end
      end
    end
  rescue RivaProxy::Error => e
    puts "Diarization error: #{e.message}"
  end
end

if __FILE__ == $0
  main
end