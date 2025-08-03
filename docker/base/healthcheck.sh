#!/bin/bash

# Ollama ヘルスチェックスクリプト
# ECSのヘルスチェックで使用

# 基本的なAPIエンドポイントの確認
if ! curl -f -s http://localhost:11434/api/tags >/dev/null 2>&1; then
    echo "❌ Ollama API is not responding"
    exit 1
fi

# モデルが指定されている場合は、そのモデルが利用可能かチェック
if [ -n "$MODEL_NAME" ]; then
    if ! curl -s http://localhost:11434/api/tags | jq -r '.[].name' | grep -q "^${MODEL_NAME}$"; then
        echo "❌ Required model '$MODEL_NAME' is not available"
        echo "Available models:"
        curl -s http://localhost:11434/api/tags | jq -r '.[].name' | sed 's/^/  - /'
        exit 1
    fi
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

echo "✅ Health check passed"
exit 0
