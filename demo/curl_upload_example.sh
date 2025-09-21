#!/bin/bash

# 文件上传识别的 cURL 示例脚本
# 演示如何使用 cURL 通过 POST /recognize 上传音频文件进行识别

PROXY_URL="http://127.0.0.1:8080"
AUDIO_FILE="16k16bit.wav"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    cURL 文件上传识别演示                     ║"
echo "║                                                              ║"
echo "║  这个脚本演示如何使用 cURL 上传音频文件进行识别               ║"
echo "║  确保 WebSocket 代理服务器正在运行:                          ║"
echo "║  ./bin/websocket_proxy                                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo

# 检查音频文件是否存在
if [ ! -f "$AUDIO_FILE" ]; then
    echo "❌ 音频文件不存在: $AUDIO_FILE"
    echo "请确保音频文件在当前目录下"
    exit 1
fi

echo "🚀 开始上传识别..."
echo "📡 服务器: $PROXY_URL/recognize"
echo "🎵 音频文件: $AUDIO_FILE"
echo

# 使用 cURL 上传文件并进行识别
curl -X POST \
  -F "audio=@$AUDIO_FILE" \
  -F "language_code=en-US" \
  -F "sample_rate_hertz=16000" \
  -F "encoding=LINEAR_PCM" \
  -F "enable_word_time_offsets=true" \
  -F "enable_automatic_punctuation=true" \
  -F "max_alternatives=1" \
  "$PROXY_URL/recognize" \
  -H "Accept: application/json" \
  -w "\n\n📊 HTTP 状态码: %{http_code}\n⏱️  总耗时: %{time_total}s\n📦 响应大小: %{size_download} bytes\n" \
  | jq '.' 2>/dev/null 

echo
echo "✅ 上传识别完成"
echo
echo "💡 提示:"
echo "   - 支持的音频格式: WAV (LINEAR_PCM)"
echo "   - 推荐采样率: 16000 Hz"
echo "   - 表单字段名: 'audio' 或 'file'"
echo "   - 可配置参数: language_code, sample_rate_hertz, encoding, 等"