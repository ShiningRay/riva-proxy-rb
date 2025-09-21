require 'faye/websocket'
# require 'eventmachine'
require 'json'
require 'base64'
require 'logger'
require 'securerandom'
require 'rack'
# require 'thin'
# require 'rack/handler' # not available in Rack 3
# require 'rackup/handler/thin'
require 'rack/handler/puma'
require_relative 'client'

module RivaProxy
  class WebSocketProxy
    # add ssl accessors
    attr_reader :host, :port, :riva_host, :riva_port, :logger, :ssl_cert, :ssl_key, :ssl_verify_mode

    def initialize(options = {})
      @host = options[:host] || '0.0.0.0'
      @port = options[:port] || 8080
      @riva_host = options[:riva_host] || ENV['RIVA_HOST'] || 'localhost'
      @riva_port = options[:riva_port] || ENV['RIVA_PORT']&.to_i || 50_051
      @riva_timeout = options[:riva_timeout] || ENV['RIVA_TIMEOUT']&.to_i || 30
      @logger = options[:logger] || Logger.new(STDOUT)
      @connections = {}
      # ssl options
      @ssl_cert = options[:ssl_cert] || ENV.fetch('WEBSOCKET_SSL_CERT', nil)
      @ssl_key = options[:ssl_key] || ENV.fetch('WEBSOCKET_SSL_KEY', nil)
      @ssl_verify_mode = options[:ssl_verify_mode] || ENV['WEBSOCKET_SSL_VERIFY_MODE'] || 'none'

      setup_logger
    end

    def start
      @logger.info "Starting WebSocket proxy server on #{@host}:#{@port}"
      @logger.info "Proxying to Riva gRPC server at #{@riva_host}:#{@riva_port}"

      # Create a simple Rack app for WebSocket handling
      app = lambda do |env|
        request = Rack::Request.new(env)

        # Handle POST /recognize for file upload recognition
        if request.post? && request.path == '/recognize'
          handle_file_recognition(request)
        elsif Faye::WebSocket.websocket?(env)
          ws = Faye::WebSocket.new(env)
          connection_id = SecureRandom.uuid

          ws.on :open do |event|
            handle_new_connection(ws, connection_id)
          end

          ws.on :message do |event|
            # puts event
            handle_message(connection_id, event.data)
          end

          ws.on :close do |event|
            handle_connection_close(connection_id)
          end

          # Return async response
          ws.rack_response
        else
          # Return 404 for non-WebSocket requests
          [404, { 'Content-Type' => 'text/plain' }, ['Not Found']]
        end
      end

      # Graceful shutdown
      Signal.trap('INT') { stop }
      Signal.trap('TERM') { stop }

      # Start the server (support SSL when cert/key provided)
      if @ssl_cert && @ssl_key
        bind = "ssl://#{@host}:#{@port}?key=#{@ssl_key}&cert=#{@ssl_cert}&verify_mode=#{@ssl_verify_mode}"
        @logger.info "SSL enabled (WSS). Using cert=#{@ssl_cert}, key=#{@ssl_key}, verify_mode=#{@ssl_verify_mode}"
        @server = Rack::Handler::Puma.run(app, Host: bind, Verbose: true) do |server|
          @logger.info "WebSocket proxy server started successfully (wss://#{@host}:#{@port})"
        end
      else
        @server = Rack::Handler::Puma.run(app, Host: @host, Port: @port) do |server|
          @logger.info "WebSocket proxy server started successfully (ws://#{@host}:#{@port})"
        end
      end
      # # use thin as server
      # # thin cannot correctly start websocket, i don't know why
      # thin = Rackup::Handler.get('thin')
      # thin.run(app, Host: '0.0.0.0', Port: port) do |server|
      #   if @ssl_cert && @ssl_key
      #     server.ssl_options = {
      #       private_key_file: @ssl_cert,
      #       cert_chain_file: @ssl_key
      #     }
      #     server.ssl = true
      #   end
      # end
    end

    def stop
      @logger.info 'Stopping WebSocket proxy server...'

      # Close all active connections
      @connections.each do |_, connection_data|
        close_grpc_session(connection_data[:grpc_client], connection_data[:stream])
      end
      @connections.clear

      EM.stop if EM.reactor_running?
      @logger.info 'WebSocket proxy server stopped'
    end

    def handle_new_connection(ws, connection_id)
      @logger.info "New WebSocket connection: #{connection_id}"

      # Initialize gRPC client for this connection
      grpc_client = RivaProxy::Client.new(
        host: @riva_host,
        port: @riva_port,
        timeout: @riva_timeout
      )

      @connections[connection_id] = {
        websocket: ws,
        grpc_client: grpc_client,
        stream: nil,
        config_sent: false,
        last_config: nil
      }
    end

    def handle_message(connection_id, message)
      connection_data = @connections[connection_id]
      return unless connection_data

      begin
        # 仅用于处理配置与 JSON 音频消息：尝试解析 JSON；否则一律按原始 Base64 音频处理
        begin
          data = JSON.parse(message)
          if data['type'] == 'config'
            handle_config_message(connection_id, data)
            return
          elsif data['type'] == 'audio' && data['audio']
            handle_audio_message(connection_id, data)
            return
          end
          # 解析成功但不是已支持的 JSON 类型，继续走原始音频处理
        rescue JSON::ParserError
          # 不是 JSON，走原始音频处理
        end

        # 将消息当作原始 Base64 编码的音频数据处理
        handle_raw_audio_message(connection_id, message)
      rescue StandardError => e
        @logger.error "Error handling message: #{e.message}"
        @logger.error e.backtrace.join("\n")
        send_error(connection_id, 'Internal server error')
      end
    end

    def handle_connection_close(connection_id)
      @logger.info "WebSocket connection closed: #{connection_id}"

      connection_data = @connections[connection_id]
      return unless connection_data

      close_grpc_session(connection_data[:grpc_client], connection_data[:stream])
      @connections.delete(connection_id)
    end

    private

    def setup_logger
      @logger.level = Logger::INFO
      @logger.formatter = proc do |severity, datetime, progname, msg|
        "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
      end
    end

    def handle_file_recognition(request)
      # Parse multipart form data to get uploaded file
      file_param = request.params['audio'] || request.params['file']

      unless file_param && file_param.is_a?(Hash) && file_param[:tempfile]
        return [400, { 'Content-Type' => 'application/json' },
                [JSON.generate({ error: 'Missing audio file. Please upload via form field "audio" or "file".' })]]
      end

      # Read audio data from uploaded file
      audio_data = file_param[:tempfile].read
      file_param[:tempfile].rewind # Reset for potential reuse

      # Parse recognition config from request parameters
      config = {
        language_code: request.params['language_code'] || 'en-US',
        sample_rate_hertz: (request.params['sample_rate_hertz'] || 16_000).to_i,
        encoding: (request.params['encoding'] || 'LINEAR_PCM').to_sym,
        max_alternatives: (request.params['max_alternatives'] || 1).to_i,
        enable_automatic_punctuation: request.params['enable_automatic_punctuation'] == 'true',
        enable_word_time_offsets: request.params['enable_word_time_offsets'] == 'true',
        model: request.params['model'] || ''
      }

      @logger.info "File recognition request: #{file_param[:filename]} (#{audio_data.bytesize} bytes), config: #{config}"

      # Create gRPC client for recognition
      grpc_client = RivaProxy::Client.new(
        host: @riva_host,
        port: @riva_port,
        timeout: @riva_timeout
      )

      # Call non-streaming recognize
      response = grpc_client.recognize(audio_data, config)

      # Convert gRPC response to JSON
      result = {
        results: response.results.map do |result|
          {
            alternatives: result.alternatives.map do |alt|
              {
                transcript: alt.transcript,
                confidence: alt.confidence,
                words: alt.words.map do |word|
                  {
                    word: word.word,
                    start_time: extract_time_in_seconds(word.start_time),
                    end_time: extract_time_in_seconds(word.end_time),
                    confidence: word.confidence,
                    speaker_tag: word.speaker_tag
                  }
                end
              }
            end
          }
        end
      }

      [200, { 'Content-Type' => 'application/json' }, [JSON.generate(result)]]
    rescue RivaProxy::RecognitionError => e
      @logger.error "Recognition error: #{e.message}"
      [422, { 'Content-Type' => 'application/json' },
       [JSON.generate({ error: "Recognition failed: #{e.message}" })]]
    rescue RivaProxy::ConnectionError => e
      @logger.error "Connection error: #{e.message}"
      [503, { 'Content-Type' => 'application/json' },
       [JSON.generate({ error: "Service unavailable: #{e.message}" })]]
    rescue StandardError => e
      @logger.error "Unexpected error in file recognition: #{e.message}"
      @logger.error e.backtrace.join("\n")
      [500, { 'Content-Type' => 'application/json' },
       [JSON.generate({ error: 'Internal server error' })]]
    end

    def handle_config_message(connection_id, data)
      connection_data = @connections[connection_id]
      config = data['config'] || {}

      @logger.info "Received config for connection #{connection_id}: #{config}"

      # Default configuration
      recognition_config = {
        encoding: config['encoding']&.to_sym || :LINEAR_PCM,
        sample_rate_hertz: config['sample_rate_hertz'] || 16_000,
        language_code: config['language_code'] || 'en-US',
        enable_automatic_punctuation: config['enable_automatic_punctuation'] || true,
        enable_word_time_offsets: config['enable_word_time_offsets'] || true,
        interim_results: config['interim_results'] || true,
        max_alternatives: config['max_alternatives'] || 1
      }

      # Add diarization config if provided
      recognition_config[:diarization] = config['diarization'] if config['diarization']

      # Remember last config for potential reconnection
      connection_data[:last_config] = recognition_config

      begin
        # Start streaming recognition session
        grpc_client = connection_data[:grpc_client]

        # Create streaming session
        stream = grpc_client.create_streaming_session(recognition_config, &build_response_handler(connection_id))

        connection_data[:stream] = stream
        connection_data[:config_sent] = true

        @logger.info "Started gRPC streaming session for connection #{connection_id}"
        send_message(connection_id, { type: 'ready', message: 'Ready to receive audio data' })
      rescue StandardError => e
        @logger.error "Failed to start gRPC session: #{e.message}"
        send_error(connection_id, "Failed to start recognition session: #{e.message}")
      end
    end

    def handle_audio_message(connection_id, data)
      connection_data = @connections[connection_id]

      # 若尚未配置（未建立会话），由服务器端发送默认配置并启动会话
      handle_config_message(connection_id, { 'config' => {} }) unless connection_data[:config_sent]

      unless data['audio']
        send_error(connection_id, 'Missing audio data')
        return
      end

      begin
        # Decode base64 audio data
        audio_data = Base64.decode64(data['audio'])
        @logger.debug "Received audio data: #{audio_data.length} bytes"

        # Ensure stream is available (auto-restart if needed)
        ensure_stream(connection_id)

        # Send audio data to gRPC stream
        stream = connection_data[:stream]
        if stream
          stream.send_audio(audio_data)
        else
          send_error(connection_id, 'No active streaming session')
        end
      rescue StandardError => e
        @logger.error "Error processing audio data: #{e.message}"
        send_error(connection_id, "Error processing audio data: #{e.message}")
      end
    end

    def handle_raw_audio_message(connection_id, base64_audio)
      connection_data = @connections[connection_id]

      # 若尚未配置（未建立会话），由服务器端发送默认配置并启动会话
      handle_config_message(connection_id, { 'config' => {} }) unless connection_data[:config_sent]

      begin
        # Decode base64 audio data directly
        audio_data = Base64.decode64(base64_audio.strip)
        @logger.debug "Received raw audio data: #{audio_data.length} bytes"

        # Ensure stream is available (auto-restart if needed)
        ensure_stream(connection_id)

        # Send audio data to gRPC stream
        stream = connection_data[:stream]
        if stream
          stream.send_audio(audio_data)
        else
          send_error(connection_id, 'No active streaming session')
        end
      rescue StandardError => e
        @logger.error "Error processing raw audio data: #{e.message}"
        send_error(connection_id, "Error processing raw audio data: #{e.message}")
      end
    end

    def send_recognition_response(connection_id, response)
      connection_data = @connections[connection_id]
      return unless connection_data

      # Handle error responses
      if response.is_a?(Hash) && response[:error]
        handle_stream_error(connection_id, response[:error])
        return
      end

      # Convert gRPC response to JSON
      response_data = {
        type: 'recognition',
        results: response.results.map do |result|
          {
            alternatives: result.alternatives.map do |alt|
              {
                transcript: alt.transcript,
                confidence: alt.confidence,
                words: alt.words.map do |word|
                  {
                    word: word.word,
                    start_time: extract_time_in_seconds(word.start_time),
                    end_time: extract_time_in_seconds(word.end_time),
                    confidence: word.confidence,
                    speaker_tag: word.speaker_tag
                  }
                end
              }
            end,
            is_final: result.is_final,
            stability: result.stability
          }
        end
      }

      send_message(connection_id, response_data)
    end

    def send_message(connection_id, data)
      connection_data = @connections[connection_id]
      return unless connection_data

      ws = connection_data[:websocket]
      return unless ws && ws.ready_state == Faye::WebSocket::API::OPEN

      ws.send(JSON.generate(data))
    end

    def send_error(connection_id, message)
      send_message(connection_id, { type: 'error', message: message })
    end

    # Build response handler which routes either recognition or error handling
    def build_response_handler(connection_id)
      proc do |response|
        if response.is_a?(Hash) && response[:error]
          handle_stream_error(connection_id, response[:error])
        else
          send_recognition_response(connection_id, response)
        end
      end
    end

    # Handle gRPC stream errors and try to restart on transient issues
    def handle_stream_error(connection_id, error)
      err_msg = error.respond_to?(:message) ? error.message : error.to_s
      @logger.warn "Recognition error for #{connection_id}: #{err_msg}"

      if retryable_grpc_error?(error)
        begin
          restart_stream(connection_id)
          send_message(connection_id, { type: 'info', message: 'gRPC stream restarted after transient error' })
          return
        rescue StandardError => e
          @logger.error "Failed to restart gRPC stream: #{e.message}"
        end
      end

      send_error(connection_id, "Recognition error: #{err_msg}")
    end

    def retryable_grpc_error?(error)
      code = error.respond_to?(:code) ? error.code : nil
      msg = error.respond_to?(:message) ? error.message : error.to_s
      return true if msg =~ /Deadline Exceeded/i
      return true if msg =~ /UNAVAILABLE|Unavailable/i
      return true if msg =~ /CANCELLED|Canceled/i
      if code.is_a?(Integer)
        return [4, 14, 1].include?(code) # DEADLINE_EXCEEDED=4, UNAVAILABLE=14, CANCELLED=1
      end

      false
    end

    def restart_stream(connection_id)
      connection_data = @connections[connection_id]
      raise 'Unknown connection' unless connection_data

      # Close old stream
      begin
        connection_data[:stream]&.close
      rescue StandardError => _e
      end

      config = connection_data[:last_config] || {}
      grpc_client = connection_data[:grpc_client]
      stream = grpc_client.create_streaming_session(config, &build_response_handler(connection_id))
      connection_data[:stream] = stream
      connection_data[:config_sent] = true
      @logger.info "Restarted gRPC streaming session for connection #{connection_id}"
    end

    def ensure_stream(connection_id)
      connection_data = @connections[connection_id]
      return unless connection_data

      stream = connection_data[:stream]
      return unless stream.nil? || (stream.respond_to?(:closed?) && stream.closed?)

      restart_stream(connection_id)
    end

    def close_grpc_session(grpc_client, stream)
      return unless stream

      begin
        stream.close if stream.respond_to?(:close)
        @logger.info 'Closed gRPC streaming session'
      rescue StandardError => e
        @logger.error "Error closing gRPC session: #{e.message}"
      end
    end
  end
end

# Convert protobuf Duration / numeric / hash time to Float seconds
def extract_time_in_seconds(ts)
  return 0.0 if ts.nil?

  # Google::Protobuf::Duration has seconds/nanos
  if ts.respond_to?(:seconds) && ts.respond_to?(:nanos)
    ts.seconds.to_f + (ts.nanos.to_f / 1_000_000_000.0)
  elsif ts.is_a?(Hash)
    secs = (ts[:seconds] || ts['seconds'] || 0).to_f
    nanos = (ts[:nanos] || ts['nanos'] || 0).to_f
    secs + (nanos / 1_000_000_000.0)
  elsif ts.respond_to?(:to_f)
    ts.to_f
  else
    0.0
  end
end
