#!/bin/bash
set -e

echo "🚀 Starting AWS Ollama Platform Container (Dynamic Model Support)"
echo "Instance ID: ${INSTANCE_ID:-unknown}"
echo "User ID: ${USER_ID:-unknown}"
echo "Model Name: ${MODEL_NAME:-none}"
echo "Preload Model: ${PRELOAD_MODEL:-false}"

# Ollamaサーバーをバックグラウンドで起動
echo "📡 Starting Ollama server..."
ollama serve &
OLLAMA_PID=$!

# サーバーが起動するまで待機
echo "⏳ Waiting for Ollama server to start..."
for i in {1..30}; do
    if curl -f http://localhost:11434/api/tags >/dev/null 2>&1; then
        echo "✅ Ollama server is ready!"
        break
    fi
    echo "   Attempt $i/30: Server not ready yet..."
    sleep 2
done

# サーバーが起動しなかった場合はエラー
if ! curl -f http://localhost:11434/api/tags >/dev/null 2>&1; then
    echo "❌ Failed to start Ollama server"
    exit 1
fi

# 動的モデル管理
if [ -n "$MODEL_NAME" ] && [ "$MODEL_NAME" != "none" ]; then
    echo "🤖 Managing model: $MODEL_NAME"
    
    # モデル管理スクリプトを実行
    if /app/model-manager.sh "$MODEL_NAME" "$PRELOAD_MODEL"; then
        echo "✅ Model management completed successfully"
    else
        echo "❌ Model management failed"
        echo "⚠️  Container will continue running, but model may not be available"
    fi
else
    echo "ℹ️  No specific model requested, Ollama server ready for dynamic model loading"
fi

# 利用可能なモデルを表示
echo "📋 Available models:"
ollama list || echo "   No models available yet"

# システム情報を表示
echo "💻 System Information:"
echo "   CPU cores: $(nproc)"
echo "   Memory: $(free -h | awk '/^Mem:/ {print $2}')"
echo "   Disk space: $(df -h / | awk 'NR==2 {print $4}')"

# GPU情報（利用可能な場合）
if command -v nvidia-smi >/dev/null 2>&1; then
    echo "🎮 GPU Information:"
    nvidia-smi --query-gpu=name,memory.total,memory.used --format=csv,noheader,nounits | \
        awk -F', ' '{printf "   GPU: %s, Memory: %s/%s MB\n", $1, $3, $2}'
fi

echo "🎉 Container initialization completed!"
echo "🌐 Ollama API is available at http://0.0.0.0:11434"

# 動的モデル情報の表示
if [ -n "$MODEL_NAME" ] && [ "$MODEL_NAME" != "none" ]; then
    echo "🔗 Model-specific endpoint ready for: $MODEL_NAME"
    echo "📝 Example API call:"
    echo "   curl -X POST http://localhost:11434/api/generate \\"
    echo "        -H 'Content-Type: application/json' \\"
    echo "        -d '{\"model\":\"$MODEL_NAME\",\"prompt\":\"Hello\",\"stream\":false}'"
fi

# シグナルハンドリング
cleanup() {
    echo "🛑 Received shutdown signal"
    if [ -n "$OLLAMA_PID" ]; then
        echo "   Stopping Ollama server (PID: $OLLAMA_PID)..."
        kill -TERM "$OLLAMA_PID" 2>/dev/null || true
        wait "$OLLAMA_PID" 2>/dev/null || true
    fi
    echo "✅ Cleanup completed"
    exit 0
}

trap cleanup SIGTERM SIGINT

# フォアグラウンドでOllamaサーバーを継続実行
echo "🔄 Running in foreground mode..."
wait "$OLLAMA_PID"
