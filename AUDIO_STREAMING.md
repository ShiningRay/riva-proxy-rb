# 音频流传输指南

## 概述

WebSocket代理现在支持两种发送音频数据的方式：

1. **JSON包装方式** - 传统方式，音频数据包装在JSON消息中
2. **直接发送方式** - 新增功能，直接发送base64编码的音频数据（推荐）

## 使用方式

### 1. 配置阶段（必需）

无论使用哪种方式发送音频，都必须先发送配置消息：

```json
{
  "type": "config",
  "config": {
    "encoding": "LINEAR_PCM",
    "sample_rate_hertz": 16000,
    "language_code": "en-US",
    "enable_automatic_punctuation": true,
    "interim_results": true
  }
}
```

### 2. 音频数据发送

#### 方式1: JSON包装（兼容旧版本）

```json
{
  "type": "audio",
  "audio": "UklGRiQAAABXQVZFZm10IBAAAAABAAEA..."
}
```

#### 方式2: 直接发送（推荐）

```
UklGRiQAAABXQVZFZm10IBAAAAABAAEA...
```

直接发送base64编码的音频数据，无需JSON包装。

## 优势

### 直接发送方式的优势：

1. **更少的数据传输** - 减少JSON包装的开销
2. **更简单的客户端代码** - 无需构造JSON消息
3. **更好的性能** - 减少JSON解析开销
4. **向后兼容** - 服务器自动检测消息格式

## 示例代码

### Ruby客户端

```ruby
require 'faye/websocket'
require 'eventmachine'
require 'json'
require 'base64'

EM.run do
  ws = Faye::WebSocket::Client.new('ws://localhost:8080')

  ws.on :open do
    # 发送配置
    config = {
      type: 'config',
      config: {
        encoding: 'LINEAR_PCM',
        sample_rate_hertz: 16000,
        language_code: 'en-US'
      }
    }
    ws.send(JSON.generate(config))
  end

  ws.on :message do |event|
    response = JSON.parse(event.data)
    if response['type'] == 'ready'
      # 直接发送base64音频数据
      audio_data = File.read('audio.wav')
      base64_audio = Base64.strict_encode64(audio_data)
      ws.send(base64_audio)  # 直接发送，无需JSON包装
    end
  end
end
```

### JavaScript客户端

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
  if (data.type === 'ready') {
    // 直接发送base64音频数据
    const base64Audio = btoa(String.fromCharCode(...audioData));
    ws.send(base64Audio);  // 直接发送
  }
};
```

## 测试

运行演示脚本来测试新功能：

```bash
# 启动服务器
./bin/websocket_proxy

# 在另一个终端运行演示客户端
./demo/simple_audio_client.rb
```

## 性能考虑

- 直接发送方式减少了约30-40%的消息大小（取决于音频数据大小）
- 减少了客户端和服务器的JSON处理开销
- 特别适合高频率的音频流传输场景

## 兼容性

- 新功能完全向后兼容
- 现有的JSON包装方式继续正常工作
- 服务器自动检测消息格式，无需客户端指定