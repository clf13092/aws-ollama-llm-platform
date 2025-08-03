#!/bin/bash

# Dynamic Model-Aware Health Check for Ollama
# This script performs health checks that adapt to the currently loaded model

# 基本的なAPIエンドポイントの確認
if ! curl -f -s http://localhost:11434/api/tags >/dev/null 2>&1; then
    echo "❌ Ollama API is not responding"
    exit 1
fi

# 動的モデルチェック
if [ -n "$MODEL_NAME" ] && [ "$MODEL_NAME" != "none" ]; then
    # 指定されたモデルが利用可能かチェック
    if ! curl -s http://localhost:11434/api/tags | jq -r '.[].name' | grep -q "^${MODEL_NAME}$"; then
        echo "❌ Required model '$MODEL_NAME' is not available"
        echo "Available models:"
        curl -s http://localhost:11434/api/tags | jq -r '.[].name' | sed 's/^/  - /' || echo "  None"
        exit 1
    fi
    
    # モデルが実際に応答可能かテスト（軽量テスト）
    if [ "$PRELOAD_MODEL" = "true" ]; then
        # プリロードされている場合は、実際にモデルが応答するかテスト
        local test_response=$(curl -s -X POST http://localhost:11434/api/generate \
            -H "Content-Type: application/json" \
            -d "{\"model\":\"$MODEL_NAME\",\"prompt\":\"Hi\",\"stream\":false}" \
            --max-time 10 2>/dev/null)
        
        if [ $? -ne 0 ] || [ -z "$test_response" ]; then
            echo "⚠️  Warning: Model '$MODEL_NAME' is available but not responding to test prompt"
            # 警告だけで、ヘルスチェックは通す（モデルロード中の可能性）
        fi
    fi
else
    # モデルが指定されていない場合は、基本的なOllamaサーバーの動作確認のみ
    echo "ℹ️  No specific model required, checking basic Ollama functionality"
fi

# メモリ使用量チェック（90%以上で警告）
MEMORY_USAGE=$(free | awk '/^Mem:/ {printf "%.0f", $3/$2 * 100}')
if [ "$MEMORY_USAGE" -gt 90 ]; then
    echo "⚠️  Warning: High memory usage: ${MEMORY_USAGE}%"
    # 警告だけで、ヘルスチェックは通す
fi

# ディスク使用量チェック（95%以上でエラー）
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -gt 95 ]; then
    echo "❌ Critical: Disk usage too high: ${DISK_USAGE}%"
    exit 1
fi

# Ollamaプロセスの確認
if ! pgrep -f "ollama serve" >/dev/null; then
    echo "❌ Ollama server process is not running"
    exit 1
fi

# 成功時のメッセージ
if [ -n "$MODEL_NAME" ] && [ "$MODEL_NAME" != "none" ]; then
    echo "✅ Health check passed - Ollama server running with model: $MODEL_NAME"
else
    echo "✅ Health check passed - Ollama server running (no specific model)"
fi

exit 0
