#!/usr/bin/env bash
set -euo pipefail

log() { echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] $*"; }

# ===== 1) Ollama 起動 =====
log "Starting Ollama on ${OLLAMA_HOST:-0.0.0.0:11434} ..."
ollama serve &
OLLAMA_PID=$!

# 起動待ち
for i in {1..60}; do
  if curl -fsS "http://127.0.0.1:11434/" >/dev/null 2>&1; then
    log "Ollama is up."
    break
  fi
  sleep 1
  if [[ $i -eq 60 ]]; then
    log "Ollama failed to start."
    exit 1
  fi
done

# ===== 2) モデルプリロード等（任意） =====
# 環境変数:
#   MODEL_NAME       : 例 "qwen2.5:1.5b"
#   PRELOAD_MODEL    : "true" で pull/warmup 実行
#   WARMUP_PROMPT    : 任意のウォームアッププロンプト（未指定なら簡易プロンプト）
if [[ "${PRELOAD_MODEL:-}" == "true" || "${PRELOAD_MODEL:-}" == "1" ]]; then
  /app/model-manager.sh "${MODEL_NAME:-}" "${WARMUP_PROMPT:-}" || true
fi

# ===== 3) Nginx (リバースプロキシ) 起動 =====
log "Starting Nginx reverse proxy on :8080 (rewrite /models/<x>/api/* -> /api/*)"
nginx -g 'daemon off;' &
NGINX_PID=$!

# ===== シグナル処理 =====
cleanup() {
  log "Shutting down ..."
  if kill -0 "$NGINX_PID" >/dev/null 2>&1; then
    kill -TERM "$NGINX_PID" || true
  fi
  if kill -0 "$OLLAMA_PID" >/dev/null 2>&1; then
    kill -TERM "$OLLAMA_PID" || true
  fi
  wait "$NGINX_PID" 2>/dev/null || true
  wait "$OLLAMA_PID" 2>/dev/null || true
}
trap cleanup SIGTERM SIGINT

# どちらかが落ちたら終了
wait -n "$NGINX_PID" "$OLLAMA_PID"
EXIT_CODE=$?
cleanup
exit $EXIT_CODE
