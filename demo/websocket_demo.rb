#!/usr/bin/env ruby

require 'bundler/setup'
require 'faye/websocket'
require 'eventmachine'
require 'json'
require 'base64'
require 'uri'

class WebSocketDemo
  def initialize(server_url = 'ws://localhost:8080')
    @server_url = server_url
    @connected = false
    @config_sent = false
  end

  def run
    puts '🚀 启动WebSocket代理演示'
    puts "📡 连接到: #{@server_url}"

    normalized_url = normalize_ws_url(@server_url)
    puts "🔗 使用WebSocket URL: #{normalized_url}"

    EM.run do
      @ws = Faye::WebSocket::Client.new(normalized_url)

      @ws.on :open do |event|
        puts '✅ WebSocket连接已建立'
        @connected = true

        # 发送配置
        send_config

        # 等待一秒后发送测试音频
        EM.add_timer(1) { send_test_audio }

        # 5秒后关闭连接
        EM.add_timer(5) { close_connection }
      end

      @ws.on :message do |event|
        handle_message(event.data)
      end

      @ws.on :close do |event|
        puts "🔌 WebSocket连接已关闭 (代码: #{event.code}, 原因: #{event.reason})"
        @connected = false
        EM.stop
      end

      @ws.on :error do |event|
        puts "❌ WebSocket错误: #{event.message}"
        EM.stop
      end
    end
  end

  private

  def normalize_ws_url(url)
    begin
      uri = URI.parse(url)
    rescue URI::InvalidURIError
      puts "⚠️ 提供的地址无效: #{url}"
      return url
    end

    case uri.scheme
    when 'http'
      uri.scheme = 'ws'
    when 'https'
      uri.scheme = 'wss'
    when 'ws', 'wss'
      # already correct
    else
      puts "⚠️ 未知协议 #{uri.scheme}，将按原样尝试"
    end

    uri.to_s
  end

  def send_config
    config = {
      type: 'config',
      config: {
        encoding: 'LINEAR_PCM',
        sample_rate_hertz: 16_000,
        language_code: 'en-US',
        max_alternatives: 1,
        enable_automatic_punctuation: true,
        enable_word_time_offsets: true
      }
    }

    puts "📤 发送配置: #{config[:config][:language_code]}, #{config[:config][:sample_rate_hertz]}Hz"
    @ws.send(JSON.generate(config))
    @config_sent = true
  end

  def send_test_audio
    return unless @connected && @config_sent

    # 生成测试音频数据 (16kHz, 16-bit, mono, 1秒的正弦波)
    sample_rate = 16_000
    duration = 1.0
    frequency = 440.0 # A4音符

    samples = []
    (0...(sample_rate * duration)).each do |i|
      # 生成16-bit PCM样本
      sample = (Math.sin(2 * Math::PI * frequency * i / sample_rate) * 32_767).to_i
      # 转换为小端字节序
      samples << [sample].pack('s<')
    end

    audio_data = samples.join
    encoded_audio = Base64.encode64(audio_data)

    audio_message = {
      type: 'audio',
      audio: encoded_audio
    }

    puts "🎵 发送测试音频数据 (#{audio_data.length} 字节, #{duration}秒)"
    @ws.send(JSON.generate(audio_message))
  end

  def handle_message(data)
    message = JSON.parse(data)

    case message['type']
    when 'result'
      puts "🎯 识别结果: #{message['result']}"
    when 'status'
      puts "ℹ️  状态: #{message['message']}"
    when 'error'
      puts "⚠️  错误: #{message['message']}"
    else
      puts "📨 收到消息: #{message}"
    end
  rescue JSON::ParserError => e
    puts "❌ 无法解析消息: #{e.message}"
  end

  def close_connection
    return unless @connected

    puts '👋 关闭连接...'
    @ws.close
  end
end

# 检查命令行参数
server_url = ARGV[0] || 'ws://localhost:8080'

puts <<~BANNER
  ╔══════════════════════════════════════════════════════════════╗
  ║                    WebSocket代理演示                         ║
  ║                                                              ║
  ║  这个演示将连接到WebSocket代理服务器并发送测试音频数据        ║
  ║  确保WebSocket代理服务器正在运行:                            ║
  ║  ./bin/websocket_proxy                                       ║
  ╚══════════════════════════════════════════════════════════════╝

BANNER

demo = WebSocketDemo.new(server_url)
demo.run
