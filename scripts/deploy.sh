#!/bin/bash

# Main deployment script for the AWS Ollama Platform
# This script handles ECR CloudFormation deployment, Docker image build/push, infrastructure deployment, and frontend upload.

set -e # Exit immediately if a command exits with a non-zero status.

# --- Configuration ---
STACK_NAME="aws-ollama-platform"
ECR_STACK_NAME="aws-ollama-platform-ecr"
FRONTEND_DIR="frontend"
MAIN_TEMPLATE="cloudformation/main.yaml"
ECR_TEMPLATE="cloudformation/storage/ecr.yaml"
PACKAGED_TEMPLATE="cloudformation/packaged.yaml"
PARAMETERS_FILE="parameters.json"
AWS_REGION=$(aws configure get region)
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
S3_BUCKET_FOR_ARTIFACTS="aws-ollama-platform-artifacts"
ENVIRONMENT="production"

# --- Functions ---

# Function to print colored output
print_color() {
    COLOR=$1
    MESSAGE=$2
    NC='\033[0m' # No Color
    case $COLOR in
        "green") echo -e "\033[0;32m${MESSAGE}${NC}" ;;
        "blue")  echo -e "\033[0;34m${MESSAGE}${NC}" ;;
        "red")   echo -e "\033[0;31m${MESSAGE}${NC}" ;;
        "yellow") echo -e "\033[0;33m${MESSAGE}${NC}" ;;
        *)       echo "${MESSAGE}" ;;
    esac
}

# Function to get CloudFormation stack output
get_stack_output() {
    local stack_name=$1
    local output_key=$2
    aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --query "Stacks[0].Outputs[?OutputKey=='$output_key'].OutputValue" \
        --output text 2>/dev/null || echo ""
}

# Function to deploy ECR stack
deploy_ecr_stack() {
    print_color "blue" "🏗️  Deploying ECR repositories with CloudFormation..."
    
    # ECRスタックの存在確認
    if aws cloudformation describe-stacks --stack-name "$ECR_STACK_NAME" >/dev/null 2>&1; then
        STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "$ECR_STACK_NAME" --query "Stacks[0].StackStatus" --output text)
        print_color "blue" "ECR Stack $ECR_STACK_NAME exists with status: $STACK_STATUS"
        
        case "$STACK_STATUS" in
            "CREATE_COMPLETE"|"UPDATE_COMPLETE")
                print_color "green" "ECR stack is ready."
                ;;
            "CREATE_IN_PROGRESS"|"UPDATE_IN_PROGRESS")
                print_color "blue" "ECR stack is being processed. Waiting for completion..."
                aws cloudformation wait stack-create-complete --stack-name "$ECR_STACK_NAME" 2>/dev/null || \
                aws cloudformation wait stack-update-complete --stack-name "$ECR_STACK_NAME"
                print_color "green" "ECR stack processing completed."
                ;;
            "ROLLBACK_COMPLETE")
                print_color "red" "ECR stack is in ROLLBACK_COMPLETE state. Deleting it..."
                aws cloudformation delete-stack --stack-name "$ECR_STACK_NAME"
                aws cloudformation wait stack-delete-complete --stack-name "$ECR_STACK_NAME"
                print_color "green" "ECR stack deleted. Will create new one."
                deploy_ecr_stack_create
                ;;
            *)
                print_color "yellow" "ECR stack in state: $STACK_STATUS. Attempting update..."
                deploy_ecr_stack_update
                ;;
        esac
    else
        print_color "blue" "ECR stack does not exist. Creating new stack..."
        deploy_ecr_stack_create
    fi
}

# Function to create ECR stack
deploy_ecr_stack_create() {
    aws cloudformation create-stack \
        --stack-name "$ECR_STACK_NAME" \
        --template-body file://"$ECR_TEMPLATE" \
        --parameters ParameterKey=Environment,ParameterValue="$ENVIRONMENT" \
        --tags Key=Environment,Value="$ENVIRONMENT" Key=Project,Value="aws-ollama-platform"
    
    print_color "blue" "Waiting for ECR stack creation to complete..."
    aws cloudformation wait stack-create-complete --stack-name "$ECR_STACK_NAME"
    print_color "green" "✅ ECR stack created successfully"
}

