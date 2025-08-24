#!/bin/bash

# AWS Ollama プラットフォーム メインデプロイスクリプト
# このスクリプトは Docker イメージのビルド/プッシュ、インフラストラクチャのデプロイ、フロントエンドのアップロードを処理します。

set -e # コマンドがゼロ以外のステータスで終了した場合、即座に終了

# このスクリプトのディレクトリを取得してパスが正しいことを確認
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
PROJECT_ROOT=$(dirname "$SCRIPT_DIR")

# --- 設定 ---
STACK_NAME="aws-ollama-platform"
FRONTEND_DIR="$PROJECT_ROOT/frontend"
MAIN_TEMPLATE="cloudformation/main.yaml"
PACKAGED_TEMPLATE="packaged.yaml"
PARAMETERS_FILE="parameters.json"
AWS_REGION=$(aws configure get region)
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
S3_BUCKET_FOR_ARTIFACTS="aws-ollama-platform-artifacts-${AWS_ACCOUNT_ID}-${AWS_REGION}"
ENVIRONMENT="production"

# --- 関数 ---

# カラー出力を印刷する関数
print_color() {
    COLOR=$1
    MESSAGE=$2
    NC='\033[0m' # カラーなし
    case $COLOR in
        "green") echo -e "\033[0;32m${MESSAGE}${NC}" ;;
        "blue")  echo -e "\033[0;34m${MESSAGE}${NC}" ;;
        "red")   echo -e "\033[0;31m${MESSAGE}${NC}" ;;
        "yellow") echo -e "\033[0;33m${MESSAGE}${NC}" ;;
        *)       echo "${MESSAGE}" ;;
    esac
}

# CloudFormationスタックから特定の出力値を取得する関数
get_stack_output() {
    local stack_name=$1
    local output_key=$2
    
    aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --query "Stacks[0].Outputs[?OutputKey=='$output_key'].OutputValue" \
        --output text 2>/dev/null
}

# Dockerイメージをビルドしてプッシュする関数
build_and_push_images() {
    print_color "blue" "🐳 DockerイメージをビルドしてECRにプッシュしています..."

    # ECRにログイン
    print_color "blue" "🔐 ECRにログインしています..."
    aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

    # メインのCFnスタックからリポジトリURIを取得
    print_color "blue" "📋 CloudFormationスタック '$STACK_NAME' からECRリポジトリURIを取得しています..."
    BASE_REPO_URI=$(get_stack_output "$STACK_NAME" "OllamaRepositoryUri")

    if [ -z "$BASE_REPO_URI" ]; then
        print_color "red" "❌ CloudFormationスタック '$STACK_NAME' からOllamaRepositoryUriの取得に失敗しました。"
        return 1
    fi
    print_color "green" "✅ ECRリポジトリURI取得完了: $BASE_REPO_URI"

    # ベースイメージをビルド（linux/amd64プラットフォームを明示的に指定）
    local base_docker_dir="$PROJECT_ROOT/docker/base"
    print_color "blue" "🏗️  '$base_docker_dir' からlinux/amd64用のベースOllamaイメージをビルドしています..."

    if [ -d "$base_docker_dir" ] && [ -f "$base_docker_dir/Dockerfile" ]; then
        local image_tag="$BASE_REPO_URI:latest"
        local timestamp_tag="$BASE_REPO_URI:$(date +%Y%m%d-%H%M%S)"

        # linux/amd64プラットフォームを明示的に指定してビルド
        print_color "blue" "linux/amd64プラットフォーム用にビルドしています..."
        docker build --platform linux/amd64 -t "$image_tag" "$base_docker_dir"
        docker tag "$image_tag" "$timestamp_tag"
        
        print_color "blue" "📤 ベースイメージをECRにプッシュしています..."
        docker push "$image_tag"
        docker push "$timestamp_tag"
        print_color "green" "✅ ベースイメージのプッシュが完了しました"
        
        # イメージの詳細情報を表示
        print_color "blue" "📋 イメージ詳細:"
        docker inspect "$image_tag" --format='{{.Architecture}} {{.Os}}' || true
    else
        print_color "red" "❌ '$base_docker_dir' にDockerfileが見つかりません。ベースイメージをビルドできません。"
        return 1
    fi

    # 注意: 将来必要に応じて、モデル固有のイメージをビルドするロジックをここに追加してください。

    print_color "green" "🎉 すべてのDockerイメージのビルドとプッシュが完了しました！"
}


