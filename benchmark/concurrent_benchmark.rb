#!/usr/bin/env ruby

require 'benchmark'
require 'concurrent-ruby'
require 'faye/websocket'
require 'eventmachine'
require 'net/http'
require 'uri'
require 'json'
require 'logger'
require 'optparse'

# WebSocket 代理并发性能基准测试
class ConcurrentBenchmark
  attr_reader :logger, :results

  def initialize(options = {})
    @proxy_url = options[:proxy_url] || 'ws://127.0.0.1:8080'
    @http_url = options[:http_url] || 'http://127.0.0.1:8080'
    @audio_file = options[:audio_file] || '16k16bit.wav'
    @concurrent_connections = options[:concurrent_connections] || 10
    @messages_per_connection = options[:messages_per_connection] || 5
    @test_duration = options[:test_duration] || 30
    @logger = Logger.new(STDOUT)
    @results = {
      websocket: { success: 0, failed: 0, total_time: 0, response_times: [] },
      http_upload: { success: 0, failed: 0, total_time: 0, response_times: [] }
    }
    
    setup_logger
  end

  def run_all_benchmarks
    puts "╔══════════════════════════════════════════════════════════════╗"
    puts "║                    WebSocket 代理并发基准测试                 ║"
    puts "║                                                              ║"
    puts "║  测试配置:                                                   ║"
    puts "║  - WebSocket URL: #{@proxy_url.ljust(42)} ║"
    puts "║  - HTTP URL: #{@http_url.ljust(47)} ║"
    puts "║  - 并发连接数: #{@concurrent_connections.to_s.ljust(44)} ║"
    puts "║  - 每连接消息数: #{@messages_per_connection.to_s.ljust(42)} ║"
    puts "║  - 测试时长: #{@test_duration}s#{' ' * 45} ║"
    puts "╚══════════════════════════════════════════════════════════════╝"
    puts

    # 检查音频文件
    unless File.exist?(@audio_file)
      @logger.error "音频文件不存在: #{@audio_file}"
      return
    end

    # 运行 WebSocket 流式识别基准测试
    puts "🚀 开始 WebSocket 流式识别并发测试..."
    websocket_benchmark

    puts "\n" + "="*60 + "\n"

    # 运行 HTTP 文件上传基准测试
    puts "🚀 开始 HTTP 文件上传并发测试..."
    http_upload_benchmark

    # 输出综合报告
    puts "\n" + "="*60 + "\n"
    print_summary_report
  end

  private

  def setup_logger
    @logger.level = Logger::INFO
    @logger.formatter = proc do |severity, datetime, progname, msg|
      "[#{datetime.strftime('%H:%M:%S')}] #{severity}: #{msg}\n"
    end
  end

  def websocket_benchmark
    @logger.info "启动 #{@concurrent_connections} 个并发 WebSocket 连接"
    
    start_time = Time.now
    promises = []
    
    @concurrent_connections.times do |i|
      promise = Concurrent::Promise.execute do
        test_websocket_connection(i)
      end
      promises << promise
    end
    
    # 等待所有连接完成
    results = promises.map(&:value)
    end_time = Time.now
    
    @results[:websocket][:total_time] = end_time - start_time
    
    # 统计结果
    results.each do |result|
      if result[:success]
        @results[:websocket][:success] += result[:messages_sent]
        @results[:websocket][:response_times].concat(result[:response_times])
      else
        @results[:websocket][:failed] += 1
      end
    end
    
    print_websocket_results
  end

  def test_websocket_connection(connection_id)
    result = {
      connection_id: connection_id,
      success: false,
      messages_sent: 0,
      response_times: [],
      error: nil
    }

    begin
      EM.run do
        ws = Faye::WebSocket::Client.new(@proxy_url)
        messages_sent = 0
        start_times = {}
        
        ws.on :open do |event|
          @logger.debug "连接 #{connection_id} 已建立"
          
          # 发送配置消息
          config = {
            type: 'config',
            config: {
              language_code: 'en-US',
              sample_rate_hertz: 16000,
              encoding: 'LINEAR_PCM',
              enable_word_time_offsets: true
            }
          }
          ws.send(JSON.generate(config))
          
          # 读取音频数据
          audio_data = File.binread(@audio_file)
          chunk_size = audio_data.size / @messages_per_connection
          
          # 分块发送音频数据
          @messages_per_connection.times do |i|
            start_pos = i * chunk_size
            end_pos = (i == @messages_per_connection - 1) ? audio_data.size : (i + 1) * chunk_size
            chunk = audio_data[start_pos...end_pos]
            
            message_id = "#{connection_id}_#{i}"
            start_times[message_id] = Time.now
            
            audio_message = {
              type: 'audio',
              audio: Base64.strict_encode64(chunk)
            }
            ws.send(JSON.generate(audio_message))
            messages_sent += 1
          end
          
          result[:messages_sent] = messages_sent
        end
        
        ws.on :message do |event|
          response_time = Time.now
          data = JSON.parse(event.data)
          
          if data['type'] == 'recognition' && data['transcript']
            # 计算响应时间（简化处理）
            if start_times.any?
              oldest_start = start_times.values.min
              result[:response_times] << (response_time - oldest_start)
            end
          end
        end
        
        ws.on :close do |event|
          @logger.debug "连接 #{connection_id} 已关闭"
          result[:success] = true
          EM.stop
        end
        
        ws.on :error do |event|
          @logger.error "连接 #{connection_id} 错误: #{event.message}"
          result[:error] = event.message
          EM.stop
        end
        
        # 设置超时
        EM.add_timer(@test_duration) do
          ws.close
        end
      end
    rescue => e
      result[:error] = e.message
      @logger.error "连接 #{connection_id} 异常: #{e.message}"
    end
    
    result
  end

  def http_upload_benchmark
    @logger.info "启动 #{@concurrent_connections} 个并发 HTTP 上传请求"
    
    start_time = Time.now
    promises = []
    
    @concurrent_connections.times do |i|
      promise = Concurrent::Promise.execute do
        test_http_upload(i)
      end
      promises << promise
    end
    
    # 等待所有请求完成
    results = promises.map(&:value)
    end_time = Time.now
    
    @results[:http_upload][:total_time] = end_time - start_time
    
    # 统计结果
    results.each do |result|
      if result[:success]
        @results[:http_upload][:success] += 1
        @results[:http_upload][:response_times] << result[:response_time]
      else
        @results[:http_upload][:failed] += 1
      end
    end
    
    print_http_results
  end

  def test_http_upload(request_id)
    result = {
      request_id: request_id,
      success: false,
      response_time: 0,
      error: nil
    }

    begin
      start_time = Time.now
      
      uri = URI("#{@http_url}/recognize")
      
      # 创建 multipart 表单数据
      boundary = "----WebKitFormBoundary#{rand(1000000000000000000)}"
      
      form_data = []
      
      # 添加配置参数
      config = {
        'language_code' => 'en-US',
        'sample_rate_hertz' => '16000',
        'encoding' => 'LINEAR_PCM',
        'enable_word_time_offsets' => 'true'
      }
      
      config.each do |key, value|
        form_data << "--#{boundary}\r\n"
        form_data << "Content-Disposition: form-data; name=\"#{key}\"\r\n\r\n"
        form_data << "#{value}\r\n"
      end
      
      # 添加音频文件
      form_data << "--#{boundary}\r\n"
      form_data << "Content-Disposition: form-data; name=\"audio\"; filename=\"#{File.basename(@audio_file)}\"\r\n"
      form_data << "Content-Type: audio/wav\r\n\r\n"
      
      audio_content = File.binread(@audio_file)
      form_data << audio_content
      form_data << "\r\n--#{boundary}--\r\n"
      
      body = form_data.join
      
      # 发送 HTTP 请求
      http = Net::HTTP.new(uri.host, uri.port)
      http.read_timeout = @test_duration
      
      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = "multipart/form-data; boundary=#{boundary}"
      request['Content-Length'] = body.bytesize.to_s
      request.body = body
      
      response = http.request(request)
      end_time = Time.now
      
      result[:response_time] = end_time - start_time
      result[:success] = response.code == '200'
      
      unless result[:success]
        result[:error] = "HTTP #{response.code}: #{response.body[0..100]}"
      end
      
    rescue => e
      result[:error] = e.message
      @logger.error "请求 #{request_id} 异常: #{e.message}"
    end
    
    result
  end

  def print_websocket_results
    puts "\n📊 WebSocket 流式识别测试结果:"
    puts "  ✅ 成功消息数: #{@results[:websocket][:success]}"
    puts "  ❌ 失败连接数: #{@results[:websocket][:failed]}"
    puts "  ⏱️  总耗时: #{@results[:websocket][:total_time].round(2)}s"
    
    if @results[:websocket][:response_times].any?
      response_times = @results[:websocket][:response_times]
      puts "  📈 响应时间统计:"
      puts "     - 平均: #{(response_times.sum / response_times.size).round(3)}s"
      puts "     - 最小: #{response_times.min.round(3)}s"
      puts "     - 最大: #{response_times.max.round(3)}s"
      puts "     - 95%: #{percentile(response_times, 95).round(3)}s"
    end
    
    throughput = @results[:websocket][:success] / @results[:websocket][:total_time]
    puts "  🚀 吞吐量: #{throughput.round(2)} 消息/秒"
  end

  def print_http_results
    puts "\n📊 HTTP 文件上传测试结果:"
    puts "  ✅ 成功请求数: #{@results[:http_upload][:success]}"
    puts "  ❌ 失败请求数: #{@results[:http_upload][:failed]}"
    puts "  ⏱️  总耗时: #{@results[:http_upload][:total_time].round(2)}s"
    
    if @results[:http_upload][:response_times].any?
      response_times = @results[:http_upload][:response_times]
      puts "  📈 响应时间统计:"
      puts "     - 平均: #{response_times.sum / response_times.size.round(3)}s"
      puts "     - 最小: #{response_times.min.round(3)}s"
      puts "     - 最大: #{response_times.max.round(3)}s"
      puts "     - 95%: #{percentile(response_times, 95).round(3)}s"
    end
    
    if @results[:http_upload][:total_time] > 0
      throughput = @results[:http_upload][:success] / @results[:http_upload][:total_time]
      puts "  🚀 吞吐量: #{throughput.round(2)} 请求/秒"
    end
  end

  def print_summary_report
    puts "📋 综合性能报告"
    puts "=" * 50
    
    total_success = @results[:websocket][:success] + @results[:http_upload][:success]
    total_failed = @results[:websocket][:failed] + @results[:http_upload][:failed]
    total_requests = total_success + total_failed
    
    puts "📊 总体统计:"
    puts "  - 总请求数: #{total_requests}"
    puts "  - 成功数: #{total_success}"
    puts "  - 失败数: #{total_failed}"
    puts "  - 成功率: #{((total_success.to_f / total_requests) * 100).round(2)}%"
    
    puts "\n🏆 性能指标:"
    puts "  - WebSocket 并发连接数: #{@concurrent_connections}"
    puts "  - HTTP 并发请求数: #{@concurrent_connections}"
    puts "  - 音频文件大小: #{File.size(@audio_file)} 字节"
    
    # 内存和 CPU 使用建议
    puts "\n💡 优化建议:"
    if @results[:websocket][:failed] > 0
      puts "  ⚠️  WebSocket 连接失败率较高，考虑:"
      puts "     - 增加服务器连接池大小"
      puts "     - 调整超时设置"
      puts "     - 检查网络稳定性"
    end
    
    if @results[:http_upload][:failed] > 0
      puts "  ⚠️  HTTP 请求失败率较高，考虑:"
      puts "     - 增加服务器线程数"
      puts "     - 优化文件上传处理"
      puts "     - 检查内存使用情况"
    end
    
    puts "\n🎯 下一步测试建议:"
    puts "  - 逐步增加并发数测试极限"
    puts "  - 测试不同大小的音频文件"
    puts "  - 监控服务器资源使用情况"
    puts "  - 进行长时间稳定性测试"
  end

  def percentile(array, percentile)
    sorted = array.sort
    index = (percentile / 100.0) * (sorted.length - 1)
    if index == index.to_i
      sorted[index.to_i]
    else
      lower = sorted[index.to_i]
      upper = sorted[index.to_i + 1]
      lower + (upper - lower) * (index - index.to_i)
    end
  end
