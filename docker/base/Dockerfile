# =========================
#   Build-time base switch
# =========================
ARG BASE=cpu

# ---- GPU base (CUDA runtime) ----
FROM nvidia/cuda:12.4.1-runtime-ubuntu22.04 AS gpu-base
ENV NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility

# ---- CPU base ----
FROM debian:bookworm-slim AS cpu-base

# ---- Select base by ARG ----
FROM ${BASE}-base AS final

# Locale/apt
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg tini nginx jq dumb-init \
  && rm -rf /var/lib/apt/lists/*

# ---------------------------
# Install Ollama (Linux x86_64)
# ※ 公式インストーラを利用。ネットワーク閉域の場合は社内ミラーへ置換。
# ---------------------------
RUN curl -fsSL https://ollama.com/install.sh | sh

# 作業ディレクトリ
WORKDIR /app

# スクリプト＆設定反映
# （あなたのリポジトリのファイルをコンテナへコピー）
COPY entrypoint.sh /app/entrypoint.sh
COPY healthcheck.sh /app/healthcheck.sh
COPY model-manager.sh /app/model-manager.sh
COPY nginx.conf /etc/nginx/nginx.conf

# 権限
RUN chmod +x /app/*.sh

# Nginx 前面、Ollama 背面
ENV OLLAMA_HOST=0.0.0.0:11434

# 8080: Nginx (ALB → ここへ)
EXPOSE 8080

# ヘルスチェック（Nginx 経由で /api/tags を確認）
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD /app/healthcheck.sh

# PID 1 を init で置換（ゾンビ回収）
ENTRYPOINT ["/usr/bin/dumb-init", "--"]

# エントリポイント（Ollama → Nginx の順で起動）
CMD ["/app/entrypoint.sh"]
