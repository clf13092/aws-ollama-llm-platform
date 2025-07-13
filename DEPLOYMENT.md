# AWS Ollama Platform - デプロイメントガイド

## 🚀 概要

このガイドでは、AWS Ollama Platformを AWS 環境にデプロイする方法を詳しく説明します。CloudFormationを使用して、認証機能付きのセキュアなOllamaプラットフォームを構築できます。

## 📋 前提条件

### 必要なツール

```bash
# AWS CLI (バージョン2推奨)
aws --version

# jq (JSON処理用)
jq --version

# curl (テスト用)
curl --version
```

### AWS 権限

デプロイには以下のAWS権限が必要です：

- **IAM**: ロール・ポリシーの作成・管理
- **VPC**: ネットワークリソースの作成・管理
- **EC2**: セキュリティグループ・サブネットの管理
- **ECS**: クラスタ・サービスの作成・管理
- **Application Load Balancer**: ロードバランサーの作成・管理
- **DynamoDB**: テーブルの作成・管理
- **Cognito**: User Pool・Identity Poolの作成・管理
- **Lambda**: 関数の作成・実行
- **API Gateway**: APIの作成・管理
- **CloudFormation**: スタックの作成・管理
- **S3**: バケットの作成・管理（フロントエンド用）
- **CloudFront**: ディストリビューションの作成・管理

## 🛠️ デプロイ手順

### ステップ 1: リポジトリのクローン

```bash
git clone https://github.com/clf13092/aws-ollama-llm-platform.git
cd aws-ollama-llm-platform
```

### ステップ 2: AWS 認証情報の設定

```bash
# AWS CLI の設定
aws configure

# または、環境変数での設定
export AWS_ACCESS_KEY_ID=your_access_key
export AWS_SECRET_ACCESS_KEY=your_secret_key
export AWS_DEFAULT_REGION=us-east-1
```

### ステップ 3: パラメータの設定

パラメータファイルをコピーして編集します：

```bash
cp parameters-template.json parameters.json
```

`parameters.json` を編集：

```json
[
  {
    "ParameterKey": "Environment",
    "ParameterValue": "production"
  },
  {
    "ParameterKey": "DomainName",
    "ParameterValue": "ollama.yourdomain.com"
  },
  {
    "ParameterKey": "AdminEmail",
    "ParameterValue": "admin@yourdomain.com"
  },
  {
    "ParameterKey": "EnableMFA",
    "ParameterValue": "false"
  },
  {
    "ParameterKey": "CertificateArn",
    "ParameterValue": ""
  }
]
```

### ステップ 4: デプロイの実行

#### 方法 1: デプロイスクリプトを使用（推奨）

```bash
# 基本的なデプロイ
./scripts/deploy.sh \
  --domain ollama.yourdomain.com \
  --admin-email admin@yourdomain.com

# カスタム設定でのデプロイ
./scripts/deploy.sh \
  --region us-west-2 \
  --environment staging \
  --domain ollama-staging.yourdomain.com \
  --admin-email admin@yourdomain.com

# 既存スタックの更新
./scripts/deploy.sh \
  --domain ollama.yourdomain.com \
  --admin-email admin@yourdomain.com \
  --update

# ドライラン（実際にはデプロイしない）
./scripts/deploy.sh \
  --domain ollama.yourdomain.com \
  --admin-email admin@yourdomain.com \
  --dry-run
```

#### 方法 2: AWS CLI を直接使用

```bash
# テンプレートの検証
aws cloudformation validate-template \
  --template-body file://cloudformation/main.yaml

# スタックの作成
aws cloudformation create-stack \
  --stack-name aws-ollama-platform \
  --template-body file://cloudformation/main.yaml \
  --parameters file://parameters.json \
  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
  --region us-east-1

# デプロイ状況の確認
aws cloudformation describe-stacks \
  --stack-name aws-ollama-platform \
  --region us-east-1
```

### ステップ 5: デプロイの完了を確認

```bash
# スタックの状態確認
aws cloudformation describe-stacks \
  --stack-name aws-ollama-platform \
  --query 'Stacks[0].StackStatus'

# 出力値の確認
aws cloudformation describe-stacks \
  --stack-name aws-ollama-platform \
  --query 'Stacks[0].Outputs'
```

## 🔧 初期設定

### 管理者ユーザーの作成

デプロイ完了後、初期管理者ユーザーを作成：

```bash
# User Pool IDを取得
USER_POOL_ID=$(aws cloudformation describe-stacks \
  --stack-name aws-ollama-platform \
  --query 'Stacks[0].Outputs[?OutputKey==`UserPoolId`].OutputValue' \
  --output text)

# 管理者ユーザーを作成
aws cognito-idp admin-create-user \
  --user-pool-id $USER_POOL_ID \
  --username admin \
  --user-attributes Name=email,Value=admin@yourdomain.com \
  --temporary-password TempPass123! \
  --message-action SUPPRESS
```

### 管理画面へのアクセス

```bash
# CloudFront URLを取得
CLOUDFRONT_URL=$(aws cloudformation describe-stacks \
  --stack-name aws-ollama-platform \
  --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontURL`].OutputValue' \
  --output text)

echo "管理画面URL: $CLOUDFRONT_URL"
```

1. 上記URLにアクセス
2. 以下の認証情報でログイン：
   - **ユーザー名**: `admin`
   - **パスワード**: `TempPass123!`
3. 初回ログイン時にパスワードを変更
4. ダッシュボードからモデルのデプロイを開始

## 🔍 トラブルシューティング

### よくある問題と解決方法

#### 1. 権限エラー

```
Error: User is not authorized to perform: iam:CreateRole
```

**解決方法**: AWS アカウントに適切なIAM権限があることを確認

```bash
# 現在のユーザー情報を確認
aws sts get-caller-identity