# Function to update ECR stack
deploy_ecr_stack_update() {
    aws cloudformation deploy \
        --template-file "$ECR_TEMPLATE" \
        --stack-name "$ECR_STACK_NAME" \
        --parameter-overrides Environment="$ENVIRONMENT" \
        --tags Environment="$ENVIRONMENT" Project="aws-ollama-platform" \
        --no-fail-on-empty-changeset
    
    print_color "green" "✅ ECR stack updated successfully"
}

# Function to build and push Docker images
build_and_push_images() {
    print_color "blue" "🐳 Building and pushing Docker images to ECR..."
    
    # ECRにログイン
    print_color "blue" "🔐 Logging in to ECR..."
    aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
    
    # ECRスタックからリポジトリURIを取得
    print_color "blue" "📋 Getting ECR repository URIs from CloudFormation..."
    BASE_REPO_URI=$(get_stack_output "$ECR_STACK_NAME" "OllamaBaseRepositoryUri")
    LLAMA2_7B_REPO_URI=$(get_stack_output "$ECR_STACK_NAME" "OllamaLlama2_7bRepositoryUri")
    LLAMA2_13B_REPO_URI=$(get_stack_output "$ECR_STACK_NAME" "OllamaLlama2_13bRepositoryUri")
    CODELLAMA_7B_REPO_URI=$(get_stack_output "$ECR_STACK_NAME" "OllamaCodeLlama7bRepositoryUri")
    CODELLAMA_13B_REPO_URI=$(get_stack_output "$ECR_STACK_NAME" "OllamaCodeLlama13bRepositoryUri")
    MISTRAL_7B_REPO_URI=$(get_stack_output "$ECR_STACK_NAME" "OllamaMistral7bRepositoryUri")
    
    if [ -z "$BASE_REPO_URI" ]; then
        print_color "red" "❌ Failed to get ECR repository URIs from CloudFormation stack"
        exit 1
    fi
    
    print_color "green" "✅ ECR repository URIs retrieved successfully"
    
    # ベースイメージをビルド
    print_color "blue" "🏗️  Building base Ollama image..."
    
    if [ -d "docker/base" ]; then
        cd docker/base
        docker build -t ollama-base:latest .
        docker tag ollama-base:latest $BASE_REPO_URI:latest
        docker tag ollama-base:latest $BASE_REPO_URI:$(date +%Y%m%d-%H%M%S)
        
        print_color "blue" "📤 Pushing base image to ECR..."
        docker push $BASE_REPO_URI:latest
        docker push $BASE_REPO_URI:$(date +%Y%m%d-%H%M%S)
        print_color "green" "✅ Base image pushed successfully"
        cd ../..
    else
        print_color "red" "❌ Docker base directory not found. Please ensure docker/base exists."
        exit 1
    fi
    
    # モデル固有のイメージをビルド
    declare -A MODEL_REPOS=(
        ["llama2-7b"]="$LLAMA2_7B_REPO_URI"
        ["llama2-13b"]="$LLAMA2_13B_REPO_URI"
        ["codellama-7b"]="$CODELLAMA_7B_REPO_URI"
        ["codellama-13b"]="$CODELLAMA_13B_REPO_URI"
        ["mistral-7b"]="$MISTRAL_7B_REPO_URI"
    )
    
    declare -A MODELS=(
        ["llama2-7b"]="llama2:7b"
        ["llama2-13b"]="llama2:13b"
        ["codellama-7b"]="codellama:7b"
        ["codellama-13b"]="codellama:13b"
        ["mistral-7b"]="mistral:7b"
    )
    
    for model_dir in "${!MODELS[@]}"; do
        model_name="${MODELS[$model_dir]}"
        repo_uri="${MODEL_REPOS[$model_dir]}"
        
        if [ -z "$repo_uri" ]; then
            print_color "yellow" "⚠️  Repository URI not found for $model_dir, skipping..."
            continue
        fi
        
        print_color "blue" "🏗️  Building $model_name image..."
        
        # Dockerfileが存在しない場合は汎用的なものを作成
        if [ ! -f "docker/models/$model_dir/Dockerfile" ]; then
            print_color "yellow" "⚠️  Creating generic Dockerfile for $model_dir..."
            mkdir -p docker/models/$model_dir
            cat > docker/models/$model_dir/Dockerfile << EOF
ARG BASE_IMAGE_URI
FROM \${BASE_IMAGE_URI}:latest

LABEL model="$model_name"
ENV MODEL_NAME=$model_name
ENV PRELOAD_MODEL=true
EOF
        fi
        
        cd docker/models/$model_dir
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
    done
    
    print_color "green" "🎉 All Docker images built and pushed successfully!"
}

