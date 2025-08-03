#!/bin/bash

# Dynamic Model Manager for Ollama
# This script handles dynamic model downloading and loading based on environment variables

set -e

# ログ関数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# モデル名の検証
validate_model_name() {
    local model_name="$1"
    
    # 基本的な検証
    if [[ -z "$model_name" ]]; then
        log "ERROR: Model name is empty"
        return 1
    fi
    
    # 許可されたモデル名のパターン
    local allowed_patterns=(
        "llama2:7b"
        "llama2:13b" 
        "llama2:70b"
        "codellama:7b"
        "codellama:13b"
        "codellama:34b"
        "mistral:7b"
        "mistral:7b-instruct"
        "phi:2.7b"
        "gemma:2b"
        "gemma:7b"
        "qwen:4b"
        "qwen:7b"
        "qwen:14b"
        "deepseek-coder:6.7b"
        "deepseek-coder:33b"
    )
    
    for pattern in "${allowed_patterns[@]}"; do
        if [[ "$model_name" == "$pattern" ]]; then
            log "INFO: Model '$model_name' is allowed"
            return 0
        fi
    done
    
    log "ERROR: Model '$model_name' is not in the allowed list"
    log "INFO: Allowed models: ${allowed_patterns[*]}"
    return 1
}

# モデルサイズの推定
estimate_model_size() {
    local model_name="$1"
    
    case "$model_name" in
        *"2b"*) echo "2GB" ;;
        *"7b"*) echo "4GB" ;;
        *"13b"*) echo "8GB" ;;
        *"34b"*) echo "20GB" ;;
        *"70b"*) echo "40GB" ;;
        *) echo "4GB" ;;  # デフォルト
    esac
}

# 利用可能メモリのチェック
check_memory_requirements() {
    local model_name="$1"
    local required_size=$(estimate_model_size "$model_name")
    local available_memory=$(free -m | awk 'NR==2{printf "%.0f", $7}')  # 利用可能メモリ(MB)
    
    log "INFO: Model '$model_name' requires approximately $required_size"
    log "INFO: Available memory: ${available_memory}MB"
    
    # 簡単なメモリチェック（実際の要件は複雑）
    case "$required_size" in
        "2GB") required_mb=2048 ;;
        "4GB") required_mb=4096 ;;
        "8GB") required_mb=8192 ;;
        "20GB") required_mb=20480 ;;
        "40GB") required_mb=40960 ;;
        *) required_mb=4096 ;;
    esac
    
    if [[ $available_memory -lt $required_mb ]]; then
        log "WARNING: Available memory (${available_memory}MB) may be insufficient for model requiring ${required_mb}MB"
        log "WARNING: Proceeding anyway, but model loading may fail"
    else
        log "INFO: Memory check passed"
    fi
}

# モデルのダウンロード
download_model() {
    local model_name="$1"
    
    log "INFO: Starting download of model: $model_name"
    
    # タイムアウト設定（大きなモデル用）
    local timeout=1800  # 30分
    
    # モデルをダウンロード
    if timeout $timeout ollama pull "$model_name"; then
        log "SUCCESS: Model '$model_name' downloaded successfully"
        return 0
    else
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            log "ERROR: Model download timed out after ${timeout} seconds"
        else
            log "ERROR: Model download failed with exit code: $exit_code"
        fi
        return 1
    fi
}

# モデルのプリロード（メモリに読み込み）
preload_model() {
    local model_name="$1"
    
    log "INFO: Preloading model '$model_name' into memory"
    
    # 小さなプロンプトでモデルを初期化
    local test_prompt="Hello"
    local max_retries=3
    local retry_count=0
    
    while [[ $retry_count -lt $max_retries ]]; do
        if curl -s -X POST http://localhost:11434/api/generate \
            -H "Content-Type: application/json" \
            -d "{\"model\":\"$model_name\",\"prompt\":\"$test_prompt\",\"stream\":false}" \
            --max-time 300 >/dev/null 2>&1; then
            log "SUCCESS: Model '$model_name' preloaded successfully"
            return 0
        else
            retry_count=$((retry_count + 1))
            log "WARNING: Preload attempt $retry_count failed, retrying in 10 seconds..."
            sleep 10
        fi
    done
    
    log "ERROR: Failed to preload model after $max_retries attempts"
    return 1
}

# モデル情報の表示
show_model_info() {
    local model_name="$1"
    
    log "INFO: Model information for '$model_name':"
    
    # モデルの詳細情報を取得
    if curl -s http://localhost:11434/api/show -d "{\"name\":\"$model_name\"}" | jq . 2>/dev/null; then
        log "INFO: Model details retrieved successfully"
    else
        log "WARNING: Could not retrieve detailed model information"
    fi
    
    # 利用可能なモデル一覧を表示
    log "INFO: Currently available models:"
    ollama list 2>/dev/null || log "WARNING: Could not list models"
}

# メイン処理
main() {
    local model_name="$1"
    local should_preload="${2:-false}"
    
    log "INFO: Starting dynamic model management"
    log "INFO: Model: $model_name"
    log "INFO: Preload: $should_preload"
    
    # モデル名の検証
    if ! validate_model_name "$model_name"; then
        log "ERROR: Model validation failed"
        return 1
    fi
    
    # メモリ要件のチェック
    check_memory_requirements "$model_name"
    
    # モデルが既にダウンロード済みかチェック
    if ollama list | grep -q "^$model_name"; then
        log "INFO: Model '$model_name' is already available"
    else
        # モデルをダウンロード
        if ! download_model "$model_name"; then
            log "ERROR: Failed to download model"
            return 1
        fi
    fi
    
    # プリロードが要求されている場合
    if [[ "$should_preload" == "true" ]]; then
        if ! preload_model "$model_name"; then
            log "WARNING: Preload failed, but continuing..."
        fi
    fi
    
    # モデル情報を表示
    show_model_info "$model_name"
    
    log "SUCCESS: Model management completed for '$model_name'"
    return 0
}

# スクリプトが直接実行された場合
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
