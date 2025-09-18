# Riva Proxy Ruby

A Ruby client library for NVIDIA Riva Automatic Speech Recognition (ASR) service with built-in mock server for testing.

## Features

- **gRPC Client**: Full-featured client for NVIDIA Riva ASR service
- **Streaming & Non-streaming Recognition**: Support for both real-time and batch processing
- **Speaker Diarization**: Identify different speakers in audio
- **Multiple Audio Formats**: Support for various audio encodings
- **Mock Server**: Built-in mock server for testing and development
- **Comprehensive Testing**: Full test suite with RSpec
- **Ruby 3.4+ Support**: Modern Ruby features and performance

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'riva-proxy-rb'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install riva-proxy-rb
```

## Quick Start

### Setup

```bash
# Install dependencies and generate protobuf code
rake setup
```

### Basic Usage

```ruby
require 'riva_proxy'

# Initialize client
client = RivaProxy::Client.new(
  host: 'your-riva-server.com',
  port: 50051
)

# Test connection
if client.health_check
  puts "Connected to Riva server successfully!"
end

# Non-streaming recognition
audio_data = File.read('audio.wav', mode: 'rb')
config = {
  encoding: :LINEAR_PCM,
  sample_rate_hertz: 16000,
  language_code: 'en-US',
  enable_automatic_punctuation: true
}

response = client.recognize(audio_data, config)
puts "Transcript: #{response.results.first.alternatives.first.transcript}"
```

### Streaming Recognition

```ruby
# Streaming recognition
audio_chunks = read_audio_in_chunks('audio.wav')
config = {
  encoding: :LINEAR_PCM,
  sample_rate_hertz: 16000,
  language_code: 'en-US',
  interim_results: true
}

client.streaming_recognize(audio_chunks, config) do |response|
  response.results.each do |result|
    alternative = result.alternatives.first
    status = result.is_final ? 'FINAL' : 'INTERIM'
    puts "[#{status}] #{alternative.transcript}"
  end
end
```

### Speaker Diarization

```ruby
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

response = client.recognize(audio_data, config)
response.results.first.alternatives.first.words.each do |word|
  puts "Speaker #{word.speaker_tag}: #{word.word} (#{word.start_time}s - #{word.end_time}s)"
end
```

## Mock Server for Testing

The library includes a mock server for testing and development:

### Start Mock Server

```bash
# Using rake task
rake server

# Or directly
ruby bin/mock_server 50051
```

### Use Mock Server in Tests

```ruby
# Start mock server
server = RivaProxy::MockServer.new(port: 50053)
server_thread = Thread.new { server.start(blocking: false) }

# Connect client to mock server
client = RivaProxy::Client.new(host: 'localhost', port: 50053)

# Use normally
response = client.recognize(audio_data)

# Cleanup
server.stop
server_thread.kill
```

## Configuration Options

### Recognition Config

```ruby
config = {
  # Audio encoding (required)
  encoding: :LINEAR_PCM,  # :LINEAR_PCM, :FLAC, :MULAW, :ALAW
  
  # Sample rate (required)
  sample_rate_hertz: 16000,
  
  # Language (required)
  language_code: 'en-US',  # 'en-US', 'zh-CN', 'es-ES', etc.
  
  # Optional features
  enable_automatic_punctuation: true,
  enable_word_time_offsets: true,
  enable_word_confidence: true,
  max_alternatives: 3,
  
  # Streaming specific
  interim_results: true,
  single_utterance: false,
  
  # Speaker diarization
  diarization: {
    enable_speaker_diarization: true,
    min_speaker_count: 2,
    max_speaker_count: 6
  }
}
```

### Client Options

```ruby
client = RivaProxy::Client.new(
  host: 'localhost',
  port: 50051,
  timeout: 30,           # Connection timeout in seconds
  credentials: nil,      # gRPC credentials (for secure connections)
  metadata: {}          # Additional metadata
)
```

## Development

### Setup Development Environment

```bash
# Clone repository
git clone https://github.com/your-org/riva-proxy-rb.git
cd riva-proxy-rb

# Install dependencies
bundle install

# Generate protobuf code
rake generate_proto
```

### Running Tests

```bash
# Run unit tests
rake spec

# Run integration tests (requires mock server)
rake spec_integration

# Run all tests
rake spec_all

# Check code quality
rake quality
```

### Available Rake Tasks

```bash
rake -T
```

## API Reference

### RivaProxy::Client

#### Methods

- `initialize(host:, port:, timeout: 30, credentials: nil, metadata: {})` - Create new client
- `health_check` - Test server connection
- `recognize(audio_data, config = {})` - Non-streaming recognition
- `streaming_recognize(audio_chunks, config = {}, &block)` - Streaming recognition

### RivaProxy::MockServer

#### Methods

- `initialize(port: 50051)` - Create mock server
- `start(blocking: true)` - Start server
- `stop` - Stop server

## Error Handling

```ruby
begin
  response = client.recognize(audio_data)
rescue RivaProxy::ConnectionError => e
  puts "Connection failed: #{e.message}"
rescue RivaProxy::RecognitionError => e
  puts "Recognition failed: #{e.message}"
rescue RivaProxy::Error => e
  puts "General error: #{e.message}"
end
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/riva_proxy.