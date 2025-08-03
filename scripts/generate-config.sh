#!/bin/bash

# CloudFormation出力から環境変数を動的生成するシンプルスクリプト

set -e

STACK_NAME=${1:-"aws-ollama-platform"}
FRONTEND_DIR="src/test/my-app"
OUTPUT_FILE="$FRONTEND_DIR/.env.production"

echo "🔧 Generating configuration from CloudFormation stack: $STACK_NAME"

# CloudFormationスタックの存在確認
if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" >/dev/null 2>&1; then
    echo "❌ Error: CloudFormation stack '$STACK_NAME' not found"
    echo "💡 Please deploy the infrastructure first using: sh scripts/deploy.sh"
    exit 1
fi

# スタック出力を取得
echo "📥 Retrieving stack outputs..."

# 各出力値を直接取得する関数
get_output_value() {
    local output_key=$1
    aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --query "Stacks[0].Outputs[?OutputKey=='$output_key'].OutputValue" \
        --output text 2>/dev/null || echo "NOT_FOUND"
}

echo "🔍 Extracting configuration values..."

API_GATEWAY_URL=$(get_output_value "APIGatewayURL")
USER_POOL_ID=$(get_output_value "UserPoolId")
USER_POOL_CLIENT_ID=$(get_output_value "UserPoolClientId")
S3_BUCKET_NAME=$(get_output_value "S3BucketName")
CLOUDFRONT_URL=$(get_output_value "CloudFrontURL")
AWS_REGION=$(aws configure get region)

# 必須値の存在確認
if [ "$API_GATEWAY_URL" == "NOT_FOUND" ] || [ -z "$API_GATEWAY_URL" ]; then
    echo "❌ Error: ApiGatewayUrl not found in CloudFormation outputs"
    exit 1
fi

if [ "$USER_POOL_ID" == "NOT_FOUND" ] || [ -z "$USER_POOL_ID" ]; then
    echo "❌ Error: UserPoolId not found in CloudFormation outputs"
    exit 1
fi

if [ "$USER_POOL_CLIENT_ID" == "NOT_FOUND" ] || [ -z "$USER_POOL_CLIENT_ID" ]; then
    echo "❌ Error: UserPoolClientId not found in CloudFormation outputs"
    exit 1
fi

# 設定ファイルの生成
echo "📝 Generating configuration file: $OUTPUT_FILE"

# ディレクトリが存在しない場合は作成
mkdir -p "$(dirname "$OUTPUT_FILE")"

# 環境変数ファイルを生成
cat > "$OUTPUT_FILE" << EOF
# 本番環境設定（自動生成）
# Generated at: $(date)
# CloudFormation Stack: $STACK_NAME

# API Configuration
VITE_API_URL=$API_GATEWAY_URL

# AWS Configuration
VITE_AWS_REGION=$AWS_REGION

# Cognito Configuration
VITE_USER_POOL_ID=$USER_POOL_ID
VITE_USER_POOL_CLIENT_ID=$USER_POOL_CLIENT_ID

# Environment
VITE_ENVIRONMENT=production
EOF

echo "✅ Configuration file generated successfully!"
echo ""
echo "📋 Generated configuration:"
echo "----------------------------------------"
echo "API Gateway URL: $API_GATEWAY_URL"
echo "User Pool ID: $USER_POOL_ID"
echo "User Pool Client ID: $USER_POOL_CLIENT_ID"
echo "AWS Region: $AWS_REGION"
echo "----------------------------------------"

echo ""
echo "🎉 Configuration generation completed!"
echo "💡 Next steps:"
echo "   1. Build the frontend: cd $FRONTEND_DIR && npm run build"
echo "   2. Deploy to S3: aws s3 sync dist/ s3://$S3_BUCKET_NAME/"
if [ "$CLOUDFRONT_URL" != "NOT_FOUND" ] && [ -n "$CLOUDFRONT_URL" ]; then
    echo "   3. Access your app: $CLOUDFRONT_URL"
fi
