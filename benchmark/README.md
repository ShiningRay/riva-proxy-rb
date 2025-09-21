# WebSocket 代理基准测试工具

这个目录包含了用于测试 WebSocket 代理服务器并发性能的基准测试工具。

## 工具概览

### 1. 简单 HTTP 负载测试 (`simple_load_test.rb`)

测试 HTTP 文件上传接口的并发性能。

**功能特点:**
- 支持自定义并发请求数和总请求数
- 实时显示请求进度
- 详细的性能统计报告
- 响应时间分布分析
- 错误分析和性能建议

**使用方法:**
```bash
# 基本使用
ruby benchmark/simple_load_test.rb

# 自定义参数
ruby benchmark/simple_load_test.rb -c 10 -n 50 -u http://127.0.0.1:8080 -f 16k16bit.wav

# 查看帮助
ruby benchmark/simple_load_test.rb --help
```

**参数说明:**
- `-u, --url URL`: 服务器 URL (默认: http://127.0.0.1:8080)
- `-f, --file FILE`: 音频文件路径 (默认: 16k16bit.wav)
- `-c, --concurrent N`: 并发请求数 (默认: 5)
- `-n, --requests N`: 总请求数 (默认: 20)

### 2. WebSocket 并发测试 (`websocket_load_test.rb`)

测试 WebSocket 实时流式识别的并发性能。

**功能特点:**
- 支持多个并发 WebSocket 连接
- 模拟真实的音频流传输
- 连接级别的性能统计
- 转录质量分析
- 详细的错误诊断

**使用方法:**
```bash
# 基本使用
ruby benchmark/websocket_load_test.rb

# 自定义参数
ruby benchmark/websocket_load_test.rb -c 5 -m 10 -w ws://127.0.0.1:8080

# 查看帮助
ruby benchmark/websocket_load_test.rb --help
```

**参数说明:**
- `-w, --ws-url URL`: WebSocket URL (默认: ws://127.0.0.1:8080)
- `-f, --file FILE`: 音频文件路径 (默认: 16k16bit.wav)
- `-c, --connections N`: 并发连接数 (默认: 5)
- `-m, --messages N`: 每连接消息数 (默认: 10)
- `-s, --chunk-size N`: 音频块大小 (默认: 1024)

### 3. 综合基准测试套件 (`run_all_benchmarks.rb`)

运行多种负载场景的综合测试套件。

**功能特点:**
- 自动运行多个测试场景
- 生成综合性能报告
- 性能趋势分析
- 结果导出为 JSON 格式
- 智能性能建议

**使用方法:**
```bash
# 运行所有测试
ruby benchmark/run_all_benchmarks.rb

# 保存结果到文件
ruby benchmark/run_all_benchmarks.rb -o results.json

# 查看帮助
ruby benchmark/run_all_benchmarks.rb --help
```

**参数说明:**
- `-u, --url URL`: HTTP 服务器 URL (默认: http://127.0.0.1:8080)
- `-w, --ws-url URL`: WebSocket URL (默认: ws://127.0.0.1:8080)
- `-f, --file FILE`: 音频文件路径 (默认: 16k16bit.wav)
- `-o, --output FILE`: 结果输出文件 (JSON 格式)

## 测试场景

综合基准测试套件包含以下测试场景:

1. **轻负载 HTTP 测试**: 2 并发, 10 请求 - 测试基本功能
2. **中等负载 HTTP 测试**: 5 并发, 25 请求 - 测试中等并发性能
3. **高负载 HTTP 测试**: 10 并发, 50 请求 - 测试高并发性能
4. **极限负载 HTTP 测试**: 20 并发, 100 请求 - 测试极限性能

## 性能指标

### HTTP 测试指标
- **成功率**: 成功请求占总请求的百分比
- **平均响应时间**: 所有成功请求的平均响应时间
- **响应时间分布**: 最快、最慢、中位数、95%、99% 响应时间
- **吞吐量**: 每秒处理的请求数
- **错误分析**: 失败请求的错误类型统计

### WebSocket 测试指标
- **连接成功率**: 成功建立的 WebSocket 连接比例
- **消息成功率**: 成功发送和接收的消息比例
- **转录质量**: 包含有效转录结果的消息比例
- **实时性能**: 消息发送到接收响应的延迟
- **连接稳定性**: 连接持续时间和断线情况

## 使用前准备

### 1. 启动服务器

确保 WebSocket 代理服务器和模拟 gRPC 服务器正在运行:

```bash
# 启动 WebSocket 代理服务器
ruby bin/websocket_proxy --host 127.0.0.1 --port 8080

# 启动模拟 gRPC 服务器 (另一个终端)
ruby bin/mock_server
```

### 2. 准备音频文件

确保测试音频文件存在:
```bash
# 检查音频文件
ls -la 16k16bit.wav

# 如果不存在，可以使用项目中的示例音频文件
```

### 3. 安装依赖

确保安装了必要的 Ruby gems:
```bash
bundle install
```

## 性能基准参考

基于测试结果，以下是性能基准参考:

### HTTP 文件上传性能
- **优秀**: 响应时间 < 50ms, 吞吐量 > 200 请求/秒, 成功率 > 99%
- **良好**: 响应时间 < 100ms, 吞吐量 > 100 请求/秒, 成功率 > 95%
- **需要优化**: 响应时间 > 200ms, 吞吐量 < 50 请求/秒, 成功率 < 90%

### WebSocket 实时识别性能
- **优秀**: 消息延迟 < 100ms, 连接成功率 > 99%, 转录率 > 95%
- **良好**: 消息延迟 < 500ms, 连接成功率 > 95%, 转录率 > 90%
- **需要优化**: 消息延迟 > 1000ms, 连接成功率 < 90%, 转录率 < 80%

## 故障排除

### 常见问题

1. **连接被拒绝**
   - 检查服务器是否启动
   - 确认端口号是否正确
   - 检查防火墙设置

2. **HTTP 422 错误**
   - 检查 gRPC 服务器是否运行
   - 确认 gRPC 服务器地址配置

3. **音频文件错误**
   - 确认音频文件存在
   - 检查音频文件格式 (需要 WAV 格式)
   - 验证音频文件大小

4. **WebSocket 连接失败**
   - 检查 WebSocket URL 格式
   - 确认服务器支持 WebSocket 协议
   - 检查网络连接

### 调试技巧

1. **增加日志输出**:
   ```bash
   # 运行服务器时增加详细日志
   VERBOSE=1 ruby bin/websocket_proxy --host 127.0.0.1 --port 8080
   ```

2. **单独测试组件**:
   ```bash
   # 先测试简单的 HTTP 请求
   curl -X POST http://127.0.0.1:8080/recognize
   
   # 再测试文件上传
   ruby demo/file_upload_demo.rb http://127.0.0.1:8080 16k16bit.wav
   ```

3. **逐步增加负载**:
   ```bash
   # 从小负载开始
   ruby benchmark/simple_load_test.rb -c 1 -n 5
   
   # 逐步增加并发数
   ruby benchmark/simple_load_test.rb -c 2 -n 10
   ruby benchmark/simple_load_test.rb -c 5 -n 20
   ```

## 扩展和定制

### 添加新的测试场景

可以通过修改 `run_all_benchmarks.rb` 中的 `scenarios` 数组来添加新的测试场景:

```ruby
scenarios << {
  name: "自定义测试场景",
  type: :http,
  concurrent: 15,
  requests: 75,
  description: "自定义的测试场景描述"
}
```

### 自定义性能指标

可以在各个测试工具中添加新的性能指标收集和分析逻辑。

### 集成到 CI/CD

可以将基准测试集成到持续集成流程中:

```bash
# 在 CI 脚本中运行基准测试
ruby benchmark/run_all_benchmarks.rb -o ci_benchmark_results.json

# 检查性能回归
ruby scripts/check_performance_regression.rb ci_benchmark_results.json
```

## 贡献

欢迎提交改进建议和新功能:

1. 添加新的测试场景
2. 改进性能分析算法
3. 增加可视化报告
4. 优化测试工具性能
5. 完善文档和示例