# --- メインデプロイプロセス ---

print_color "blue" "🚀 AWS Ollama プラットフォームのデプロイを開始しています..."

# 1. フロントエンドの依存関係をインストール（初期ビルドは設定更新後に実行）
print_color "blue" "
[ステップ 1/5] フロントエンドの依存関係をインストールしています..."
if [ -d "$FRONTEND_DIR/node_modules" ]; then
    print_color "green" "node_modulesは既に存在するため、インストールをスキップします。"
else
    (cd "$FRONTEND_DIR" && npm install)
fi
print_color "green" "フロントエンドの依存関係の準備が完了しました。"

# 2. CloudFormationテンプレートをパッケージ化
print_color "blue" "
[ステップ 2/5] CloudFormationテンプレートをパッケージ化しています..."
aws cloudformation package \
  --template-file "$MAIN_TEMPLATE" \
  --s3-bucket "$S3_BUCKET_FOR_ARTIFACTS" \
  --output-template-file "$PACKAGED_TEMPLATE"
print_color "green" "CloudFormationテンプレートを $PACKAGED_TEMPLATE にパッケージ化しました。"

# parameters.jsonをチェックし、存在しない場合はテンプレートから作成
if [ ! -f "$PROJECT_ROOT/$PARAMETERS_FILE" ]; then
    print_color "yellow" "⚠️  プロジェクトルートに $PARAMETERS_FILE が見つかりません。"
    if [ -f "$PROJECT_ROOT/parameters-template.json" ]; then
        print_color "blue" "テンプレートから $PARAMETERS_FILE を作成しています..."
        cp "$PROJECT_ROOT/parameters-template.json" "$PROJECT_ROOT/$PARAMETERS_FILE"
        print_color "green" "✅ $PARAMETERS_FILE を正常に作成しました。"
        print_color "yellow" "重要: 新しく作成された '$PARAMETERS_FILE' を確認・編集してから、スクリプトを再実行してください。"
        exit 1
    else
        print_color "red" "❌ 'parameters-template.json' が見つかりません。'$PARAMETERS_FILE' を作成できません。"
        exit 1
    fi
fi

# 3. メインのCloudFormationスタックをデプロイ
print_color "blue" "
[ステップ 3/5] CloudFormationでメインのAWSインフラストラクチャをデプロイしています..."
aws cloudformation deploy \
    --template-file "$PACKAGED_TEMPLATE" \
    --stack-name "$STACK_NAME" \
    --parameter-overrides file://"$PARAMETERS_FILE" \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset
print_color "green" "✅ CloudFormationスタックのデプロイを開始しました。"

print_color "blue" "スタックのデプロイ完了を待機しています..."
aws cloudformation wait stack-create-complete --stack-name "$STACK_NAME" 2>/dev/null || \
aws cloudformation wait stack-update-complete --stack-name "$STACK_NAME"
print_color "green" "✅ CloudFormationスタックのデプロイが完了しました。"


# 4. Dockerイメージをビルドしてプッシュ（メインスタックの準備完了後）
print_color "blue" "
[ステップ 4/5] Dockerイメージをビルドしてプッシュしています..."
build_and_push_images

# ステップ 5: フロントエンドアセットをS3にデプロイし、CloudFrontキャッシュを無効化
print_color "blue" "
[ステップ 5/5] フロントエンドアセットをデプロイし、CloudFrontキャッシュを無効化しています..."

