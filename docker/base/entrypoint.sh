#!/bin/bash
set -e

echo "🚀 Starting AWS Ollama Platform Container"
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

# モデルのプリロード
if [ "$PRELOAD_MODEL" = "true" ] && [ -n "$MODEL_NAME" ]; then
    echo "📦 Preloading model: $MODEL_NAME"
    
    # モデルをダウンロード
    echo "   Downloading model..."
    if ollama pull "$MODEL_NAME"; then
        echo "✅ Model downloaded successfully"
        
        # モデルをメモリにロード（小さなプロンプトで実行）
        echo "   Loading model into memory..."
        if curl -X POST http://localhost:11434/api/generate \
            -H "Content-Type: application/json" \
            -d "{\"model\":\"$MODEL_NAME\",\"prompt\":\"Hello\",\"stream\":false}" \
            >/dev/null 2>&1; then
            echo "✅ Model loaded into memory"
        else
            echo "⚠️  Warning: Failed to load model into memory, but continuing..."
        fi
    else
        echo "❌ Failed to download model: $MODEL_NAME"
        echo "   Available models:"
        ollama list || echo "   No models available"
        # モデルダウンロードに失敗してもサーバーは継続
    fi
else
    echo "ℹ️  No model preloading requested"
fi

# 利用可能なモデルを表示
echo "📋 Available models:"
ollama list || echo "   No models available"

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
