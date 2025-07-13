#!/bin/bash

# AWS Ollama Platform Deployment Script
# This script deploys the entire CloudFormation stack for the AWS Ollama Platform

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
STACK_NAME="aws-ollama-platform"
REGION="us-east-1"
ENVIRONMENT="production"

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -r, --region REGION        AWS region (default: us-east-1)"
    echo "  -e, --environment ENV      Environment name (default: production)"
    echo "  -s, --stack-name NAME      Stack name (default: aws-ollama-platform)"
    echo "  -p, --parameters FILE      Parameters file (default: parameters.json)"
    echo "  -d, --domain DOMAIN        Domain name for the platform"
    echo "  -a, --admin-email EMAIL    Admin email address"
    echo "  --dry-run                  Show what would be deployed without deploying"
    echo "  --update                   Update existing stack"
    echo "  --validate-only            Only validate templates"
    echo "  -h, --help                 Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --domain ollama.example.com --admin-email admin@example.com"
    echo "  $0 --region us-west-2 --environment staging --update"
    echo "  $0 --validate-only"
}

# Function to check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials are not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        print_error "jq is not installed. Please install it first."
        exit 1
    fi
    
    # Check if CloudFormation templates exist
    if [ ! -f "$PROJECT_ROOT/cloudformation/main.yaml" ]; then
        print_error "CloudFormation templates not found. Please ensure you're in the correct directory."
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Function to validate CloudFormation templates
validate_templates() {
    print_info "Validating CloudFormation templates..."
    
    local templates=(
        "cloudformation/main.yaml"
        "cloudformation/network/vpc.yaml"
        "cloudformation/auth/cognito.yaml"
        "cloudformation/storage/dynamodb.yaml"
        "cloudformation/security/iam.yaml"
    )
    
    for template in "${templates[@]}"; do
        local template_path="$PROJECT_ROOT/$template"
        if [ -f "$template_path" ]; then
            print_info "Validating $template..."
            if aws cloudformation validate-template --template-body "file://$template_path" --region "$REGION" > /dev/null; then
                print_success "$template is valid"
            else
                print_error "$template validation failed"
                exit 1
            fi
        else
            print_warning "$template not found, skipping validation"
        fi
    done
    
    print_success "All templates validated successfully"
}

# Function to upload templates to S3 (for nested stacks)
upload_templates() {
    print_info "Uploading CloudFormation templates to S3..."
    
    # Create a unique bucket name
    local bucket_name="aws-ollama-cf-templates-$(date +%s)-$RANDOM"
    local bucket_exists=false
    
    # Check if bucket already exists (from previous runs)
    if aws s3 ls "s3://$bucket_name" 2>/dev/null; then
        bucket_exists=true
        print_info "Using existing S3 bucket: $bucket_name"
    else
        print_info "Creating S3 bucket: $bucket_name"
        aws s3 mb "s3://$bucket_name" --region "$REGION"
    fi
    
    # Upload templates
    aws s3 sync "$PROJECT_ROOT/cloudformation/" "s3://$bucket_name/" --exclude "main.yaml"
    
    # Update main.yaml with S3 URLs
    local temp_main="$PROJECT_ROOT/cloudformation/main-deployed.yaml"
    sed "s|'./|'https://s3.amazonaws.com/$bucket_name/|g" "$PROJECT_ROOT/cloudformation/main.yaml" > "$temp_main"
    
    echo "$bucket_name" > "$PROJECT_ROOT/.s3-bucket-name"
    echo "$temp_main"
}

