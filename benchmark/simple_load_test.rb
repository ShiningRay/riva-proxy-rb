#!/usr/bin/env ruby

require 'net/http'
require 'uri'
require 'json'
require 'benchmark'
require 'concurrent-ruby'

# 简单的 HTTP 负载测试工具
class SimpleLoadTest
  def initialize(options = {})
    @base_url = options[:base_url] || 'http://127.0.0.1:8080'
    @audio_file = options[:audio_file] || '16k16bit.wav'
    @concurrent_requests = options[:concurrent_requests] || 5
    @total_requests = options[:total_requests] || 20
    @results = []
  end

  def run
    puts "🚀 开始简单负载测试"
    puts "📡 目标服务器: #{@base_url}"
    puts "🎵 音频文件: #{@audio_file}"
    puts "🔄 并发请求数: #{@concurrent_requests}"
    puts "📊 总请求数: #{@total_requests}"
    puts "=" * 50

    unless File.exist?(@audio_file)
      puts "❌ 音频文件不存在: #{@audio_file}"
      return
    end

    # 预热请求
    puts "🔥 预热服务器..."
    warmup_request
    
    # 执行负载测试
    puts "⚡ 开始负载测试..."
    
    total_time = Benchmark.realtime do
      run_concurrent_requests
    end

    # 输出结果
    print_results(total_time)
  end

  private

  def warmup_request
    begin
      send_upload_request
      puts "✅ 预热完成"
    rescue => e
      puts "⚠️  预热失败: #{e.message}"
    end
  end

  def run_concurrent_requests
    # 计算每批次的请求数
    requests_per_batch = [@concurrent_requests, @total_requests].min
    batches = (@total_requests.to_f / requests_per_batch).ceil
    
    batches.times do |batch|
      remaining_requests = @total_requests - (batch * requests_per_batch)
      current_batch_size = [requests_per_batch, remaining_requests].min
      
      puts "📦 批次 #{batch + 1}/#{batches}: #{current_batch_size} 个请求"
      
      # 并发执行当前批次
      promises = []
      current_batch_size.times do |i|
        request_id = batch * requests_per_batch + i + 1
        promise = Concurrent::Promise.execute do
          execute_request(request_id)
        end
        promises << promise
      end
      
      # 等待当前批次完成
      batch_results = promises.map(&:value)
      @results.concat(batch_results)
      
      # 显示批次结果
      successful = batch_results.count { |r| r[:success] }
      puts "  ✅ 成功: #{successful}/#{current_batch_size}"
    end
  end

  def execute_request(request_id)
    result = {
      request_id: request_id,
      success: false,
      response_time: 0,
      status_code: nil,
      error: nil,
      response_size: 0
    }

    start_time = Time.now
    
    begin
      response = send_upload_request
      end_time = Time.now
      
      result[:response_time] = end_time - start_time
      result[:status_code] = response.code.to_i
      result[:success] = response.code == '200'
      result[:response_size] = response.body.bytesize
      
      if result[:success]
        # 验证响应内容
        response_data = JSON.parse(response.body)
        if response_data['results'] && response_data['results'].any?
          result[:transcript_length] = response_data['results'][0]['alternatives'][0]['transcript'].length rescue 0
        end
      else
        result[:error] = "HTTP #{response.code}"
      end
      
    rescue => e
      result[:error] = e.message
      result[:response_time] = Time.now - start_time
    end
    
    # 实时输出进度
    status = result[:success] ? "✅" : "❌"
    puts "  #{status} 请求 #{request_id}: #{(result[:response_time] * 1000).round(0)}ms"
    
    result
  end

  def send_upload_request
    uri = URI("#{@base_url}/recognize")
    
    # 创建 multipart 表单数据
    boundary = "----WebKitFormBoundary#{rand(1000000000000000000)}"
    
    form_data = []
    
    # 添加配置参数
    config = {
      'language_code' => 'en-US',
      'sample_rate_hertz' => '16000',
      'encoding' => 'LINEAR_PCM',
      'enable_word_time_offsets' => 'true',
      'enable_automatic_punctuation' => 'true'
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
    http.read_timeout = 30
    http.open_timeout = 10
    
    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = "multipart/form-data; boundary=#{boundary}"
    request['Content-Length'] = body.bytesize.to_s
    request.body = body
    
    http.request(request)
  end

  def print_results(total_time)
    puts "\n" + "=" * 60
    puts "📊 负载测试结果报告"
    puts "=" * 60
    
    successful_requests = @results.select { |r| r[:success] }
    failed_requests = @results.reject { |r| r[:success] }
    
    # 基本统计
    puts "📈 基本统计:"
    puts "  总请求数: #{@results.size}"
    puts "  成功请求: #{successful_requests.size}"
    puts "  失败请求: #{failed_requests.size}"
    puts "  成功率: #{(successful_requests.size.to_f / @results.size * 100).round(2)}%"
    puts "  总耗时: #{total_time.round(2)}s"
    
    if successful_requests.any?
      response_times = successful_requests.map { |r| r[:response_time] }
      
      puts "\n⏱️  响应时间统计 (成功请求):"
      puts "  平均响应时间: #{(response_times.sum / response_times.size * 1000).round(0)}ms"
      puts "  最快响应: #{(response_times.min * 1000).round(0)}ms"
      puts "  最慢响应: #{(response_times.max * 1000).round(0)}ms"
      puts "  中位数: #{(percentile(response_times, 50) * 1000).round(0)}ms"
      puts "  95% 响应时间: #{(percentile(response_times, 95) * 1000).round(0)}ms"
      puts "  99% 响应时间: #{(percentile(response_times, 99) * 1000).round(0)}ms"
      
      # 吞吐量计算
      throughput = successful_requests.size / total_time
      puts "\n🚀 性能指标:"
      puts "  吞吐量: #{throughput.round(2)} 请求/秒"
      puts "  平均并发: #{(@concurrent_requests * response_times.sum / total_time).round(2)}"
      
      # 响应大小统计
      response_sizes = successful_requests.map { |r| r[:response_size] }
      if response_sizes.any?
        puts "  平均响应大小: #{(response_sizes.sum / response_sizes.size / 1024.0).round(2)} KB"
      end
    end
    
    # 错误分析
    if failed_requests.any?
      puts "\n❌ 错误分析:"
      error_counts = failed_requests.group_by { |r| r[:error] || "HTTP #{r[:status_code]}" }
      error_counts.each do |error, requests|
        puts "  #{error}: #{requests.size} 次"
      end
    end
    
    # 性能建议
    puts "\n💡 性能建议:"
    avg_response_time = successful_requests.any? ? 
      (successful_requests.map { |r| r[:response_time] }.sum / successful_requests.size * 1000) : 0
    
    if avg_response_time > 5000
      puts "  ⚠️  平均响应时间较长 (#{avg_response_time.round(0)}ms)，建议:"
      puts "     - 检查服务器资源使用情况"
      puts "     - 优化 gRPC 连接池"
      puts "     - 考虑增加服务器实例"
    elsif avg_response_time > 2000
      puts "  ⚡ 响应时间适中 (#{avg_response_time.round(0)}ms)，可以考虑:"
      puts "     - 进一步优化音频处理流程"
      puts "     - 调整服务器配置"
    else
      puts "  ✅ 响应时间良好 (#{avg_response_time.round(0)}ms)"
    end
    
    if failed_requests.size > @results.size * 0.05
      puts "  ⚠️  错误率较高 (#{(failed_requests.size.to_f / @results.size * 100).round(2)}%)，建议检查:"
      puts "     - 服务器稳定性"
      puts "     - 网络连接质量"
      puts "     - 服务器负载能力"
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
  require 'optparse'
  
  options = {}
  
  OptionParser.new do |opts|
    opts.banner = "用法: #{$0} [选项]"
    
    opts.on("-u", "--url URL", "服务器 URL (默认: http://127.0.0.1:8080)") do |url|
      options[:base_url] = url
    end
    
    opts.on("-f", "--file FILE", "音频文件路径 (默认: 16k16bit.wav)") do |file|
      options[:audio_file] = file
    end
    
    opts.on("-c", "--concurrent N", Integer, "并发请求数 (默认: 5)") do |n|
      options[:concurrent_requests] = n
    end
    
    opts.on("-n", "--requests N", Integer, "总请求数 (默认: 20)") do |n|
      options[:total_requests] = n
    end
    
    opts.on("--help", "显示帮助信息") do
      puts opts
      exit
    end
  end.parse!
  
  load_test = SimpleLoadTest.new(options)
  load_test.run
end