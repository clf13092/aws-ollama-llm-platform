#!/bin/bash

# Universal Ollama Docker イメージをビルドしてECRにプッシュするスクリプト

set -e

# 設定
AWS_REGION=${AWS_REGION:-us-east-1}
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ENVIRONMENT=${ENVIRONMENT:-production}

# 色付きログ関数
print_color() {
    local color=$1
    local message=$2
    case $color in
        "red") echo -e "\033[0;31m$message\033[0m" ;;
        "green") echo -e "\033[0;32m$message\033[0m" ;;
        "blue") echo -e "\033[0;34m$message\033[0m" ;;
        "yellow") echo -e "\033[0;33m$message\033[0m" ;;
        *) echo "$message" ;;
    esac
}

print_color "blue" "🚀 Starting Universal Ollama Docker image build and push process"
print_color "blue" "AWS Account: $AWS_ACCOUNT_ID"
print_color "blue" "Region: $AWS_REGION"
print_color "blue" "Environment: $ENVIRONMENT"

# ECRにログイン
print_color "blue" "🔐 Logging in to ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# ECRリポジトリURIを設定
REPO_URI="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ENVIRONMENT-ollama"

print_color "blue" "📦 Repository URI: $REPO_URI"

# ユニバーサルOllamaイメージをビルド
print_color "blue" "🏗️  Building universal Ollama image..."

if [ -d "docker/base" ]; then
    cd docker/base
    
    # イメージをビルド
    docker build -t ollama-universal:latest .
    
    # タグ付け
    docker tag ollama-universal:latest $REPO_URI:latest
    docker tag ollama-universal:latest $REPO_URI:$(date +%Y%m%d-%H%M%S)
    docker tag ollama-universal:latest $REPO_URI:v2.0  # 動的モデル対応版
    
    print_color "blue" "📤 Pushing universal Ollama image to ECR..."
    docker push $REPO_URI:latest
    docker push $REPO_URI:$(date +%Y%m%d-%H%M%S)
    docker push $REPO_URI:v2.0
    
    print_color "green" "✅ Universal Ollama image pushed successfully"
    cd ../..
else
    print_color "red" "❌ Docker base directory not found. Please ensure docker/base exists."
    exit 1
fi

# イメージサイズの確認
print_color "blue" "📊 Image size:"
docker images | grep ollama-universal | awk '{print $1 ":" $2 " - " $7 $8}'

# クリーンアップ（オプション）
read -p "🗑️  Do you want to clean up local Docker images? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_color "blue" "🧹 Cleaning up local images..."
    docker images | grep ollama-universal | awk '{print $3}' | xargs docker rmi -f || true
    print_color "green" "✅ Local images cleaned up"
fi

print_color "green" "🎉 Universal Ollama image built and pushed successfully!"
print_color "blue" "📋 ECR Repository URI: $REPO_URI"
print_color "blue" "🔧 Available tags: latest, v2.0, $(date +%Y%m%d-%H%M%S)"

print_color "yellow" "💡 This universal image supports dynamic model loading:"
print_color "yellow" "   - Llama2 (7B, 13B, 70B)"
print_color "yellow" "   - CodeLlama (7B, 13B, 34B)"
print_color "yellow" "   - Mistral (7B, 7B-Instruct)"
print_color "yellow" "   - Phi (2.7B)"
print_color "yellow" "   - Gemma (2B, 7B)"
print_color "yellow" "   - Qwen (4B, 7B, 14B)"
print_color "yellow" "   - DeepSeek-Coder (6.7B, 33B)"
print_color "yellow" "   - And more models supported by Ollama!"