# Function to create parameters file if it doesn't exist
create_parameters_file() {
    local params_file="$1"
    local domain="$2"
    local admin_email="$3"
    
    if [ ! -f "$params_file" ]; then
        print_info "Creating parameters file: $params_file"
        
        cat > "$params_file" << EOF
[
  {
    "ParameterKey": "Environment",
    "ParameterValue": "$ENVIRONMENT"
  },
  {
    "ParameterKey": "DomainName",
    "ParameterValue": "$domain"
  },
  {
    "ParameterKey": "AdminEmail",
    "ParameterValue": "$admin_email"
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
EOF
        print_success "Parameters file created: $params_file"
    fi
}

# Function to deploy the stack
deploy_stack() {
    local template_file="$1"
    local params_file="$2"
    local update_mode="$3"
    
    local deployment_command="aws cloudformation"
    
    if [ "$update_mode" = "true" ]; then
        deployment_command="$deployment_command update-stack"
        print_info "Updating CloudFormation stack: $STACK_NAME"
    else
        deployment_command="$deployment_command create-stack"
        print_info "Creating CloudFormation stack: $STACK_NAME"
    fi
    
    deployment_command="$deployment_command --stack-name $STACK_NAME"
    deployment_command="$deployment_command --template-body file://$template_file"
    deployment_command="$deployment_command --parameters file://$params_file"
    deployment_command="$deployment_command --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM"
    deployment_command="$deployment_command --region $REGION"
    deployment_command="$deployment_command --tags Key=Project,Value=aws-ollama-platform Key=Environment,Value=$ENVIRONMENT"
    
    if [ "$DRY_RUN" = "true" ]; then
        print_info "DRY RUN - Would execute:"
        echo "$deployment_command"
        return 0
    fi
    
    # Execute deployment
    if eval "$deployment_command"; then
        print_success "Stack deployment initiated successfully"
        
        # Wait for stack deployment to complete
        print_info "Waiting for stack deployment to complete..."
        local wait_command="aws cloudformation wait stack-"
        
        if [ "$update_mode" = "true" ]; then
            wait_command="${wait_command}update-complete"
        else
            wait_command="${wait_command}create-complete"
        fi
        
        wait_command="$wait_command --stack-name $STACK_NAME --region $REGION"
        
        if eval "$wait_command"; then
            print_success "Stack deployment completed successfully"
            show_stack_outputs
        else
            print_error "Stack deployment failed"
            show_stack_events
            exit 1
        fi
    else
        print_error "Stack deployment failed to initiate"
        exit 1
    fi
}

# Function to show stack outputs
show_stack_outputs() {
    print_info "Retrieving stack outputs..."
    
    local outputs=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs' \
        --output table 2>/dev/null || echo "[]")
    
    if [ "$outputs" != "[]" ]; then
        echo ""
        print_success "Stack Outputs:"
        echo "$outputs"
        
        # Get specific important outputs
        local cloudfront_url=$(aws cloudformation describe-stacks \
            --stack-name "$STACK_NAME" \
            --region "$REGION" \
            --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontURL`].OutputValue' \
            --output text 2>/dev/null || echo "Not available")
        
        local user_pool_id=$(aws cloudformation describe-stacks \
            --stack-name "$STACK_NAME" \
            --region "$REGION" \
            --query 'Stacks[0].Outputs[?OutputKey==`UserPoolId`].OutputValue' \
            --output text 2>/dev/null || echo "Not available")
        
        echo ""
        print_success "Quick Access Information:"
        echo "  Management Interface: $cloudfront_url"
        echo "  User Pool ID: $user_pool_id"
        echo ""
        
        # Show initial setup instructions
        show_post_deployment_instructions "$user_pool_id"
    fi
}

# Function to show stack events (for debugging)
show_stack_events() {
    print_info "Recent stack events:"
    aws cloudformation describe-stack-events \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --max-items 10 \
        --query 'StackEvents[*].[Timestamp,ResourceStatus,ResourceType,LogicalResourceId,ResourceStatusReason]' \
        --output table
}

# Function to show post-deployment instructions
show_post_deployment_instructions() {
    local user_pool_id="$1"
    
    echo ""
    print_success "=== POST-DEPLOYMENT SETUP ==="
    echo ""
    echo "1. Create your initial admin user:"
    echo "   aws cognito-idp admin-create-user \\"
    echo "     --user-pool-id $user_pool_id \\"
    echo "     --username admin \\"
    echo "     --user-attributes Name=email,Value=YOUR_ADMIN_EMAIL \\"
    echo "     --temporary-password TempPass123! \\"
    echo "     --message-action SUPPRESS \\"
    echo "     --region $REGION"
    echo ""
    echo "2. Access the management interface and login with:"
    echo "   - Username: admin"
    echo "   - Password: TempPass123! (change on first login)"
    echo ""
    echo "3. Start deploying your first Ollama model!"
    echo ""
    print_success "=== DEPLOYMENT COMPLETE ==="
}

# Function to cleanup temporary files
cleanup() {
    if [ -f "$PROJECT_ROOT/cloudformation/main-deployed.yaml" ]; then
        rm "$PROJECT_ROOT/cloudformation/main-deployed.yaml"
    fi
    
    # Optionally clean up S3 bucket (commented out for safety)
    # if [ -f "$PROJECT_ROOT/.s3-bucket-name" ]; then
    #     local bucket_name=$(cat "$PROJECT_ROOT/.s3-bucket-name")
    #     aws s3 rm "s3://$bucket_name" --recursive
    #     aws s3 rb "s3://$bucket_name"
    #     rm "$PROJECT_ROOT/.s3-bucket-name"
    # fi
}

# Parse command line arguments
PARAMETERS_FILE="$PROJECT_ROOT/parameters.json"
DOMAIN=""
ADMIN_EMAIL=""
DRY_RUN=false
UPDATE_MODE=false
VALIDATE_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -s|--stack-name)
            STACK_NAME="$2"
            shift 2
            ;;
        -p|--parameters)
            PARAMETERS_FILE="$2"
            shift 2
            ;;
        -d|--domain)
            DOMAIN="$2"
            shift 2
            ;;
        -a|--admin-email)
            ADMIN_EMAIL="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --update)
            UPDATE_MODE=true
            shift
            ;;
        --validate-only)
            VALIDATE_ONLY=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$DOMAIN" ] && [ "$VALIDATE_ONLY" != "true" ]; then
    print_error "Domain name is required. Use --domain option."
    show_usage
    exit 1
fi

if [ -z "$ADMIN_EMAIL" ] && [ "$VALIDATE_ONLY" != "true" ]; then
    print_error "Admin email is required. Use --admin-email option."
    show_usage
    exit 1
fi

# Main execution
echo "=========================================="
echo "AWS Ollama Platform Deployment Script"
echo "=========================================="
echo "Stack Name: $STACK_NAME"
echo "Region: $REGION"
echo "Environment: $ENVIRONMENT"
echo "Domain: $DOMAIN"
echo "Admin Email: $ADMIN_EMAIL"
echo "=========================================="

# Trap for cleanup
trap cleanup EXIT

# Execute steps
check_prerequisites

if [ "$VALIDATE_ONLY" = "true" ]; then
    validate_templates
    print_success "Template validation completed successfully"
    exit 0
fi

validate_templates
create_parameters_file "$PARAMETERS_FILE" "$DOMAIN" "$ADMIN_EMAIL"

# For now, use local templates (nested stack support can be added later)
deploy_stack "$PROJECT_ROOT/cloudformation/main.yaml" "$PARAMETERS_FILE" "$UPDATE_MODE"

print_success "Deployment process completed successfully!"