# --- Main Deployment Process ---

print_color "blue" "🚀 Starting AWS Ollama Platform Deployment..."
print_color "blue" "AWS Account: $AWS_ACCOUNT_ID"
print_color "blue" "Region: $AWS_REGION"
print_color "blue" "Environment: $ENVIRONMENT"

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    print_color "red" "❌ Docker is not running. Please start Docker and try again."
    exit 1
fi

# Check for S3 bucket for CloudFormation artifacts
print_color "blue" "
Checking for S3 bucket for CloudFormation artifacts: $S3_BUCKET_FOR_ARTIFACTS"
if aws s3 ls "s3://$S3_BUCKET_FOR_ARTIFACTS" 2>&1 | grep -q 'NoSuchBucket'; then
    print_color "blue" "Creating S3 bucket for CloudFormation artifacts: $S3_BUCKET_FOR_ARTIFACTS"
    aws s3 mb "s3://$S3_BUCKET_FOR_ARTIFACTS" --region $AWS_REGION
    print_color "green" "S3 bucket $S3_BUCKET_FOR_ARTIFACTS created."
else
    print_color "green" "S3 bucket $S3_BUCKET_FOR_ARTIFACTS already exists."
fi

# 1. Deploy ECR repositories with CloudFormation
print_color "blue" "
[Step 1/7] Deploying ECR repositories..."
deploy_ecr_stack

# 2. Build and push Docker images
print_color "blue" "
[Step 2/7] Building and pushing Docker images..."
build_and_push_images

# 3. Build the React frontend application
print_color "blue" "
[Step 3/7] Building React frontend application..."
if [ -d "$FRONTEND_DIR/node_modules" ]; then
    print_color "green" "node_modules already exists, skipping installation."
else
    (cd "$FRONTEND_DIR" && npm install)
fi
(cd "$FRONTEND_DIR" && npm run build)
print_color "green" "Frontend build complete."

# 4. Package the CloudFormation templates
print_color "blue" "
[Step 4/7] Packaging CloudFormation templates..."
aws cloudformation package \
  --template-file "$MAIN_TEMPLATE" \
  --s3-bucket "$S3_BUCKET_FOR_ARTIFACTS" \
  --output-template-file "$PACKAGED_TEMPLATE"
print_color "green" "CloudFormation templates packaged to $PACKAGED_TEMPLATE."

# 5. Deploy the main CloudFormation stack
print_color "blue" "
[Step 5/7] Deploying main AWS infrastructure with CloudFormation..."

# スタックの存在確認
STACK_EXISTS=false
if aws cloudformation describe-stacks --stack-name "$STACK_NAME" >/dev/null 2>&1; then
    STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].StackStatus" --output text)
    print_color "blue" "Stack $STACK_NAME exists with status: $STACK_STATUS"
    
    case "$STACK_STATUS" in
        "CREATE_IN_PROGRESS")
            print_color "blue" "Stack is currently being created. Waiting for completion..."
            aws cloudformation wait stack-create-complete --stack-name "$STACK_NAME"
            print_color "green" "Stack creation completed."
            STACK_EXISTS=true
            ;;
        "UPDATE_IN_PROGRESS")
            print_color "blue" "Stack is currently being updated. Waiting for completion..."
            aws cloudformation wait stack-update-complete --stack-name "$STACK_NAME"
            print_color "green" "Stack update completed."
            STACK_EXISTS=true
            ;;
        "ROLLBACK_COMPLETE")
            print_color "red" "Stack is in ROLLBACK_COMPLETE state. Deleting it..."
            aws cloudformation delete-stack --stack-name "$STACK_NAME"
            aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME"
            print_color "green" "Stack deleted successfully."
            STACK_EXISTS=false
            ;;
        "CREATE_COMPLETE"|"UPDATE_COMPLETE")
            print_color "green" "Stack is ready for updates."
            STACK_EXISTS=true
            ;;
        "DELETE_IN_PROGRESS")
            print_color "blue" "Stack is being deleted. Waiting for completion..."
            aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME"
            print_color "green" "Stack deletion completed."
            STACK_EXISTS=false
            ;;
        *)
            print_color "red" "Stack is in unexpected state: $STACK_STATUS"
            print_color "red" "Please check the CloudFormation console and resolve manually."
            exit 1
            ;;
    esac
else
    print_color "blue" "Stack $STACK_NAME does not exist. Will create new stack."
    STACK_EXISTS=false
fi

