#!/bin/bash

# Lambda関数をパッケージングしてS3にアップロードするスクリプト

set -e

# 設定
AWS_REGION=${AWS_REGION:-us-east-1}
ENVIRONMENT=${ENVIRONMENT:-production}
S3_BUCKET="$ENVIRONMENT-ollama-platform-artifacts"
LAMBDA_DIR="lambda-functions"

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

print_color "blue" "📦 Starting Lambda function packaging..."

# 作業用ディレクトリを作成
WORK_DIR=$(mktemp -d)
print_color "blue" "Working directory: $WORK_DIR"

# Lambda関数をパッケージング
package_lambda() {
    local function_name=$1
    local source_dir="$LAMBDA_DIR/$function_name"
    
    if [ ! -d "$source_dir" ]; then
        print_color "yellow" "⚠️  Directory $source_dir not found, skipping..."
        return
    fi
    
    print_color "blue" "📦 Packaging $function_name..."
    
    # 作業用サブディレクトリを作成
    local work_subdir="$WORK_DIR/$function_name"
    mkdir -p "$work_subdir"
    
    # ソースファイルをコピー
    cp -r "$source_dir"/* "$work_subdir/"
    
    cd "$work_subdir"
    
    # requirements.txtが存在する場合は依存関係をインストール
    if [ -f "requirements.txt" ]; then
        print_color "blue" "   Installing dependencies..."
        pip install -r requirements.txt -t . --quiet
    fi
    
    # ZIPファイルを作成
    local zip_file="$function_name.zip"
    zip -r "$zip_file" . -x "*.pyc" "__pycache__/*" "*.zip" >/dev/null
    
    # S3にアップロード
    print_color "blue" "   Uploading to S3..."
    aws s3 cp "$zip_file" "s3://$S3_BUCKET/lambda-functions/$zip_file"
    
    print_color "green" "✅ $function_name packaged and uploaded"
    
    cd - >/dev/null
}

# 各Lambda関数をパッケージング
LAMBDA_FUNCTIONS=(
    "instances"
    "models"
    "auth"
)

for func in "${LAMBDA_FUNCTIONS[@]}"; do
    package_lambda "$func"
done

# クリーンアップ
rm -rf "$WORK_DIR"

print_color "green" "🎉 All Lambda functions packaged successfully!"
print_color "blue" "📋 Uploaded packages:"
for func in "${LAMBDA_FUNCTIONS[@]}"; do
    echo "  - s3://$S3_BUCKET/lambda-functions/$func.zip"
done
