require 'spec_helper'
require 'riva_proxy/websocket_proxy'
require 'faye/websocket'
require 'eventmachine'
require 'json'
require 'base64'

RSpec.describe RivaProxy::WebSocketProxy do
  let(:proxy_options) do
    {
      host: '127.0.0.1',
      port: 8081,  # Use different port for testing
      riva_host: 'localhost',
      riva_port: 50051,
      riva_timeout: 5,
      logger: Logger.new(StringIO.new)  # Suppress logs during tests
    }
  end

  let(:proxy) { described_class.new(proxy_options) }

  describe '#initialize' do
    it 'sets default values' do
      expect(proxy.host).to eq('127.0.0.1')
      expect(proxy.port).to eq(8081)
      expect(proxy.riva_host).to eq('localhost')
      expect(proxy.riva_port).to eq(50051)
    end

    it 'uses environment variables when provided' do
      ENV['RIVA_HOST'] = 'test-host'
      ENV['RIVA_PORT'] = '9999'
      
      proxy = described_class.new
      expect(proxy.riva_host).to eq('test-host')
      expect(proxy.riva_port).to eq(9999)
      
      # Clean up
      ENV.delete('RIVA_HOST')
      ENV.delete('RIVA_PORT')
    end
  end

  describe '#handle_new_connection' do
    let(:mock_ws) { double('websocket') }
    let(:connection_id) { 'test-connection-id' }

    before do
      allow(RivaProxy::Client).to receive(:new).and_return(double('grpc_client'))
    end

    it 'creates a new connection entry' do
      proxy.handle_new_connection(mock_ws, connection_id)
      
      expect(proxy.instance_variable_get(:@connections)).to have_key(connection_id)
      connection_data = proxy.instance_variable_get(:@connections)[connection_id]
      expect(connection_data[:websocket]).to eq(mock_ws)
      expect(connection_data[:config_sent]).to be false
    end
  end

  describe '#handle_message' do
    let(:mock_ws) { double('websocket') }
    let(:connection_id) { 'test-connection-id' }
    let(:mock_grpc_client) { double('grpc_client') }

    before do
      allow(RivaProxy::Client).to receive(:new).and_return(mock_grpc_client)
      proxy.handle_new_connection(mock_ws, connection_id)
    end

    context 'with config message' do
      let(:config_message) do
        {
          'type' => 'config',
          'config' => {
            'encoding' => 'LINEAR_PCM',
            'sample_rate_hertz' => 16000,
            'language_code' => 'en-US'
          }
        }.to_json
      end

      it 'handles config message' do
        mock_stream = double('stream')
        allow(mock_grpc_client).to receive(:create_streaming_session).and_return(mock_stream)
        allow(mock_ws).to receive(:ready_state).and_return(Faye::WebSocket::API::OPEN)
        allow(mock_ws).to receive(:send)

        proxy.handle_message(connection_id, config_message)

        connection_data = proxy.instance_variable_get(:@connections)[connection_id]
        expect(connection_data[:config_sent]).to be true
        expect(connection_data[:stream]).to eq(mock_stream)
      end
    end

    context 'with audio message' do
      let(:audio_data) { 'test audio data' }
      let(:audio_message) do
        {
          'type' => 'audio',
          'audio' => Base64.encode64(audio_data)
        }.to_json
      end

      context 'when config is sent' do
        let(:mock_stream) { double('stream') }

        before do
          connection_data = proxy.instance_variable_get(:@connections)[connection_id]
          connection_data[:config_sent] = true
          connection_data[:stream] = mock_stream
        end

        it 'processes audio data' do
          expect(mock_stream).to receive(:send_audio).with(audio_data)

          proxy.handle_message(connection_id, audio_message)
        end
      end

      context 'when config is not sent' do
        it 'auto-starts session with default config and processes audio' do
          mock_stream = double('stream')
          allow(mock_grpc_client).to receive(:create_streaming_session).and_return(mock_stream)
          allow(mock_stream).to receive(:send_audio)
          allow(mock_ws).to receive(:ready_state).and_return(Faye::WebSocket::API::OPEN)
          allow(mock_ws).to receive(:send) # for 'ready' message

          expect(mock_stream).to receive(:send_audio).with(audio_data)

          proxy.handle_message(connection_id, audio_message)

          connection_data = proxy.instance_variable_get(:@connections)[connection_id]
          expect(connection_data[:config_sent]).to be true
          expect(connection_data[:stream]).to eq(mock_stream)
        end
      end
    end

    context 'with raw base64 audio data' do
      let(:audio_data) { 'test audio data' }
      let(:base64_audio) { Base64.strict_encode64(audio_data) }

      context 'when config is sent' do
        let(:mock_stream) { double('stream') }

        before do
          connection_data = proxy.instance_variable_get(:@connections)[connection_id]
          connection_data[:config_sent] = true
          connection_data[:stream] = mock_stream
        end

        it 'processes raw base64 audio data' do
          expect(mock_stream).to receive(:send_audio).with(audio_data)

          proxy.handle_message(connection_id, base64_audio)
        end
      end

      context 'when config is not sent' do
        it 'auto-starts session with default config and processes raw audio' do
          mock_stream = double('stream')
          allow(mock_grpc_client).to receive(:create_streaming_session).and_return(mock_stream)
          allow(mock_stream).to receive(:send_audio)
          allow(mock_ws).to receive(:ready_state).and_return(Faye::WebSocket::API::OPEN)
          allow(mock_ws).to receive(:send) # for 'ready' message

          expect(mock_stream).to receive(:send_audio).with(audio_data)

          proxy.handle_message(connection_id, base64_audio)

          connection_data = proxy.instance_variable_get(:@connections)[connection_id]
          expect(connection_data[:config_sent]).to be true
          expect(connection_data[:stream]).to eq(mock_stream)
        end
      end
    end

    # removed obsolete error expectation: server auto-initializes default config
   end

  describe '#handle_connection_close' do
    let(:mock_ws) { double('websocket') }
    let(:connection_id) { 'test-connection-id' }
    let(:mock_grpc_client) { double('grpc_client') }
    let(:mock_stream) { double('stream') }

    before do
      allow(RivaProxy::Client).to receive(:new).and_return(mock_grpc_client)
      proxy.handle_new_connection(mock_ws, connection_id)
      
      connection_data = proxy.instance_variable_get(:@connections)[connection_id]
      connection_data[:stream] = mock_stream
    end

    it 'closes gRPC session and removes connection' do
      expect(mock_stream).to receive(:close)

      proxy.handle_connection_close(connection_id)

      expect(proxy.instance_variable_get(:@connections)).not_to have_key(connection_id)
    end
  end

  describe 'message sending methods' do
    let(:mock_ws) { double('websocket') }
    let(:connection_id) { 'test-connection-id' }

    before do
      allow(RivaProxy::Client).to receive(:new).and_return(double('grpc_client'))
      proxy.handle_new_connection(mock_ws, connection_id)
    end

    describe '#send_message' do
      it 'sends JSON message to WebSocket' do
        allow(mock_ws).to receive(:ready_state).and_return(Faye::WebSocket::API::OPEN)
        expect(mock_ws).to receive(:send) do |message|
          data = JSON.parse(message)
          expect(data['type']).to eq('test')
          expect(data['data']).to eq('test data')
        end

        proxy.send(:send_message, connection_id, { type: 'test', data: 'test data' })
      end

      it 'does not send when WebSocket is not open' do
        allow(mock_ws).to receive(:ready_state).and_return(Faye::WebSocket::API::CLOSED)
        expect(mock_ws).not_to receive(:send)

        proxy.send(:send_message, connection_id, { type: 'test' })
      end
    end

    describe '#send_error' do
      it 'sends error message' do
        allow(mock_ws).to receive(:ready_state).and_return(Faye::WebSocket::API::OPEN)
        expect(mock_ws).to receive(:send) do |message|
          data = JSON.parse(message)
          expect(data['type']).to eq('error')
          expect(data['message']).to eq('Test error')
        end

        proxy.send(:send_error, connection_id, 'Test error')
      end
    end
  end
end