# スタックの作成または更新
if [ "$STACK_EXISTS" = true ]; then
    print_color "blue" "Updating existing stack..."
    if aws cloudformation deploy \
      --template-file "$PACKAGED_TEMPLATE" \
      --stack-name "$STACK_NAME" \
      --parameter-overrides file://"$PARAMETERS_FILE" \
      --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
      --no-fail-on-empty-changeset; then
        print_color "green" "Stack update completed successfully."
    else
        print_color "red" "Stack update failed."
        exit 1
    fi
else
    print_color "blue" "Creating new stack..."
    if aws cloudformation create-stack \
      --stack-name "$STACK_NAME" \
      --template-body file://"$PACKAGED_TEMPLATE" \
      --parameters file://"$PARAMETERS_FILE" \
      --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM; then
        
        print_color "blue" "Waiting for stack creation to complete..."
        if aws cloudformation wait stack-create-complete --stack-name "$STACK_NAME"; then
            print_color "green" "Stack creation completed successfully."
        else
            print_color "red" "Stack creation failed or timed out."
            print_color "red" "Check the CloudFormation console for details."
            exit 1
        fi
    else
        print_color "red" "Failed to initiate stack creation."
        exit 1
    fi
fi

print_color "green" "CloudFormation stack deployment complete."

# 6. Get stack outputs
print_color "blue" "
[Step 6/7] Retrieving S3 bucket and CloudFront distribution from stack outputs..."

S3_BUCKET_NAME=$(get_stack_output "$STACK_NAME" "S3BucketName")
CLOUDFRONT_ID=$(get_stack_output "$STACK_NAME" "CloudFrontDistributionId")
CLOUDFRONT_URL=$(get_stack_output "$STACK_NAME" "CloudFrontURL")
USER_POOL_ID=$(get_stack_output "$STACK_NAME" "UserPoolId")
USER_POOL_CLIENT_ID=$(get_stack_output "$STACK_NAME" "UserPoolClientId")

print_color "green" "- User Pool ID: $USER_POOL_ID"
print_color "green" "- User Pool Client ID: $USER_POOL_CLIENT_ID"
print_color "green" "- S3 Bucket Name: $S3_BUCKET_NAME"
print_color "green" "- CloudFront ID: $CLOUDFRONT_ID"

# Check if we got the required outputs
if [ -z "$S3_BUCKET_NAME" ]; then
    print_color "red" "Error: Could not find S3 bucket name in CloudFormation stack outputs."
    exit 1
fi

# 7. Deploy frontend assets to S3 and invalidate CloudFront cache
print_color "blue" "
[Step 7/7] Deploying frontend assets to S3 and invalidating CloudFront cache..."

# Upload frontend configuration
aws s3 cp "$FRONTEND_DIR/build/config.js" "s3://$S3_BUCKET_NAME/config.js" --content-type "application/javascript"
print_color "green" "- Frontend configuration uploaded to S3."

# Sync frontend assets to S3
aws s3 sync "$FRONTEND_DIR/build/" "s3://$S3_BUCKET_NAME/" --delete
print_color "green" "- Frontend assets synced to S3."

# Invalidate CloudFront cache
if [ -n "$CLOUDFRONT_ID" ]; then
    aws cloudfront create-invalidation --distribution-id "$CLOUDFRONT_ID" --paths "/*" >/dev/null
    print_color "green" "- CloudFront cache invalidation created."
fi

# 8. Populate DynamoDB with model data
print_color "blue" "
[Bonus] Populating DynamoDB with model data..."
if [ -f "scripts/populate-models.py" ]; then
    python3 scripts/populate-models.py
    print_color "green" "- Model data populated in DynamoDB."
else
    print_color "yellow" "⚠️  populate-models.py not found. Skipping model data population."
fi

print_color "blue" "
--------------------------------------------------"
print_color "green" "🚀 Deployment Successful! 🚀"
print_color "blue" "--------------------------------------------------"
print_color "green" "You can now access your application at:"
print_color "blue" "$CLOUDFRONT_URL"
print_color "blue" "
📋 Next Steps:"
print_color "blue" "1. Create admin user:"
print_color "blue" "   aws cognito-idp admin-create-user \\"
print_color "blue" "     --user-pool-id $USER_POOL_ID \\"
print_color "blue" "     --username admin \\"
print_color "blue" "     --user-attributes Name=email,Value=your-email@example.com \\"
print_color "blue" "     --temporary-password TempPass123! \\"
print_color "blue" "     --message-action SUPPRESS"
print_color "blue" "
2. Generate frontend configuration:"
print_color "blue" "   sh scripts/generate-config.sh"
print_color "blue" "
3. Access the application and start deploying models!"

