#!/bin/bash

# Docker イメージをビルドしてECRにプッシュするスクリプト

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

print_color "blue" "🚀 Starting Docker image build and push process"
print_color "blue" "AWS Account: $AWS_ACCOUNT_ID"
print_color "blue" "Region: $AWS_REGION"
print_color "blue" "Environment: $ENVIRONMENT"

# ECRにログイン
print_color "blue" "🔐 Logging in to ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# ベースイメージをビルド
print_color "blue" "🏗️  Building base Ollama image..."
BASE_REPO_URI="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ENVIRONMENT-ollama-base"

cd docker/base
docker build -t ollama-base:latest .
docker tag ollama-base:latest $BASE_REPO_URI:latest
docker tag ollama-base:latest $BASE_REPO_URI:$(date +%Y%m%d-%H%M%S)

print_color "blue" "📤 Pushing base image to ECR..."
docker push $BASE_REPO_URI:latest
docker push $BASE_REPO_URI:$(date +%Y%m%d-%H%M%S)
print_color "green" "✅ Base image pushed successfully"

cd ../..

# モデル固有のイメージをビルド
declare -A MODELS=(
    ["llama2-7b"]="llama2:7b"
    ["llama2-13b"]="llama2:13b"
    ["codellama-7b"]="codellama:7b"
    ["codellama-13b"]="codellama:13b"
    ["mistral-7b"]="mistral:7b"
)

for model_dir in "${!MODELS[@]}"; do
    model_name="${MODELS[$model_dir]}"
    repo_name="$ENVIRONMENT-ollama-$model_dir"
    repo_uri="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$repo_name"
    
    print_color "blue" "🏗️  Building $model_name image..."
    
    # Dockerfileが存在するかチェック
    if [ -f "docker/models/$model_dir/Dockerfile" ]; then
        cd docker/models/$model_dir
        
        # ベースイメージURIを引数として渡してビルド
        docker build \
            --build-arg BASE_IMAGE_URI=$BASE_REPO_URI \
            -t ollama-$model_dir:latest .
        
        docker tag ollama-$model_dir:latest $repo_uri:latest
        docker tag ollama-$model_dir:latest $repo_uri:$(date +%Y%m%d-%H%M%S)
        
        print_color "blue" "📤 Pushing $model_name image to ECR..."
        docker push $repo_uri:latest
        docker push $repo_uri:$(date +%Y%m%d-%H%M%S)
        print_color "green" "✅ $model_name image pushed successfully"
        
        cd ../../..
    else
        print_color "yellow" "⚠️  Dockerfile not found for $model_dir, creating generic one..."
        
        # 汎用的なDockerfileを作成
        mkdir -p docker/models/$model_dir
        cat > docker/models/$model_dir/Dockerfile << EOF
ARG BASE_IMAGE_URI
FROM \${BASE_IMAGE_URI}:latest

LABEL model="$model_name"
ENV MODEL_NAME=$model_name
ENV PRELOAD_MODEL=true
EOF
        
        cd docker/models/$model_dir
        docker build \
            --build-arg BASE_IMAGE_URI=$BASE_REPO_URI \
            -t ollama-$model_dir:latest .
        
        docker tag ollama-$model_dir:latest $repo_uri:latest
        docker tag ollama-$model_dir:latest $repo_uri:$(date +%Y%m%d-%H%M%S)
        
        docker push $repo_uri:latest
        docker push $repo_uri:$(date +%Y%m%d-%H%M%S)
        print_color "green" "✅ $model_name image pushed successfully"
        
        cd ../../..
    fi
done

# イメージサイズの確認
print_color "blue" "📊 Image sizes:"
docker images | grep ollama | awk '{print $1 ":" $2 " - " $7 $8}'

# クリーンアップ（オプション）
read -p "🗑️  Do you want to clean up local Docker images? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_color "blue" "🧹 Cleaning up local images..."
    docker images | grep ollama | awk '{print $3}' | xargs docker rmi -f || true
    print_color "green" "✅ Local images cleaned up"
fi

print_color "green" "🎉 All images built and pushed successfully!"
print_color "blue" "📋 ECR Repository URIs:"
echo "Base: $BASE_REPO_URI"
for model_dir in "${!MODELS[@]}"; do
    repo_name="$ENVIRONMENT-ollama-$model_dir"
    repo_uri="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$repo_name"
    echo "$model_dir: $repo_uri"
done
