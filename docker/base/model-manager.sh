#!/usr/bin/env bash
set -euo pipefail

MODEL_NAME="${1:-}"
WARMUP_PROMPT_IN="${2:-}"

log() { echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] $*"; }

if [[ -n "$MODEL_NAME" ]]; then
  log "Preloading model: ${MODEL_NAME}"
  # 既にある場合は再DLしない（ollama pull は冪等）
  if ! ollama pull "$MODEL_NAME"; then
    log "WARN: ollama pull failed for ${MODEL_NAME} (continuing)."
  fi

  # 軽くウォームアップ。stream=false で即応答にする
  PROMPT="${WARMUP_PROMPT_IN:-"Say hello."}"
  log "Warmup generate (model=${MODEL_NAME})"
  curl -fsS -m 30 -H "Content-Type: application/json" \
    -d "{\"model\":\"${MODEL_NAME}\",\"prompt\":\"${PROMPT}\",\"stream\":false}" \
    "http://127.0.0.1:11434/api/generate" >/dev/null 2>&1 || \
    log "WARN: warmup request failed (continuing)."
else
  log "MODEL_NAME is empty; skipping preload."
fi