# --- Main Deployment Process ---

print_color "blue" "Starting AWS Ollama Platform Deployment..."
print_color "blue" "AWS Account: $AWS_ACCOUNT_ID"
print_color "blue" "Region: $AWS_REGION"
print_color "blue" "Environment: $ENVIRONMENT"

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    print_color "red" "❌ Docker is not running. Please start Docker and try again."
    exit 1
fi

# Check for S3 bucket for CloudFormation artifacts
print_color "blue" "
Checking for S3 bucket for CloudFormation artifacts: $S3_BUCKET_FOR_ARTIFACTS"
if aws s3 ls "s3://$S3_BUCKET_FOR_ARTIFACTS" 2>&1 | grep -q 'NoSuchBucket'; then
    print_color "blue" "Creating S3 bucket for CloudFormation artifacts: $S3_BUCKET_FOR_ARTIFACTS"
    aws s3 mb "s3://$S3_BUCKET_FOR_ARTIFACTS" --region $AWS_REGION
    print_color "green" "S3 bucket $S3_BUCKET_FOR_ARTIFACTS created."
else
    print_color "green" "S3 bucket $S3_BUCKET_FOR_ARTIFACTS already exists."
fi

# 1. Build and push Docker images
print_color "blue" "
[Step 1/6] Building and pushing Docker images..."
build_and_push_images

# 2. Build the React frontend application
print_color "blue" "
[Step 2/6] Building React frontend application..."
if [ -d "$FRONTEND_DIR/node_modules" ]; then
    print_color "green" "node_modules already exists, skipping installation."
else
    (cd "$FRONTEND_DIR" && npm install)
fi
(cd "$FRONTEND_DIR" && npm run build)
print_color "green" "Frontend build complete."

# 3. Package the CloudFormation templates
print_color "blue" "
[Step 3/6] Packaging CloudFormation templates..."
aws cloudformation package \
  --template-file "$MAIN_TEMPLATE" \
  --s3-bucket "$S3_BUCKET_FOR_ARTIFACTS" \
  --output-template-file "$PACKAGED_TEMPLATE"
print_color "green" "CloudFormation templates packaged to $PACKAGED_TEMPLATE."

# 4. Deploy the CloudFormation stack
print_color "blue" "
[Step 4/6] Deploying AWS infrastructure with CloudFormation..."

# スタックの存在確認
STACK_EXISTS=false
if aws cloudformation describe-stacks --stack-name "$STACK_NAME" >/dev/null 2>&1; then
    STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].StackStatus" --output text)
    print_color "blue" "Stack $STACK_NAME exists with status: $STACK_STATUS"
    
    case "$STACK_STATUS" in
        "CREATE_IN_PROGRESS")
            print_color "blue" "Stack is currently being created. Waiting for completion..."
            aws cloudformation wait stack-create-complete --stack-name "$STACK_NAME"
            print_color "green" "Stack creation completed."
            STACK_EXISTS=true
            ;;
        "UPDATE_IN_PROGRESS")
            print_color "blue" "Stack is currently being updated. Waiting for completion..."
            aws cloudformation wait stack-update-complete --stack-name "$STACK_NAME"
            print_color "green" "Stack update completed."
            STACK_EXISTS=true
            ;;
        "ROLLBACK_COMPLETE")
            print_color "red" "Stack is in ROLLBACK_COMPLETE state. Deleting it..."
            aws cloudformation delete-stack --stack-name "$STACK_NAME"
            aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME"
            print_color "green" "Stack deleted successfully."
            STACK_EXISTS=false
            ;;
        "CREATE_COMPLETE"|"UPDATE_COMPLETE")
            print_color "green" "Stack is ready for updates."
            STACK_EXISTS=true
            ;;
        "DELETE_IN_PROGRESS")
            print_color "blue" "Stack is being deleted. Waiting for completion..."
            aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME"
            print_color "green" "Stack deletion completed."
            STACK_EXISTS=false
            ;;
        *)
            print_color "red" "Stack is in unexpected state: $STACK_STATUS"
            print_color "red" "Please check the CloudFormation console and resolve manually."
            exit 1
            ;;
    esac
else
    print_color "blue" "Stack $STACK_NAME does not exist. Will create new stack."
    STACK_EXISTS=false
