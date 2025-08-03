# Universal Ollama Docker Image for AWS ECS
FROM ubuntu:22.04

# メタデータ
LABEL maintainer="AWS Ollama Platform"
LABEL version="2.0"
LABEL description="Universal Ollama image for dynamic model deployment"

# 環境変数
ENV DEBIAN_FRONTEND=noninteractive
ENV OLLAMA_HOST=0.0.0.0
ENV OLLAMA_ORIGINS=*
ENV OLLAMA_KEEP_ALIVE=24h
ENV OLLAMA_MAX_LOADED_MODELS=1
ENV OLLAMA_NUM_PARALLEL=1
ENV OLLAMA_MAX_QUEUE=512

# 動的設定用環境変数（ECSタスクで設定される）
ENV MODEL_NAME=""
ENV PRELOAD_MODEL="false"
ENV INSTANCE_ID=""
ENV USER_ID=""

# 必要なパッケージをインストール
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    ca-certificates \
    gnupg \
    lsb-release \
    jq \
    htop \
    vim \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Ollamaをインストール
RUN curl -fsSL https://ollama.com/install.sh | sh

# 作業ディレクトリを作成
WORKDIR /app

# 動的モデル管理スクリプト
COPY model-manager.sh /app/model-manager.sh
RUN chmod +x /app/model-manager.sh

# ヘルスチェック用スクリプト
COPY healthcheck.sh /app/healthcheck.sh
RUN chmod +x /app/healthcheck.sh

# 起動スクリプト（動的モデル対応）
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Ollamaユーザーを作成
RUN useradd -m -s /bin/bash ollama && \
    mkdir -p /home/ollama/.ollama && \
    chown -R ollama:ollama /home/ollama && \
    chown -R ollama:ollama /app

# ポート公開
EXPOSE 11434

# ヘルスチェック（動的モデル対応）
HEALTHCHECK --interval=30s --timeout=15s --start-period=300s --retries=3 \
    CMD /app/healthcheck.sh

# 非rootユーザーで実行
USER ollama

# エントリーポイント
ENTRYPOINT ["/app/entrypoint.sh"]