# 必要な権限の確認
aws iam simulate-principal-policy \
  --policy-source-arn $(aws sts get-caller-identity --query Arn --output text) \
  --action-names iam:CreateRole cloudformation:CreateStack
```

#### 2. リソース制限エラー

```
Error: The maximum number of VPCs has been reached
```

**解決方法**: 既存のリソースを削除するか、リソース制限の増加をリクエスト

```bash
# VPC使用状況の確認
aws ec2 describe-vpcs --query 'length(Vpcs)'
```

#### 3. ネストされたスタックエラー

```
Error: S3 bucket does not exist
```

**解決方法**: S3バケットを作成してテンプレートをアップロード

```bash
# S3バケットの作成
aws s3 mb s3://your-cloudformation-templates-bucket

# テンプレートのアップロード
aws s3 sync cloudformation/ s3://your-cloudformation-templates-bucket/
```

### デプロイ状況の確認

```bash
# スタックイベントの確認
aws cloudformation describe-stack-events \
  --stack-name aws-ollama-platform \
  --max-items 10

# 失敗したリソースの確認
aws cloudformation describe-stack-events \
  --stack-name aws-ollama-platform \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]'
```

### ログの確認

```bash
# CloudWatch Logsの確認
aws logs describe-log-groups \
  --log-group-name-prefix "/aws/lambda/production-ollama"

# 特定のログストリームの内容確認
aws logs get-log-events \
  --log-group-name "/aws/lambda/production-ollama-api" \
  --log-stream-name "2024/01/01/[LATEST]"
```

## 🔄 更新とメンテナンス

### スタックの更新

```bash
# パラメータを変更してスタックを更新
./scripts/deploy.sh \
  --domain ollama.yourdomain.com \
  --admin-email admin@yourdomain.com \
  --update

# または AWS CLI で直接更新
aws cloudformation update-stack \
  --stack-name aws-ollama-platform \
  --template-body file://cloudformation/main.yaml \
  --parameters file://parameters.json \
  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM
```

### バックアップ

```bash
# DynamoDB テーブルのバックアップ
aws dynamodb create-backup \
  --table-name production-ollama-models \
  --backup-name ollama-models-backup-$(date +%Y%m%d)

aws dynamodb create-backup \
  --table-name production-ollama-instances \
  --backup-name ollama-instances-backup-$(date +%Y%m%d)
```

### モニタリング

```bash
# CloudWatch メトリクスの確認
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name ConsumedReadCapacityUnits \
  --dimensions Name=TableName,Value=production-ollama-models \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Average
```

## 🗑️ スタックの削除

### ⚠️ 注意事項

**データの完全削除**: 削除操作は元に戻せません。重要なデータは事前にバックアップしてください。

### 削除手順

```bash
# 削除スクリプトを使用（推奨）
./scripts/cleanup.sh --stack-name aws-ollama-platform

# または AWS CLI で直接削除
aws cloudformation delete-stack \
  --stack-name aws-ollama-platform

# 削除完了の確認
aws cloudformation wait stack-delete-complete \
  --stack-name aws-ollama-platform
```

### 手動削除が必要なリソース

一部のリソースは手動での削除が必要な場合があります：

```bash
# S3 バケットの内容を削除
aws s3 rm s3://production-ollama-frontend-bucket --recursive
aws s3 rb s3://production-ollama-frontend-bucket

# CloudWatch Log Groups の削除
aws logs delete-log-group --log-group-name /aws/lambda/production-ollama-api
aws logs delete-log-group --log-group-name /ecs/production-ollama-models
```

## 💰 コスト最適化

### 推定コスト

**月額想定コスト（us-east-1リージョン）**:

- **基本インフラ**: $50-100/月
  - VPC, ALB, DynamoDB (軽量使用)
  - Cognito (月1000アクティブユーザーまで無料)
  - API Gateway (月100万リクエストまで無料枠あり)

- **モデル実行時**: $20-200/月（使用状況により変動）
  - ECS Fargate: $0.04048/vCPU/時間
  - ECS with EC2: より安価だが管理コストが増加

### コスト削減のヒント

```bash
# 未使用のインスタンスを自動停止
aws events put-rule \
  --name ollama-auto-stop \
  --schedule-expression "rate(1 hour)" \
  --description "Stop idle Ollama instances"

# Spot Instances の使用（開発環境）
# ECS タスク定義で capacity provider を FARGATE_SPOT に設定
```

## 📞 サポート

### コミュニティサポート

- **GitHub Issues**: [https://github.com/clf13092/aws-ollama-llm-platform/issues](https://github.com/clf13092/aws-ollama-llm-platform/issues)
- **Discussions**: [https://github.com/clf13092/aws-ollama-llm-platform/discussions](https://github.com/clf13092/aws-ollama-llm-platform/discussions)

### AWSサポート

- **AWS Support Center**: [https://console.aws.amazon.com/support/](https://console.aws.amazon.com/support/)
- **AWS CloudFormation ドキュメント**: [https://docs.aws.amazon.com/cloudformation/](https://docs.aws.amazon.com/cloudformation/)

---

**🎉 デプロイが完了したら、管理画面にアクセスして最初のOllamaモデルをデプロイしてみましょう！**