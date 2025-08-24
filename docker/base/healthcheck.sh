#!/usr/bin/env bash
set -euo pipefail

# Nginx 経由で Ollama の /api/tags を確認
curl -fsS "http://127.0.0.1:8080/api/tags" >/dev/null 2>&1
