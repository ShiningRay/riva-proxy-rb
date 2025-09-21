#!/usr/bin/env ruby

require 'optparse'
require 'json'

# 综合基准测试套件
class BenchmarkSuite
  def initialize(options = {})
    @base_url = options[:base_url] || 'http://127.0.0.1:8080'
    @ws_url = options[:ws_url] || 'ws://127.0.0.1:8080'
    @audio_file = options[:audio_file] || '16k16bit.wav'
    @output_file = options[:output_file]
    @results = {}
  end

  def run
    puts "🚀 开始综合基准测试套件"
    puts "📡 HTTP URL: #{@base_url}"
    puts "📡 WebSocket URL: #{@ws_url}"
    puts "🎵 音频文件: #{@audio_file}"
    puts "=" * 60

    # 检查音频文件
    unless File.exist?(@audio_file)
      puts "❌ 音频文件不存在: #{@audio_file}"
      return
    end

    # 检查服务器连接
    unless check_server_connectivity
      puts "❌ 无法连接到服务器，请确保服务器正在运行"
      return
    end

    puts "✅ 服务器连接正常，开始基准测试..."
    puts

    # 运行各种测试场景
    run_test_scenarios

    # 生成综合报告
    generate_comprehensive_report

    # 保存结果到文件
    save_results_to_file if @output_file
  end

  private

  def check_server_connectivity
    require 'net/http'
    require 'uri'
    
    begin
      uri = URI("#{@base_url}/")
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 5
      http.read_timeout = 5
      response = http.get(uri.path)
      true
    rescue => e
      puts "⚠️  HTTP 连接检查失败: #{e.message}"
      false
    end
  end

  def run_test_scenarios
    scenarios = [
      {
        name: "轻负载 HTTP 测试",
        type: :http,
        concurrent: 2,
        requests: 10,
        description: "测试基本 HTTP 文件上传功能"
      },
      {
        name: "中等负载 HTTP 测试", 
        type: :http,
        concurrent: 5,
        requests: 25,
        description: "测试中等并发下的 HTTP 性能"
      },
      {
        name: "高负载 HTTP 测试",
        type: :http,
        concurrent: 10,
        requests: 50,
        description: "测试高并发下的 HTTP 性能"
      },
      {
        name: "极限负载 HTTP 测试",
        type: :http,
        concurrent: 20,
        requests: 100,
        description: "测试极限并发下的 HTTP 性能"
      }
    ]

    scenarios.each_with_index do |scenario, index|
      puts "📊 场景 #{index + 1}/#{scenarios.size}: #{scenario[:name]}"
      puts "   #{scenario[:description]}"
      puts "   并发: #{scenario[:concurrent]}, 请求: #{scenario[:requests]}"
      
      result = run_scenario(scenario)
      @results[scenario[:name]] = result
      
      puts "   ✅ 完成 - 成功率: #{result[:success_rate]}%, 平均响应时间: #{result[:avg_response_time]}ms"
      puts
      
      # 在测试之间稍作休息，避免服务器过载
      sleep 2
    end
  end

  def run_scenario(scenario)
    case scenario[:type]
    when :http
      run_http_scenario(scenario)
    when :websocket
      run_websocket_scenario(scenario)
    else
      { error: "未知的测试类型: #{scenario[:type]}" }
    end
  end

  def run_http_scenario(scenario)
    # 构建命令
    cmd = [
      "ruby", "benchmark/simple_load_test.rb",
      "-u", @base_url,
      "-f", @audio_file,
      "-c", scenario[:concurrent].to_s,
      "-n", scenario[:requests].to_s
    ].join(" ")

    # 执行测试并捕获输出
    start_time = Time.now
    output = `#{cmd} 2>&1`
    end_time = Time.now
    exit_status = $?.exitstatus

    # 解析结果
    parse_http_results(output, end_time - start_time, exit_status)
  end

  def run_websocket_scenario(scenario)
    # WebSocket 测试实现
    # 这里可以添加 WebSocket 测试逻辑
    {
      success_rate: 0,
      avg_response_time: 0,
      throughput: 0,
      error: "WebSocket 测试尚未实现"
    }
  end

  def parse_http_results(output, duration, exit_status)
    result = {
      duration: duration.round(2),
      exit_status: exit_status,
      raw_output: output
    }

    if exit_status == 0
      # 解析成功率
      if output =~ /成功率: ([\d.]+)%/
        result[:success_rate] = $1.to_f
      end

      # 解析平均响应时间
      if output =~ /平均响应时间: (\d+)ms/
        result[:avg_response_time] = $1.to_i
      end

      # 解析吞吐量
      if output =~ /吞吐量: ([\d.]+) 请求\/秒/
        result[:throughput] = $1.to_f
      end

      # 解析总请求数和成功请求数
      if output =~ /总请求数: (\d+)/
        result[:total_requests] = $1.to_i
      end

      if output =~ /成功请求: (\d+)/
        result[:successful_requests] = $1.to_i
      end

      # 解析响应时间统计
      if output =~ /最快响应: (\d+)ms/
        result[:min_response_time] = $1.to_i
      end

      if output =~ /最慢响应: (\d+)ms/
        result[:max_response_time] = $1.to_i
      end

      if output =~ /95% 响应时间: (\d+)ms/
        result[:p95_response_time] = $1.to_i
      end

    else
      result[:error] = "测试执行失败，退出码: #{exit_status}"
    end

    result
  end

  def generate_comprehensive_report
    puts "=" * 80
    puts "📊 综合基准测试报告"
    puts "=" * 80
    puts "🕒 测试时间: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
    puts "🎵 音频文件: #{@audio_file} (#{File.size(@audio_file)} bytes)" if File.exist?(@audio_file)
    puts

    # 性能概览
    puts "📈 性能概览:"
    successful_tests = @results.select { |name, result| result[:success_rate] && result[:success_rate] > 0 }
    
    if successful_tests.any?
      max_throughput = successful_tests.map { |name, result| result[:throughput] || 0 }.max
      min_response_time = successful_tests.map { |name, result| result[:avg_response_time] || Float::INFINITY }.min
      avg_success_rate = successful_tests.map { |name, result| result[:success_rate] || 0 }.sum / successful_tests.size

      puts "  🚀 最高吞吐量: #{max_throughput.round(2)} 请求/秒"
      puts "  ⚡ 最快平均响应: #{min_response_time}ms"
      puts "  ✅ 平均成功率: #{avg_success_rate.round(2)}%"
    else
      puts "  ❌ 没有成功的测试结果"
    end
    puts

    # 详细结果
    puts "📋 详细测试结果:"
    @results.each_with_index do |(name, result), index|
      puts "#{index + 1}. #{name}"
      
      if result[:error]
        puts "   ❌ 错误: #{result[:error]}"
      else
        puts "   📊 成功率: #{result[:success_rate] || 'N/A'}%"
        puts "   ⏱️  平均响应时间: #{result[:avg_response_time] || 'N/A'}ms"
        puts "   🚀 吞吐量: #{result[:throughput] || 'N/A'} 请求/秒"
        puts "   📈 响应时间范围: #{result[:min_response_time] || 'N/A'}ms - #{result[:max_response_time] || 'N/A'}ms"
        puts "   📊 95% 响应时间: #{result[:p95_response_time] || 'N/A'}ms"
        puts "   🕒 测试耗时: #{result[:duration] || 'N/A'}s"
      end
      puts
    end

    # 性能建议
    generate_performance_recommendations
  end

  def generate_performance_recommendations
    puts "💡 性能建议和分析:"
    
    successful_tests = @results.select { |name, result| result[:success_rate] && result[:success_rate] > 0 }
    
    if successful_tests.empty?
      puts "  ❌ 所有测试都失败了，建议检查:"
      puts "     - 服务器是否正常运行"
      puts "     - 网络连接是否正常"
      puts "     - 音频文件是否存在且格式正确"
      return
    end

    # 分析成功率趋势
    success_rates = successful_tests.map { |name, result| result[:success_rate] }
    if success_rates.any? { |rate| rate < 95 }
      puts "  ⚠️  发现成功率低于 95% 的测试，建议:"
      puts "     - 检查服务器资源使用情况"
      puts "     - 优化错误处理机制"
      puts "     - 考虑增加重试机制"
    end

    # 分析响应时间趋势
    response_times = successful_tests.map { |name, result| result[:avg_response_time] }.compact
    if response_times.any?
      avg_response_time = response_times.sum / response_times.size
      
      if avg_response_time > 100
        puts "  ⚠️  平均响应时间较长 (#{avg_response_time.round(0)}ms)，建议:"
        puts "     - 优化音频处理算法"
        puts "     - 检查 gRPC 连接性能"
        puts "     - 考虑使用连接池"
      elsif avg_response_time > 50
        puts "  ⚡ 响应时间适中 (#{avg_response_time.round(0)}ms)，可以考虑:"
        puts "     - 进一步优化热点代码"
        puts "     - 调整服务器配置"
      else
        puts "  ✅ 响应时间表现良好 (#{avg_response_time.round(0)}ms)"
      end
    end

    # 分析吞吐量趋势
    throughputs = successful_tests.map { |name, result| result[:throughput] }.compact
    if throughputs.any?
      max_throughput = throughputs.max
      
      if max_throughput < 50
        puts "  ⚠️  吞吐量较低 (#{max_throughput.round(2)} 请求/秒)，建议:"
        puts "     - 增加服务器线程数"
        puts "     - 优化 I/O 操作"
        puts "     - 考虑水平扩展"
      elsif max_throughput < 100
        puts "  ⚡ 吞吐量适中 (#{max_throughput.round(2)} 请求/秒)"
      else
        puts "  ✅ 吞吐量表现优秀 (#{max_throughput.round(2)} 请求/秒)"
      end
    end

    # 并发性能分析
    puts "\n🔄 并发性能分析:"
    concurrent_tests = @results.select { |name, result| name.include?("负载") }
    if concurrent_tests.size >= 2
      # 比较不同并发级别的性能
      puts "  📊 不同并发级别的性能表现:"
      concurrent_tests.each do |name, result|
        if result[:success_rate] && result[:avg_response_time]
          puts "     #{name}: 成功率 #{result[:success_rate]}%, 响应时间 #{result[:avg_response_time]}ms"
        end
      end
    end

    puts "\n🎯 总体建议:"
    puts "  1. 定期运行基准测试以监控性能变化"
    puts "  2. 在生产环境中设置性能监控和告警"
    puts "  3. 根据实际负载情况调整服务器配置"
    puts "  4. 考虑实施缓存策略以提高响应速度"
  end

  def save_results_to_file
    report_data = {
      timestamp: Time.now.iso8601,
      test_config: {
        base_url: @base_url,
        ws_url: @ws_url,
        audio_file: @audio_file,
        audio_file_size: File.exist?(@audio_file) ? File.size(@audio_file) : nil
      },
      results: @results,
      summary: generate_summary
    }

    File.write(@output_file, JSON.pretty_generate(report_data))
    puts "📄 测试结果已保存到: #{@output_file}"
  end

  def generate_summary
    successful_tests = @results.select { |name, result| result[:success_rate] && result[:success_rate] > 0 }
    
    return { error: "没有成功的测试" } if successful_tests.empty?

    {
      total_tests: @results.size,
      successful_tests: successful_tests.size,
      max_throughput: successful_tests.map { |name, result| result[:throughput] || 0 }.max,
      min_avg_response_time: successful_tests.map { |name, result| result[:avg_response_time] || Float::INFINITY }.min,
      avg_success_rate: successful_tests.map { |name, result| result[:success_rate] || 0 }.sum / successful_tests.size
    }
  end
end

# 命令行使用
if __FILE__ == $0
  options = {}
  
  OptionParser.new do |opts|
    opts.banner = "用法: #{$0} [选项]"
    
    opts.on("-u", "--url URL", "HTTP 服务器 URL (默认: http://127.0.0.1:8080)") do |url|
      options[:base_url] = url
    end
    
    opts.on("-w", "--ws-url URL", "WebSocket URL (默认: ws://127.0.0.1:8080)") do |url|
      options[:ws_url] = url
    end
    
    opts.on("-f", "--file FILE", "音频文件路径 (默认: 16k16bit.wav)") do |file|
      options[:audio_file] = file
    end
    
    opts.on("-o", "--output FILE", "结果输出文件 (JSON 格式)") do |file|
      options[:output_file] = file
    end
    
    opts.on("--help", "显示帮助信息") do
      puts opts
      exit
    end
  end.parse!
  
  benchmark_suite = BenchmarkSuite.new(options)
  benchmark_suite.run
end