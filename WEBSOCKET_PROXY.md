# WebSocket Proxy for Riva ASR

这个WebSocket代理服务器允许客户端通过WebSocket连接使用Riva ASR服务进行实时语音识别。

## 功能特性

- 通过WebSocket提供实时语音识别服务
- 自动管理与Riva gRPC服务器的连接
- 支持多个并发客户端连接
- Base64音频数据解码和转发
- 完整的连接生命周期管理
- 详细的错误处理和日志记录

## 安装依赖

```bash
bundle install
```

## 环境配置

复制环境变量示例文件并根据需要修改：

```bash
cp .env.example .env
```

编辑 `.env` 文件：

```env
# WebSocket服务器配置
WEBSOCKET_HOST=0.0.0.0
WEBSOCKET_PORT=8080

# Riva gRPC服务器配置
RIVA_HOST=localhost
RIVA_PORT=50051
RIVA_TIMEOUT=30

# 日志配置
LOG_LEVEL=info
```

## 启动服务器

```bash
# 使用默认配置启动
./bin/websocket_proxy

# 或者指定自定义配置
./bin/websocket_proxy --host 0.0.0.0 --port 8080 --riva-host your-riva-server.com --riva-port 50051
```

## 客户端使用

### 连接到WebSocket服务器

```javascript
const ws = new WebSocket('ws://localhost:8080');
```

### 发送配置消息

首先发送识别配置：

```javascript
const config = {
  type: 'config',
  config: {
    encoding: 'LINEAR_PCM',
    sample_rate_hertz: 16000,
    language_code: 'en-US',
    max_alternatives: 1,
    enable_automatic_punctuation: true,
    enable_word_time_offsets: true
  }
};

ws.send(JSON.stringify(config));
```

### 发送音频数据

发送Base64编码的音频数据：

```javascript
// 假设 audioData 是原始音频字节
const audioMessage = {
  type: 'audio',
  audio: btoa(String.fromCharCode.apply(null, audioData))
};

ws.send(JSON.stringify(audioMessage));
```

### 接收识别结果

```javascript
ws.onmessage = function(event) {
  const data = JSON.parse(event.data);
  
  switch(data.type) {
    case 'result':
      console.log('识别结果:', data.result);
      break;
    case 'error':
      console.error('错误:', data.message);
      break;
    case 'status':
      console.log('状态:', data.message);
      break;
  }
};
```

## 消息格式

### 客户端发送的消息

#### 配置消息
```json
{
  "type": "config",
  "config": {
    "encoding": "LINEAR_PCM",
    "sample_rate_hertz": 16000,
    "language_code": "en-US",
    "max_alternatives": 1,
    "enable_automatic_punctuation": true,
    "enable_word_time_offsets": true
  }
}
```

#### 音频消息

##### 方式1: JSON包装的音频数据
```json
{
  "type": "audio",
  "audio": "base64编码的音频数据"
}
```

##### 方式2: 直接发送base64音频数据（推荐）
```
直接发送base64编码的音频数据，无需JSON包装
```

**注意**: 服务器会自动检测消息格式。如果消息不是有效的JSON，会被当作直接的base64音频数据处理。

### 服务器发送的消息

#### 识别结果
```json
{
  "type": "result",
  "result": {
    "alternatives": [
      {
        "transcript": "识别的文本",
        "confidence": 0.95
      }
    ],
    "is_final": true
  }
}
```

#### 错误消息
```json
{
  "type": "error",
  "message": "错误描述"
}
```

#### 状态消息
```json
{
  "type": "status",
  "message": "状态描述"
}
```

## 示例客户端

### JavaScript客户端

#### 方式1: JSON包装的音频数据
```javascript
const ws = new WebSocket('ws://localhost:8080');

ws.onopen = function() {
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

ws.onmessage = function(event) {
  const data = JSON.parse(event.data);
  if (data.type === 'recognition') {
    console.log('识别结果:', data.results);
  }
};

// 发送音频数据（JSON方式）
function sendAudioJSON(audioData) {
  const base64Audio = btoa(String.fromCharCode(...new Uint8Array(audioData)));
  ws.send(JSON.stringify({
    type: 'audio',
    audio: base64Audio
  }));
}
```

#### 方式2: 直接发送base64音频数据（推荐）
```javascript
const ws = new WebSocket('ws://localhost:8080');

ws.onopen = function() {
  // 发送配置（仍需JSON格式）
  ws.send(JSON.stringify({
    type: 'config',
    config: {
      encoding: 'LINEAR_PCM',
      sample_rate_hertz: 16000,
      language_code: 'en-US'
    }
  }));
};

ws.onmessage = function(event) {
  const data = JSON.parse(event.data);
  if (data.type === 'recognition') {
    console.log('识别结果:', data.results);
  }
};

// 直接发送base64音频数据（推荐方式）
function sendAudioDirect(audioData) {
  const base64Audio = btoa(String.fromCharCode(...new Uint8Array(audioData)));
  ws.send(base64Audio);  // 直接发送，无需JSON包装
}
```

查看 `examples/websocket_client_example.rb` 获取完整的Ruby客户端示例。

## 测试

运行测试套件：

```bash
bundle exec rspec spec/websocket_proxy_spec.rb
```

## 故障排除

### 常见问题

1. **连接被拒绝**
   - 检查Riva服务器是否运行
   - 验证RIVA_HOST和RIVA_PORT配置

2. **音频识别失败**
   - 确保音频格式与配置匹配
   - 检查采样率和编码格式

3. **WebSocket连接失败**
   - 验证防火墙设置
   - 检查端口是否被占用

### 日志

服务器会输出详细的日志信息，包括：
- 客户端连接/断开
- 消息处理状态
- gRPC会话管理
- 错误信息

调整LOG_LEVEL环境变量来控制日志详细程度：
- `debug`: 最详细的日志
- `info`: 一般信息（默认）
- `warn`: 警告和错误
- `error`: 仅错误信息

## 架构说明

```
客户端 <--WebSocket--> WebSocket代理 <--gRPC--> Riva服务器
```

WebSocket代理服务器：
1. 接受WebSocket连接
2. 为每个连接创建独立的gRPC流式会话
3. 转发配置和音频数据到Riva
4. 将识别结果返回给客户端
5. 管理连接生命周期

## 性能考虑

- 每个WebSocket连接对应一个gRPC流式会话
- 服务器使用EventMachine进行异步I/O处理
- 支持多个并发连接
- 内存使用与活跃连接数成正比

## 安全注意事项

- 在生产环境中使用HTTPS/WSS
- 考虑添加身份验证机制
- 限制连接数和速率
- 验证输入数据格式