end

# 命令行参数解析
if __FILE__ == $0
  options = {}
  
  OptionParser.new do |opts|
    opts.banner = "用法: #{$0} [选项]"
    
    opts.on("-w", "--websocket-url URL", "WebSocket URL (默认: ws://127.0.0.1:8080)") do |url|
      options[:proxy_url] = url
    end
    
    opts.on("-h", "--http-url URL", "HTTP URL (默认: http://127.0.0.1:8080)") do |url|
      options[:http_url] = url
    end
    
    opts.on("-f", "--audio-file FILE", "音频文件路径 (默认: 16k16bit.wav)") do |file|
      options[:audio_file] = file
    end
    
    opts.on("-c", "--concurrent N", Integer, "并发连接数 (默认: 10)") do |n|
      options[:concurrent_connections] = n
    end
    
    opts.on("-m", "--messages N", Integer, "每连接消息数 (默认: 5)") do |n|
      options[:messages_per_connection] = n
    end
    
    opts.on("-t", "--timeout N", Integer, "测试超时时间 (默认: 30s)") do |n|
      options[:test_duration] = n
    end
    
    opts.on("--help", "显示帮助信息") do
      puts opts
      exit
    end
  end.parse!
  
  benchmark = ConcurrentBenchmark.new(options)
  benchmark.run_all_benchmarks
end