# CloudFormationスタックから出力を取得
print_color "blue" "スタック出力を取得しています..."
FRONTEND_S3_BUCKET_NAME=$(get_stack_output "$STACK_NAME" "FrontendS3BucketName")
CLOUDFRONT_DISTRIBUTION_ID=$(get_stack_output "$STACK_NAME" "CloudFrontDistributionId")
CLOUDFRONT_URL=$(get_stack_output "$STACK_NAME" "CloudFrontURL")
USER_POOL_ID=$(get_stack_output "$STACK_NAME" "UserPoolId")
USER_POOL_CLIENT_ID=$(get_stack_output "$STACK_NAME" "UserPoolClientId")
API_GATEWAY_URL=$(get_stack_output "$STACK_NAME" "APIGatewayURL")

if [ -z "$FRONTEND_S3_BUCKET_NAME" ] || [ -z "$USER_POOL_ID" ] || [ -z "$USER_POOL_CLIENT_ID" ]; then
    print_color "red" "エラー: CloudFormationスタックから必要な出力を取得できませんでした。"
    print_color "red" "不足: FrontendS3BucketName、UserPoolId、またはUserPoolClientId"
    exit 1
fi

print_color "green" "スタック出力を取得しました:"
print_color "green" "- S3バケット: $FRONTEND_S3_BUCKET_NAME"
print_color "green" "- CloudFront ID: $CLOUDFRONT_DISTRIBUTION_ID"
print_color "green" "- ユーザープールID: $USER_POOL_ID"
print_color "green" "- ユーザープールクライアントID: $USER_POOL_CLIENT_ID"
print_color "green" "- API Gateway URL: $API_GATEWAY_URL"

# 実際にデプロイされた値でフロントエンド環境設定を更新
print_color "blue" "フロントエンド環境設定を更新しています..."

# 既存の設定ファイルをバックアップ
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
if [ -f "$ENV_PRODUCTION_FILE" ]; then
    cp "$ENV_PRODUCTION_FILE" "$ENV_PRODUCTION_FILE.backup.$TIMESTAMP"
    print_color "blue" "既存の .env.production を .env.production.backup.$TIMESTAMP にバックアップしました"
fi

# 実際にデプロイされた値で .env.production を生成
ENV_PRODUCTION_FILE="$FRONTEND_DIR/.env.production"
cat > "$ENV_PRODUCTION_FILE" << EOF
# 本番環境設定（自動生成）
# 生成日時: $(date)
# CloudFormationスタック: $STACK_NAME

# API設定
VITE_API_URL=$API_GATEWAY_URL

# AWS設定
VITE_AWS_REGION=$AWS_REGION

# Cognito設定
VITE_USER_POOL_ID=$USER_POOL_ID
VITE_USER_POOL_CLIENT_ID=$USER_POOL_CLIENT_ID

# 環境
VITE_ENVIRONMENT=production
EOF

print_color "green" "✅ デプロイされた値で .env.production を更新しました:"
print_color "blue" "   - API URL: $API_GATEWAY_URL"
print_color "blue" "   - AWSリージョン: $AWS_REGION"
print_color "blue" "   - ユーザープールID: $USER_POOL_ID"
print_color "blue" "   - クライアントID: $USER_POOL_CLIENT_ID"

# 開発環境の一貫性のために .env.local も更新
ENV_LOCAL_FILE="$FRONTEND_DIR/.env.local"
if [ -f "$ENV_LOCAL_FILE" ]; then
    cp "$ENV_LOCAL_FILE" "$ENV_LOCAL_FILE.backup.$TIMESTAMP"
fi

cat > "$ENV_LOCAL_FILE" << EOF
# 開発環境設定（実際のCognito設定を使用）
# 生成日時: $(date)

# APIエンドポイント（本番環境では実際のAPI Gateway URLを設定）
VITE_API_URL=$API_GATEWAY_URL

# AWS設定（実際の値）
VITE_AWS_REGION=$AWS_REGION
VITE_USER_POOL_ID=$USER_POOL_ID
VITE_USER_POOL_CLIENT_ID=$USER_POOL_CLIENT_ID


