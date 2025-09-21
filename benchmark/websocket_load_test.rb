#!/usr/bin/env ruby

require 'websocket-client-simple'
require 'json'
require 'benchmark'
require 'concurrent-ruby'
require 'optparse'

# WebSocket 并发负载测试工具
class WebSocketLoadTest
  def initialize(options = {})
    @ws_url = options[:ws_url] || 'ws://127.0.0.1:8080'
    @audio_file = options[:audio_file] || '16k16bit.wav'
    @concurrent_connections = options[:concurrent_connections] || 5
    @messages_per_connection = options[:messages_per_connection] || 10
    @chunk_size = options[:chunk_size] || 1024
    @results = []
    @audio_data = nil
  end

  def run
    puts "🚀 开始 WebSocket 并发负载测试"
    puts "📡 WebSocket URL: #{@ws_url}"
    puts "🎵 音频文件: #{@audio_file}"
    puts "🔗 并发连接数: #{@concurrent_connections}"
    puts "📨 每连接消息数: #{@messages_per_connection}"
    puts "📦 音频块大小: #{@chunk_size} bytes"
    puts "=" * 60

    unless load_audio_file
      puts "❌ 无法加载音频文件"
      return
    end

    puts "📊 音频文件信息:"
    puts "  文件大小: #{@audio_data.bytesize} bytes"
    puts "  预计音频块数: #{(@audio_data.bytesize.to_f / @chunk_size).ceil}"
    puts

    # 执行负载测试
    total_time = Benchmark.realtime do
      run_concurrent_websocket_test
    end

    # 输出结果
    print_results(total_time)
  end

  private

  def load_audio_file
    return false unless File.exist?(@audio_file)
    
    @audio_data = File.binread(@audio_file)
    true
  rescue => e
    puts "❌ 加载音频文件失败: #{e.message}"
    false
  end

  def run_concurrent_websocket_test
    puts "⚡ 开始 WebSocket 并发测试..."
    
    # 创建并发连接
    promises = []
    @concurrent_connections.times do |i|
      connection_id = i + 1
      promise = Concurrent::Promise.execute do
        test_websocket_connection(connection_id)
      end
      promises << promise
    end
    
    # 等待所有连接完成
    connection_results = promises.map(&:value)
    @results = connection_results.flatten
    
    puts "✅ 所有连接测试完成"
  end

  def test_websocket_connection(connection_id)
    connection_results = []
    connection_start_time = Time.now
    
    begin
      puts "🔗 连接 #{connection_id}: 开始建立 WebSocket 连接"
      
      ws = WebSocket::Client::Simple.connect(@ws_url)
      connection_established = false
      messages_sent = 0
      responses_received = 0
      
      # 连接建立事件
      ws.on :open do
        connection_established = true
        puts "✅ 连接 #{connection_id}: WebSocket 连接已建立"
        
        # 发送配置消息
        config = {
          type: 'config',
          config: {
            language_code: 'en-US',
            sample_rate_hertz: 16000,
            encoding: 'LINEAR_PCM',
            enable_word_time_offsets: true,
            enable_automatic_punctuation: true
          }
        }
        
        ws.send(config.to_json)
        puts "📤 连接 #{connection_id}: 配置消息已发送"
      end
      
      # 消息接收事件
      ws.on :message do |msg|
        response_time = Time.now
        responses_received += 1
        
        begin
          data = JSON.parse(msg.data)
          result = {
            connection_id: connection_id,
            message_id: responses_received,
            success: true,
            response_time: response_time - connection_start_time,
            response_type: data['type'] || 'unknown',
            has_transcript: !!(data['results'] && data['results'].any?),
            transcript_length: 0
          }
          
          if data['results'] && data['results'].any?
            transcript = data['results'][0]['alternatives'][0]['transcript'] rescue ''
            result[:transcript_length] = transcript.length
            puts "📝 连接 #{connection_id}: 收到转录结果 (#{transcript.length} 字符)"
          end
          
          connection_results << result
          
        rescue JSON::ParserError => e
          puts "⚠️  连接 #{connection_id}: JSON 解析错误: #{e.message}"
        end
      end
      
      # 错误处理
      ws.on :error do |e|
        puts "❌ 连接 #{connection_id}: WebSocket 错误: #{e.message}"
      end
      
      # 连接关闭事件
      ws.on :close do |e|
        puts "🔌 连接 #{connection_id}: WebSocket 连接已关闭 (code: #{e.code})"
      end
      
      # 等待连接建立
      sleep 0.1 until connection_established || Time.now - connection_start_time > 5
      
      unless connection_established
        puts "❌ 连接 #{connection_id}: 连接建立超时"
        return connection_results
      end
      
      # 发送音频数据
      @messages_per_connection.times do |msg_index|
        message_start_time = Time.now
        
        # 计算音频块的起始和结束位置
        start_pos = (msg_index * @audio_data.bytesize / @messages_per_connection).to_i
        end_pos = ((msg_index + 1) * @audio_data.bytesize / @messages_per_connection).to_i
        audio_chunk = @audio_data[start_pos...end_pos]
        
        if audio_chunk && audio_chunk.bytesize > 0
          # 发送音频数据
          audio_message = {
            type: 'audio',
            audio: [audio_chunk].pack('m0')  # Base64 编码
          }
          
          ws.send(audio_message.to_json)
          messages_sent += 1
          
          puts "📤 连接 #{connection_id}: 发送音频块 #{msg_index + 1}/#{@messages_per_connection} (#{audio_chunk.bytesize} bytes)"
          
          # 控制发送速率，避免过快发送
          sleep 0.1
        end
      end
      
      # 发送结束消息
      end_message = { type: 'end' }
      ws.send(end_message.to_json)
      puts "🏁 连接 #{connection_id}: 发送结束消息"
      
      # 等待响应
      sleep 2
      
      # 关闭连接
      ws.close
      
      puts "📊 连接 #{connection_id}: 发送 #{messages_sent} 条消息，收到 #{responses_received} 个响应"
      
    rescue => e
      puts "❌ 连接 #{connection_id}: 测试失败: #{e.message}"
      puts e.backtrace.first(3).join("\n") if e.backtrace
    end
    
    connection_results
  end

  def print_results(total_time)
    puts "\n" + "=" * 70
    puts "📊 WebSocket 并发负载测试结果报告"
    puts "=" * 70
    
    successful_messages = @results.select { |r| r[:success] }
    failed_messages = @results.reject { |r| r[:success] }
    
    # 基本统计
    puts "📈 基本统计:"
    puts "  总连接数: #{@concurrent_connections}"
    puts "  总消息数: #{@results.size}"
    puts "  成功消息: #{successful_messages.size}"
    puts "  失败消息: #{failed_messages.size}"
    puts "  成功率: #{(successful_messages.size.to_f / @results.size * 100).round(2)}%" if @results.any?
    puts "  总耗时: #{total_time.round(2)}s"
    
    if successful_messages.any?
      response_times = successful_messages.map { |r| r[:response_time] }
      
      puts "\n⏱️  响应时间统计 (成功消息):"
      puts "  平均响应时间: #{(response_times.sum / response_times.size * 1000).round(0)}ms"
      puts "  最快响应: #{(response_times.min * 1000).round(0)}ms"
      puts "  最慢响应: #{(response_times.max * 1000).round(0)}ms"
      puts "  中位数: #{(percentile(response_times, 50) * 1000).round(0)}ms"
      puts "  95% 响应时间: #{(percentile(response_times, 95) * 1000).round(0)}ms"
      
      # 转录统计
      transcript_messages = successful_messages.select { |r| r[:has_transcript] }
      if transcript_messages.any?
        puts "\n📝 转录统计:"
        puts "  包含转录的消息: #{transcript_messages.size}"
        puts "  转录率: #{(transcript_messages.size.to_f / successful_messages.size * 100).round(2)}%"
        
        transcript_lengths = transcript_messages.map { |r| r[:transcript_length] }
        if transcript_lengths.any?
          puts "  平均转录长度: #{(transcript_lengths.sum.to_f / transcript_lengths.size).round(1)} 字符"
          puts "  最长转录: #{transcript_lengths.max} 字符"
        end
      end
      
      # 吞吐量计算
      if total_time > 0
        throughput = successful_messages.size / total_time
        puts "\n🚀 性能指标:"
        puts "  消息吞吐量: #{throughput.round(2)} 消息/秒"
        puts "  连接吞吐量: #{(@concurrent_connections / total_time).round(2)} 连接/秒"
      end
    end
    
    # 连接统计
    if @results.any?
      puts "\n🔗 连接统计:"
      connection_stats = @results.group_by { |r| r[:connection_id] }
      connection_stats.each do |conn_id, messages|
        successful = messages.count { |m| m[:success] }
        puts "  连接 #{conn_id}: #{successful}/#{messages.size} 成功"
      end
    end
    
    # 性能建议
    puts "\n💡 性能建议:"
    if successful_messages.any?
      avg_response_time = (successful_messages.map { |r| r[:response_time] }.sum / successful_messages.size * 1000)
      
      if avg_response_time > 1000
        puts "  ⚠️  平均响应时间较长 (#{avg_response_time.round(0)}ms)，建议:"
        puts "     - 检查网络延迟"
        puts "     - 优化音频处理流程"
        puts "     - 减少音频块大小"
      elsif avg_response_time > 500
        puts "  ⚡ 响应时间适中 (#{avg_response_time.round(0)}ms)，可以考虑:"
        puts "     - 增加并发连接数测试极限"
        puts "     - 优化音频编码"
      else
        puts "  ✅ 响应时间良好 (#{avg_response_time.round(0)}ms)"
      end
    end
    
    if failed_messages.size > @results.size * 0.05
      puts "  ⚠️  错误率较高 (#{(failed_messages.size.to_f / @results.size * 100).round(2)}%)，建议检查:"
      puts "     - WebSocket 连接稳定性"
      puts "     - 服务器负载能力"
      puts "     - 网络连接质量"
    end
    
    success_rate = @results.any? ? (successful_messages.size.to_f / @results.size) : 0
    if success_rate < 0.95
      puts "  ⚠️  成功率偏低 (#{(success_rate * 100).round(2)}%)，建议:"
      puts "     - 检查服务器资源"
      puts "     - 优化错误处理"
      puts "     - 调整发送速率"
    end
  end

  def percentile(array, percentile)
    return 0 if array.empty?
    sorted = array.sort
    index = (percentile / 100.0) * (sorted.length - 1)
    if index == index.to_i
      sorted[index.to_i]
    else
      lower = sorted[index.to_i]
      upper = sorted[index.to_i + 1] || lower
      lower + (upper - lower) * (index - index.to_i)
    end
  end
end

# 命令行使用
if __FILE__ == $0
  options = {}
  
  OptionParser.new do |opts|
    opts.banner = "用法: #{$0} [选项]"
    
    opts.on("-w", "--ws-url URL", "WebSocket URL (默认: ws://127.0.0.1:8080)") do |url|
      options[:ws_url] = url
    end
    
    opts.on("-f", "--file FILE", "音频文件路径 (默认: 16k16bit.wav)") do |file|
      options[:audio_file] = file
    end
    
    opts.on("-c", "--connections N", Integer, "并发连接数 (默认: 5)") do |n|
      options[:concurrent_connections] = n
    end
    
    opts.on("-m", "--messages N", Integer, "每连接消息数 (默认: 10)") do |n|
      options[:messages_per_connection] = n
    end
    
    opts.on("-s", "--chunk-size N", Integer, "音频块大小 (默认: 1024)") do |n|
      options[:chunk_size] = n
    end
    
    opts.on("--help", "显示帮助信息") do
      puts opts
      exit
    end
  end.parse!
  
  load_test = WebSocketLoadTest.new(options)
  load_test.run
end