# Llama2 7B Pre-built Docker Image
ARG BASE_IMAGE_URI
FROM ${BASE_IMAGE_URI}:latest

# メタデータ
LABEL model="llama2:7b"
LABEL model_size="7B"
LABEL category="chat"

# モデル固有の環境変数
ENV MODEL_NAME=llama2:7b
ENV PRELOAD_MODEL=true
ENV OLLAMA_MAX_LOADED_MODELS=1

# rootユーザーに一時的に切り替え（モデルダウンロード用）
USER root

# モデルを事前にダウンロード
RUN echo "📦 Pre-downloading Llama2 7B model..." && \
    # Ollamaサーバーをバックグラウンドで起動
    su - ollama -c "ollama serve &" && \
    sleep 10 && \
    # モデルをダウンロード
    su - ollama -c "ollama pull llama2:7b" && \
    # プロセスをクリーンアップ
    pkill -f ollama || true && \
    sleep 5 && \
    echo "✅ Llama2 7B model pre-downloaded"

# モデルファイルの存在確認
RUN if [ -d "/home/ollama/.ollama/models" ]; then \
        echo "📁 Model files:"; \
        find /home/ollama/.ollama/models -name "*.bin" -o -name "*.gguf" | head -5; \
        echo "💾 Total model size: $(du -sh /home/ollama/.ollama/models | cut -f1)"; \
    else \
        echo "⚠️  Warning: Model directory not found"; \
    fi

# 権限を修正
RUN chown -R ollama:ollama /home/ollama/.ollama

# ollamaユーザーに戻す
USER ollama

# ヘルスチェック（モデル固有）
HEALTHCHECK --interval=30s --timeout=15s --start-period=120s --retries=3 \
    CMD /app/healthcheck.sh

# デフォルトでllama2:7bモデルを使用
ENV MODEL_NAME=llama2:7b