fi

# スタックの作成または更新
if [ "$STACK_EXISTS" = true ]; then
    print_color "blue" "Updating existing stack..."
    if aws cloudformation deploy \
      --template-file "$PACKAGED_TEMPLATE" \
      --stack-name "$STACK_NAME" \
      --parameter-overrides file://"$PARAMETERS_FILE" \
      --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
      --no-fail-on-empty-changeset; then
        print_color "green" "Stack update completed successfully."
    else
        print_color "red" "Stack update failed."
        exit 1
    fi
else
    print_color "blue" "Creating new stack..."
    if aws cloudformation create-stack \
      --stack-name "$STACK_NAME" \
      --template-body file://"$PACKAGED_TEMPLATE" \
      --parameters file://"$PARAMETERS_FILE" \
      --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM; then
        
        print_color "blue" "Waiting for stack creation to complete..."
        if aws cloudformation wait stack-create-complete --stack-name "$STACK_NAME"; then
            print_color "green" "Stack creation completed successfully."
        else
            print_color "red" "Stack creation failed or timed out."
            print_color "red" "Check the CloudFormation console for details."
            exit 1
        fi
    else
        print_color "red" "Failed to initiate stack creation."
        exit 1
    fi
fi

print_color "green" "CloudFormation stack deployment complete."

# 5. Get stack outputs
print_color "blue" "
[Step 5/6] Retrieving S3 bucket and CloudFront distribution from stack outputs..."

# 出力値を安全に取得する関数
get_stack_output() {
    local output_key=$1
    aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --query "Stacks[0].Outputs[?OutputKey=='$output_key'].OutputValue" \
        --output text 2>/dev/null || echo ""
}

S3_BUCKET_NAME=$(get_stack_output "S3BucketName")
CLOUDFRONT_ID=$(get_stack_output "CloudFrontDistributionId")
CLOUDFRONT_URL=$(get_stack_output "CloudFrontURL")
USER_POOL_ID=$(get_stack_output "UserPoolId")
USER_POOL_CLIENT_ID=$(get_stack_output "UserPoolClientId")

print_color "green" "- User Pool ID: $USER_POOL_ID"
print_color "green" "- User Pool Client ID: $USER_POOL_CLIENT_ID"
print_color "green" "- S3 Bucket Name: $S3_BUCKET_NAME"
print_color "green" "- CloudFront ID: $CLOUDFRONT_ID"

# Check if we got the required outputs
if [ -z "$S3_BUCKET_NAME" ]; then
    print_color "red" "Error: Could not find S3 bucket name in CloudFormation stack outputs."
    exit 1
fi

# 6. Deploy frontend assets to S3 and invalidate CloudFront cache
print_color "blue" "
[Step 6/6] Deploying frontend assets to S3 and invalidating CloudFront cache..."

# Upload frontend configuration
aws s3 cp "$FRONTEND_DIR/build/config.js" "s3://$S3_BUCKET_NAME/config.js" --content-type "application/javascript"
print_color "green" "- Frontend configuration uploaded to S3."

# Sync frontend assets to S3
aws s3 sync "$FRONTEND_DIR/build/" "s3://$S3_BUCKET_NAME/" --delete
print_color "green" "- Frontend assets synced to S3."

# Invalidate CloudFront cache
if [ -n "$CLOUDFRONT_ID" ]; then
    aws cloudfront create-invalidation --distribution-id "$CLOUDFRONT_ID" --paths "/*" >/dev/null
    print_color "green" "- CloudFront cache invalidation created."
fi

# 7. Populate DynamoDB with model data
print_color "blue" "
[Step 7/7] Populating DynamoDB with model data..."
if [ -f "scripts/populate-models.py" ]; then
    python3 scripts/populate-models.py
    print_color "green" "- Model data populated in DynamoDB."
else
    print_color "yellow" "⚠️  populate-models.py not found. Skipping model data population."
fi

print_color "blue" "
--------------------------------------------------"
print_color "green" "🚀 Deployment Successful! 🚀"
print_color "blue" "--------------------------------------------------"
print_color "green" "You can now access your application at:"
print_color "blue" "$CLOUDFRONT_URL"
print_color "blue" "
📋 Next Steps:"
print_color "blue" "1. Create admin user:"
print_color "blue" "   aws cognito-idp admin-create-user \\"
print_color "blue" "     --user-pool-id $USER_POOL_ID \\"
print_color "blue" "     --username admin \\"
print_color "blue" "     --user-attributes Name=email,Value=your-email@example.com \\"
print_color "blue" "     --temporary-password TempPass123! \\"
print_color "blue" "     --message-action SUPPRESS"
print_color "blue" "
2. Generate frontend configuration:"
print_color "blue" "   sh scripts/generate-config.sh"
print_color "blue" "
3. Access the application and start deploying models!"