# 環境
VITE_ENVIRONMENT=development
EOF

print_color "green" "✅ 開発環境の一貫性のために .env.local を更新しました"

# 更新された設定でフロントエンドを再ビルド
print_color "blue" "更新された設定でフロントエンドを再ビルドしています..."
(cd "$FRONTEND_DIR" && npm run build)
print_color "green" "✅ 更新された設定でフロントエンドを再ビルドしました"

# フロントエンド用の設定ファイルを作成（JavaScriptコンフィグをフォールバックとして）
print_color "blue" "ランタイム設定ファイルを生成しています..."
CONFIG_JS="window.AWS_OLLAMA_CONFIG = { 
  region: '$AWS_REGION', 
  userPoolId: '$USER_POOL_ID', 
  userPoolWebClientId: '$USER_POOL_CLIENT_ID',
  apiUrl: '${API_GATEWAY_URL:-https://api.example.com}'
};"
echo "$CONFIG_JS" > "$FRONTEND_DIR/dist/config.js"
print_color "green" "✅ ランタイム設定ファイルを作成しました"

# ビルドディレクトリをS3バケットと同期
print_color "blue" "アセットをS3にアップロードしています..."
aws s3 sync "$FRONTEND_DIR/dist/" "s3://$FRONTEND_S3_BUCKET_NAME/" --delete
print_color "green" "- フロントエンドアセットをS3に同期しました。"

# CloudFrontキャッシュを無効化
if [ -n "$CLOUDFRONT_DISTRIBUTION_ID" ]; then
    print_color "blue" "CloudFrontキャッシュを無効化しています..."
    aws cloudfront create-invalidation --distribution-id "$CLOUDFRONT_DISTRIBUTION_ID" --paths "/*" > /dev/null
    print_color "green" "- CloudFrontキャッシュの無効化を作成しました。"
fi

print_color "blue" "
--------------------------------------------------"
print_color "green" "🚀 デプロイ成功！ 🚀"
print_color "blue" "--------------------------------------------------"
print_color "green" "以下のURLでアプリケーションにアクセスできます:"
print_color "blue" "$CLOUDFRONT_URL"
print_color "blue" ""
print_color "green" "設定概要:"
print_color "blue" "- CloudFormationスタック: $STACK_NAME"
print_color "blue" "- AWSリージョン: $AWS_REGION"
print_color "blue" "- ユーザープールID: $USER_POOL_ID"
print_color "blue" "- クライアントID: $USER_POOL_CLIENT_ID"
print_color "blue" "- API Gateway URL: $API_GATEWAY_URL"
print_color "blue" "- S3バケット: $FRONTEND_S3_BUCKET_NAME"
print_color "blue" "- CloudFrontディストリビューション: $CLOUDFRONT_DISTRIBUTION_ID"
print_color "blue" ""
print_color "yellow" "次のステップ:"
print_color "blue" "1. 以下のURLでアプリケーションにアクセス: $CLOUDFRONT_URL"
print_color "blue" ""
print_color "blue" "2. parameters.jsonの認証情報でログイン:"
print_color "blue" "   ユーザー名: admin"
print_color "blue" "   パスワード: $(grep -o '"AdminPassword"[^"]*"[^"]*"[^"]*"[^"]*' $PROJECT_ROOT/parameters.json | cut -d'"' -f8 2>/dev/null || echo 'parameters.jsonを確認してください')"
print_color "blue" ""
print_color "green" "✅ パスワード変更は不要です - 直接ログインできます！"
print_color "blue" ""
print_color "green" "設定ファイルが更新されました:"
print_color "blue" "- $FRONTEND_DIR/.env.production （実際にデプロイされた値）"
print_color "blue" "- $FRONTEND_DIR/.env.local （開発用）"
print_color "blue" "- バックアップファイルがタイムスタンプ付きで作成されました: $TIMESTAMP"
