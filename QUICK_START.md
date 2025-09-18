# 🚀 WebSocket代理快速启动指南

## 📋 前提条件

1. **Ruby 3.4.5+** 已安装
2. **Riva ASR服务器** 正在运行 (或使用mock服务器进行测试)
3. **Bundler** 已安装

## ⚡ 快速开始

### 1️⃣ 安装依赖
```bash
bundle install
```

### 2️⃣ 配置环境 (可选)
```bash
# 复制环境变量模板
cp .env.example .env

# 编辑配置 (如果需要)
# vim .env
```

### 3️⃣ 启动WebSocket代理服务器
```bash
# 使用默认配置 (localhost:8080)
./bin/websocket_proxy

# 或指定自定义配置
./bin/websocket_proxy --host 0.0.0.0 --port 8080 --riva-host your-riva-server.com
```

### 4️⃣ 测试连接

#### 选项A: 使用演示脚本
```bash
# 在新终端中运行演示
./demo/websocket_demo.rb
```

#### 选项B: 使用示例客户端
```bash
# 运行Ruby客户端示例
./examples/websocket_client_example.rb
```

#### 选项C: 使用浏览器测试
```javascript
// 在浏览器控制台中运行
const ws = new WebSocket('ws://localhost:8080');

ws.onopen = () => {
  console.log('✅ 连接已建立');
  
  // 发送配置
  ws.send(JSON.stringify({
    type: 'config',
    config: {
      encoding: 'LINEAR_PCM',
      sample_rate_hertz: 16000,
      language_code: 'en-US'
    }
  }));
};

ws.onmessage = (event) => {
  console.log('📨 收到消息:', JSON.parse(event.data));
};
```

## 🔧 配置选项

### 环境变量
```env
WEBSOCKET_HOST=0.0.0.0      # WebSocket服务器主机
WEBSOCKET_PORT=8080         # WebSocket服务器端口
RIVA_HOST=localhost         # Riva gRPC服务器主机
RIVA_PORT=50051            # Riva gRPC服务器端口
RIVA_TIMEOUT=30            # gRPC超时时间(秒)
LOG_LEVEL=info             # 日志级别
```

### 命令行参数
```bash
./bin/websocket_proxy --help
```

## 📊 验证服务器状态

### 检查服务器是否运行
```bash
# 检查端口是否被监听
lsof -i :8080

# 或使用netstat
netstat -an | grep 8080
```

### 查看日志
服务器会输出详细的日志信息，包括：
- 客户端连接/断开
- 消息处理状态
- gRPC会话管理
- 错误信息

## 🧪 测试

### 运行单元测试
```bash
bundle exec rspec spec/websocket_proxy_spec.rb -v
```

### 运行所有测试
```bash
bundle exec rspec spec/ -v
```

## 🔍 故障排除

### 常见问题

1. **端口被占用**
   ```bash
   # 查找占用端口的进程
   lsof -i :8080
   # 杀死进程
   kill -9 <PID>
   ```

2. **无法连接到Riva服务器**
   - 检查RIVA_HOST和RIVA_PORT配置
   - 确保Riva服务器正在运行
   - 检查网络连接和防火墙设置

3. **WebSocket连接失败**
   - 确保WebSocket代理服务器正在运行
   - 检查客户端URL是否正确
   - 验证防火墙设置

### 调试模式
```bash
# 启用调试日志
./bin/websocket_proxy --log-level DEBUG
```

## 📚 更多信息

- 📖 [详细文档](WEBSOCKET_PROXY.md)
- 🏗️ [项目总结](PROJECT_SUMMARY.md)
- 💻 [客户端示例](examples/)
- 🧪 [测试文件](spec/)

## 🎯 下一步

1. 集成到您的应用程序中
2. 添加身份验证和授权
3. 实现监控和指标收集
4. 配置生产环境部署

---

**🎉 恭喜！您的WebSocket代理服务器现在已经运行起来了！**