# --- Script Start ---

print_color "blue" "Starting AWS Ollama Platform Deployment..."

# Check if stack is in ROLLBACK_COMPLETE state and delete it
STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].StackStatus" --output text 2>/dev/null || echo "NOT_EXISTS")
if [ "$STACK_STATUS" == "ROLLBACK_COMPLETE" ]; then
    print_color "red" "Stack $STACK_NAME is in ROLLBACK_COMPLETE state. Deleting it before proceeding..."
    aws cloudformation delete-stack --stack-name "$STACK_NAME"
    aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME"
    print_color "green" "Stack $STACK_NAME deleted successfully."
fi

# Create S3 bucket for CloudFormation artifacts if it doesn't exist
print_color "blue" "
Checking for S3 bucket for CloudFormation artifacts: $S3_BUCKET_FOR_ARTIFACTS"
if ! aws s3 ls "s3://$S3_BUCKET_FOR_ARTIFACTS" 2>&1 | grep -q 'NoSuchBucket'; then
    print_color "green" "S3 bucket $S3_BUCKET_FOR_ARTIFACTS already exists."
else
    print_color "blue" "Creating S3 bucket for CloudFormation artifacts: $S3_BUCKET_FOR_ARTIFACTS"
    aws s3 mb "s3://$S3_BUCKET_FOR_ARTIFACTS" --region $AWS_REGION
    print_color "green" "S3 bucket $S3_BUCKET_FOR_ARTIFACTS created."
fi

# 1. Build the React frontend application
print_color "blue" "
[Step 1/5] Building React frontend application..."
if [ -d "$FRONTEND_DIR/node_modules" ]; then
    print_color "green" "node_modules already exists, skipping installation."
else
    (cd "$FRONTEND_DIR" && npm install)
fi
(cd "$FRONTEND_DIR" && npm run build)
print_color "green" "Frontend build complete."

# 2. Package the CloudFormation templates
print_color "blue" "
[Step 2/5] Packaging CloudFormation templates..."
aws cloudformation package \
  --template-file "$MAIN_TEMPLATE" \
  --s3-bucket "$S3_BUCKET_FOR_ARTIFACTS" \
  --output-template-file "$PACKAGED_TEMPLATE"
print_color "green" "CloudFormation templates packaged to $PACKAGED_TEMPLATE."

# 3. Deploy the CloudFormation stack
print_color "blue" "
[Step 3/5] Deploying AWS infrastructure with CloudFormation..."

# スタックの存在確認
STACK_EXISTS=false
if aws cloudformation describe-stacks --stack-name "$STACK_NAME" >/dev/null 2>&1; then
    STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].StackStatus" --output text)
    print_color "blue" "Stack $STACK_NAME exists with status: $STACK_STATUS"
    
    case "$STACK_STATUS" in
        "CREATE_IN_PROGRESS")
            print_color "blue" "Stack is currently being created. Waiting for completion..."
            aws cloudformation wait stack-create-complete --stack-name "$STACK_NAME"
            print_color "green" "Stack creation completed."
            STACK_EXISTS=true
            ;;
        "UPDATE_IN_PROGRESS")
            print_color "blue" "Stack is currently being updated. Waiting for completion..."
            aws cloudformation wait stack-update-complete --stack-name "$STACK_NAME"
            print_color "green" "Stack update completed."
            STACK_EXISTS=true
            ;;
        "ROLLBACK_COMPLETE")
            print_color "red" "Stack is in ROLLBACK_COMPLETE state. Deleting it..."
            aws cloudformation delete-stack --stack-name "$STACK_NAME"
            aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME"
            print_color "green" "Stack deleted successfully."
            STACK_EXISTS=false
            ;;
        "CREATE_COMPLETE"|"UPDATE_COMPLETE")
            print_color "green" "Stack is ready for updates."
            STACK_EXISTS=true
            ;;
        "DELETE_IN_PROGRESS")
            print_color "blue" "Stack is being deleted. Waiting for completion..."
            aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME"
            print_color "green" "Stack deletion completed."
            STACK_EXISTS=false
            ;;
        *)
            print_color "red" "Stack is in unexpected state: $STACK_STATUS"
            print_color "red" "Please check the CloudFormation console and resolve manually."
            exit 1
            ;;
    esac
