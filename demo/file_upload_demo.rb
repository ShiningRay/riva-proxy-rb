#!/usr/bin/env ruby

require 'net/http'
require 'uri'
require 'json'

# Demo script for testing file upload recognition via POST /recognize
class FileUploadDemo
  def initialize(proxy_url = 'http://127.0.0.1:8080')
    @proxy_url = proxy_url
  end

  def upload_and_recognize(audio_file_path, config = {})
    puts "🚀 启动文件上传识别演示"
    puts "📡 连接到: #{@proxy_url}/recognize"
    puts "🎵 上传文件: #{audio_file_path}"

    unless File.exist?(audio_file_path)
      puts "❌ 文件不存在: #{audio_file_path}"
      return
    end

    uri = URI("#{@proxy_url}/recognize")
    
    # Create multipart form data
    boundary = "----WebKitFormBoundary#{rand(1000000000000000000)}"
    
    # Build form data
    form_data = []
    
    # Add config parameters
    config.each do |key, value|
      form_data << "--#{boundary}\r\n"
      form_data << "Content-Disposition: form-data; name=\"#{key}\"\r\n\r\n"
      form_data << "#{value}\r\n"
    end
    
    # Add audio file
    form_data << "--#{boundary}\r\n"
    form_data << "Content-Disposition: form-data; name=\"audio\"; filename=\"#{File.basename(audio_file_path)}\"\r\n"
    form_data << "Content-Type: audio/wav\r\n\r\n"
    
    # Read file content
    audio_content = File.binread(audio_file_path)
    form_data << audio_content
    form_data << "\r\n--#{boundary}--\r\n"
    
    body = form_data.join
    
    # Create HTTP request
    http = Net::HTTP.new(uri.host, uri.port)
    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = "multipart/form-data; boundary=#{boundary}"
    request['Content-Length'] = body.bytesize.to_s
    request.body = body
    
    puts "📤 发送请求 (#{audio_content.bytesize} 字节)..."
    
    begin
      response = http.request(request)
      
      puts "📨 收到响应: HTTP #{response.code}"
      
      if response.code == '200'
        result = JSON.parse(response.body)
        puts "✅ 识别成功!"
        
        if result['results'] && !result['results'].empty?
          result['results'].each_with_index do |res, i|
            puts "📝 结果 #{i + 1}:"
            res['alternatives'].each_with_index do |alt, j|
              puts "  选项 #{j + 1}: #{alt['transcript']} (置信度: #{alt['confidence']})"
              
              if alt['words'] && !alt['words'].empty?
                puts "  词级时间戳:"
                alt['words'].each do |word|
                  puts "    #{word['word']}: #{word['start_time']}s - #{word['end_time']}s (置信度: #{word['confidence']})"
                end
              end
            end
          end
        else
          puts "⚠️  未识别到内容"
        end
      else
        error_info = JSON.parse(response.body) rescue { 'error' => response.body }
        puts "❌ 识别失败: #{error_info['error']}"
      end
      
    rescue => e
      puts "❌ 请求失败: #{e.message}"
    end
  end
end

# 使用示例
if __FILE__ == $0
  proxy_url = ARGV[0] || 'http://127.0.0.1:8080'
  audio_file = ARGV[1] || '16k16bit.wav'
  
  puts "╔══════════════════════════════════════════════════════════════╗"
  puts "║                    文件上传识别演示                          ║"
  puts "║                                                              ║"
  puts "║  这个演示将上传音频文件到WebSocket代理服务器进行识别          ║"
  puts "║  确保WebSocket代理服务器正在运行:                            ║"
  puts "║  ./bin/websocket_proxy                                       ║"
  puts "╚══════════════════════════════════════════════════════════════╝"
  puts
  
  demo = FileUploadDemo.new(proxy_url)
  
  # 配置参数
  config = {
    'language_code' => 'en-US',
    'sample_rate_hertz' => '16000',
    'encoding' => 'LINEAR_PCM',
    'enable_word_time_offsets' => 'true',
    'enable_automatic_punctuation' => 'true'
  }
  
  demo.upload_and_recognize(audio_file, config)
end