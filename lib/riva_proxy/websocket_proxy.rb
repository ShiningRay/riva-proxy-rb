require 'faye/websocket'
require 'eventmachine'
require 'json'
require 'base64'
require 'logger'
require 'securerandom'
require 'rack'
# require 'rack/handler' # not available in Rack 3
# require 'rack/handler/thin'
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
      @riva_port = options[:riva_port] || ENV['RIVA_PORT']&.to_i || 50051
      @riva_timeout = options[:riva_timeout] || ENV['RIVA_TIMEOUT']&.to_i || 30
      @logger = options[:logger] || Logger.new(STDOUT)
      @connections = {}
      # ssl options
      @ssl_cert = options[:ssl_cert] || ENV['WEBSOCKET_SSL_CERT']
      @ssl_key = options[:ssl_key] || ENV['WEBSOCKET_SSL_KEY']
      @ssl_verify_mode = options[:ssl_verify_mode] || ENV['WEBSOCKET_SSL_VERIFY_MODE'] || 'none'
      
      setup_logger
    end

    def start
      @logger.info "Starting WebSocket proxy server on #{@host}:#{@port}"
      @logger.info "Proxying to Riva gRPC server at #{@riva_host}:#{@riva_port}"

      EM.run do
        # Create a simple Rack app for WebSocket handling
        app = lambda do |env|
          if Faye::WebSocket.websocket?(env)
            ws = Faye::WebSocket.new(env)
            connection_id = SecureRandom.uuid
            
            ws.on :open do |event|
              handle_new_connection(ws, connection_id)
            end
            
            ws.on :message do |event|
              handle_message(connection_id, event.data)
            end
            
            ws.on :close do |event|
              handle_connection_close(connection_id)
            end
            
            # Return async response
            ws.rack_response
          else
            # Return 404 for non-WebSocket requests
            [404, {'Content-Type' => 'text/plain'}, ['Not Found']]
          end
        end
        
        # Start the server (support SSL when cert/key provided)
        if @ssl_cert && @ssl_key
          bind = "ssl://#{@host}:#{@port}?key=#{@ssl_key}&cert=#{@ssl_cert}&verify_mode=#{@ssl_verify_mode}"
          @logger.info "SSL enabled (WSS). Using cert=#{@ssl_cert}, key=#{@ssl_key}, verify_mode=#{@ssl_verify_mode}"
          @server = Rack::Handler::Puma.run(app, Host: bind) do |server|
            @logger.info "WebSocket proxy server started successfully (wss://#{@host}:#{@port})"
          end
        else
          @server = Rack::Handler::Puma.run(app, Host: @host, Port: @port) do |server|
            @logger.info "WebSocket proxy server started successfully (ws://#{@host}:#{@port})"
          end
        end
        
        # Graceful shutdown
        Signal.trap('INT') { stop }
        Signal.trap('TERM') { stop }
      end
    end

    def stop
      @logger.info "Stopping WebSocket proxy server..."
      
      # Close all active connections
      @connections.each do |_, connection_data|
        close_grpc_session(connection_data[:grpc_client], connection_data[:stream])
      end
      @connections.clear
      
      EM.stop if EM.reactor_running?
      @logger.info "WebSocket proxy server stopped"
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
        config_sent: false
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
      rescue => e
        @logger.error "Error handling message: #{e.message}"
        @logger.error e.backtrace.join("\n")
        send_error(connection_id, "Internal server error")
      end
    end

    def handle_connection_close(connection_id)
      @logger.info "WebSocket connection closed: #{connection_id}"
      
      connection_data = @connections[connection_id]
      if connection_data
        close_grpc_session(connection_data[:grpc_client], connection_data[:stream])
        @connections.delete(connection_id)
      end
    end

    private

    def setup_logger
      @logger.level = Logger::INFO
      @logger.formatter = proc do |severity, datetime, progname, msg|
        "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
      end
    end

    def handle_config_message(connection_id, data)
      connection_data = @connections[connection_id]
      config = data['config'] || {}
      
      @logger.info "Received config for connection #{connection_id}: #{config}"
      
      # Default configuration
      recognition_config = {
        encoding: config['encoding']&.to_sym || :LINEAR_PCM,
        sample_rate_hertz: config['sample_rate_hertz'] || 16000,
        language_code: config['language_code'] || 'en-US',
        enable_automatic_punctuation: config['enable_automatic_punctuation'] || true,
        enable_word_time_offsets: config['enable_word_time_offsets'] || true,
        interim_results: config['interim_results'] || true,
        max_alternatives: config['max_alternatives'] || 1
      }
      
      # Add diarization config if provided
      if config['diarization']
        recognition_config[:diarization] = config['diarization']
      end
      
      begin
        # Start streaming recognition session
        grpc_client = connection_data[:grpc_client]
        
        # Create streaming session
        stream = grpc_client.create_streaming_session(recognition_config) do |response|
          # Forward response to WebSocket client
          send_recognition_response(connection_id, response)
        end
        
        connection_data[:stream] = stream
        connection_data[:config_sent] = true
        
        @logger.info "Started gRPC streaming session for connection #{connection_id}"
        send_message(connection_id, { type: 'ready', message: 'Ready to receive audio data' })
        
      rescue => e
        @logger.error "Failed to start gRPC session: #{e.message}"
        send_error(connection_id, "Failed to start recognition session: #{e.message}")
      end
    end

    def handle_audio_message(connection_id, data)
      connection_data = @connections[connection_id]
      
      # 若尚未配置（未建立会话），由服务器端发送默认配置并启动会话
      unless connection_data[:config_sent]
        handle_config_message(connection_id, { 'config' => {} })
      end
      
      unless data['audio']
        send_error(connection_id, "Missing audio data")
        return
      end
      
      begin
        # Decode base64 audio data
        audio_data = Base64.decode64(data['audio'])
        @logger.debug "Received audio data: #{audio_data.length} bytes"
        
        # Send audio data to gRPC stream
        stream = connection_data[:stream]
        if stream
          stream.send_audio(audio_data)
        else
          send_error(connection_id, "No active streaming session")
        end
        
      rescue => e
        @logger.error "Error processing audio data: #{e.message}"
        send_error(connection_id, "Error processing audio data: #{e.message}")
      end
    end

    def handle_raw_audio_message(connection_id, base64_audio)
      connection_data = @connections[connection_id]
      
      # 若尚未配置（未建立会话），由服务器端发送默认配置并启动会话
      unless connection_data[:config_sent]
        handle_config_message(connection_id, { 'config' => {} })
      end
      
      begin
        # Decode base64 audio data directly
        audio_data = Base64.decode64(base64_audio.strip)
        @logger.debug "Received raw audio data: #{audio_data.length} bytes"
        
        # Send audio data to gRPC stream
        stream = connection_data[:stream]
        if stream
          stream.send_audio(audio_data)
        else
          send_error(connection_id, "No active streaming session")
        end
        
      rescue => e
        @logger.error "Error processing raw audio data: #{e.message}"
        send_error(connection_id, "Error processing raw audio data: #{e.message}")
      end
    end

    def send_recognition_response(connection_id, response)
      connection_data = @connections[connection_id]
      return unless connection_data
      
      # Handle error responses
      if response.is_a?(Hash) && response[:error]
        send_error(connection_id, "Recognition error: #{response[:error].message}")
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
                    start_time: word.start_time&.seconds || 0,
                    end_time: word.end_time&.seconds || 0,
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
      if ws && ws.ready_state == Faye::WebSocket::API::OPEN
        ws.send(JSON.generate(data))
      end
    end

    def send_error(connection_id, message)
      send_message(connection_id, { type: 'error', message: message })
    end

    def close_grpc_session(grpc_client, stream)
      return unless stream
      
      begin
        stream.close if stream.respond_to?(:close)
        @logger.info "Closed gRPC streaming session"
      rescue => e
        @logger.error "Error closing gRPC session: #{e.message}"
      end
    end
  end
end