else
    print_color "blue" "Stack $STACK_NAME does not exist. Will create new stack."
    STACK_EXISTS=false
fi

# スタックの作成または更新
if [ "$STACK_EXISTS" = true ]; then
    print_color "blue" "Updating existing stack..."
    if aws cloudformation deploy \
      --template-file "$PACKAGED_TEMPLATE" \
      --stack-name "$STACK_NAME" \
      --parameter-overrides file://"$PARAMETERS_FILE" \
      --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
      --no-fail-on-empty-changeset; then
        print_color "green" "Stack update completed successfully."
    else
        print_color "red" "Stack update failed."
        exit 1
    fi
else
    print_color "blue" "Creating new stack..."
    if aws cloudformation create-stack \
      --stack-name "$STACK_NAME" \
      --template-body file://"$PACKAGED_TEMPLATE" \
      --parameters file://"$PARAMETERS_FILE" \
      --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM; then
        
        print_color "blue" "Waiting for stack creation to complete..."
        if aws cloudformation wait stack-create-complete --stack-name "$STACK_NAME"; then
            print_color "green" "Stack creation completed successfully."
        else
            print_color "red" "Stack creation failed or timed out."
            print_color "red" "Check the CloudFormation console for details."
            exit 1
        fi
    else
        print_color "red" "Failed to initiate stack creation."
        exit 1
    fi
fi

print_color "green" "CloudFormation stack deployment complete."

# 4. Get stack outputs
print_color "blue" "
[Step 4/5] Retrieving S3 bucket and CloudFront distribution from stack outputs..."

# 出力値を安全に取得する関数
get_stack_output() {
    local output_key=$1
    aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --query "Stacks[0].Outputs[?OutputKey=='$output_key'].OutputValue" \
        --output text 2>/dev/null || echo ""
}

S3_BUCKET_NAME=$(get_stack_output "S3BucketName")
CLOUDFRONT_ID=$(get_stack_output "CloudFrontDistributionId")
CLOUDFRONT_URL=$(get_stack_output "CloudFrontURL")
USER_POOL_ID=$(get_stack_output "UserPoolId")
USER_POOL_CLIENT_ID=$(get_stack_output "UserPoolClientId")

print_color "green" "- User Pool ID: $USER_POOL_ID"
print_color "green" "- User Pool Client ID: $USER_POOL_CLIENT_ID"

if [ -z "$S3_BUCKET_NAME" ]; then
    print_color "red" "Error: Could not find S3 bucket name in CloudFormation stack outputs."
    exit 1
fi
print_color "green" "- S3 Bucket Name: $S3_BUCKET_NAME"
print_color "green" "- CloudFront ID: $CLOUDFRONT_ID"

# 5. Deploy frontend to S3 and invalidate CloudFront
print_color "blue" "
[Step 5/5] Deploying frontend assets to S3 and invalidating CloudFront cache..."

# Create a configuration file for the frontend
CONFIG_JS="window.AWS_OLLAMA_CONFIG = { region: '$AWS_REGION', userPoolId: '$USER_POOL_ID', userPoolWebClientId: '$USER_POOL_CLIENT_ID' };"
echo "$CONFIG_JS" > "$FRONTEND_DIR/build/config.js"
aws s3 cp "$FRONTEND_DIR/build/config.js" "s3://$S3_BUCKET_NAME/config.js"
print_color "green" "- Frontend configuration uploaded to S3."

# Sync the build directory with the S3 bucket
aws s3 sync "$FRONTEND_DIR/build/" "s3://$S3_BUCKET_NAME/" --delete
print_color "green" "- Frontend assets synced to S3."

# Invalidate the CloudFront cache
if [ -z "$CLOUDFRONT_ID" ]; then
    print_color "red" "Warning: Could not find CloudFront distribution ID. Cache invalidation skipped."
else
    aws cloudfront create-invalidation --distribution-id "$CLOUDFRONT_ID" --paths "/*" > /dev/null
    print_color "green" "- CloudFront cache invalidation created."
fi

print_color "blue" "
--------------------------------------------------"
print_color "green" "🚀 Deployment Successful! 🚀"
print_color "blue" "--------------------------------------------------"
print_color "green" "You can now access your application at:"
print_color "blue" "$CLOUDFRONT_URL"