require 'grpc'
require_relative 'riva_proxy/proto/riva_asr_pb'
require_relative 'riva_proxy/proto/riva_asr_services_pb'
require_relative 'riva_proxy/client'
require_relative 'riva_proxy/streaming_session'
require_relative 'riva_proxy/websocket_proxy'

module RivaProxy
  class Error < StandardError; end
  class ConnectionError < Error; end
  class RecognitionError < Error; end
end