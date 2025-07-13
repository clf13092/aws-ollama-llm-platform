#!/bin/bash

# AWS Ollama Platform Cleanup Script
# This script safely removes the CloudFormation stack and associated resources

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
    echo "  -s, --stack-name NAME      Stack name (default: aws-ollama-platform)"
    echo "  -e, --environment ENV      Environment name (default: production)"
    echo "  --backup-data              Create backups before deletion"
    echo "  --force                    Skip confirmation prompts"
    echo "  --preserve-data            Keep DynamoDB tables and S3 buckets"
    echo "  --dry-run                  Show what would be deleted without deleting"
    echo "  -h, --help                 Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                         # Interactive cleanup with confirmations"
    echo "  $0 --backup-data --force   # Backup data and cleanup without prompts"
    echo "  $0 --preserve-data         # Delete infrastructure but keep data"
    echo "  $0 --dry-run               # Show what would be deleted"
}

# Function to check if stack exists
check_stack_exists() {
    if aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to get stack resources
get_stack_resources() {
    aws cloudformation describe-stack-resources \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'StackResources[*].[ResourceType,PhysicalResourceId,LogicalResourceId]' \
        --output table 2>/dev/null || echo "No resources found"
}

# Function to backup DynamoDB tables
backup_dynamodb_tables() {
    print_info "Creating DynamoDB table backups..."
    
    local tables=(
        "${ENVIRONMENT}-ollama-models"
        "${ENVIRONMENT}-ollama-instances"
        "${ENVIRONMENT}-ollama-users"
        "${ENVIRONMENT}-ollama-usage-logs"
    )
    
    for table in "${tables[@]}"; do
        if aws dynamodb describe-table --table-name "$table" --region "$REGION" &>/dev/null; then
            local backup_name="${table}-backup-$(date +%Y%m%d%H%M%S)"
            print_info "Creating backup for table: $table"
            
            aws dynamodb create-backup \
                --table-name "$table" \
                --backup-name "$backup_name" \
                --region "$REGION" &>/dev/null && \
            print_success "Backup created: $backup_name" || \
            print_error "Failed to create backup for $table"
        else
            print_warning "Table $table not found, skipping backup"
        fi
    done
}

# Function to backup S3 buckets
backup_s3_buckets() {
    print_info "Creating S3 bucket backups..."
    
    # Get S3 bucket names from stack outputs
    local frontend_bucket=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`S3BucketName`].OutputValue' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$frontend_bucket" ] && [ "$frontend_bucket" != "None" ]; then
        local backup_bucket="${frontend_bucket}-backup-$(date +%Y%m%d%H%M%S)"
        print_info "Creating backup bucket: $backup_bucket"
        
        aws s3 mb "s3://$backup_bucket" --region "$REGION" && \
        aws s3 sync "s3://$frontend_bucket" "s3://$backup_bucket" && \
        print_success "S3 backup created: $backup_bucket" || \
        print_error "Failed to create S3 backup"
    else
        print_warning "Frontend S3 bucket not found, skipping backup"
    fi
}

# Function to empty S3 buckets before deletion
empty_s3_buckets() {
    print_info "Emptying S3 buckets..."
    
    # Get all S3 buckets created by the stack
    local buckets=$(aws cloudformation describe-stack-resources \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'StackResources[?ResourceType==`AWS::S3::Bucket`].PhysicalResourceId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$buckets" ]; then
        for bucket in $buckets; do
            if aws s3 ls "s3://$bucket" &>/dev/null; then
                print_info "Emptying S3 bucket: $bucket"
                aws s3 rm "s3://$bucket" --recursive && \
                print_success "Emptied bucket: $bucket" || \
                print_error "Failed to empty bucket: $bucket"
            fi
        done
    else
        print_warning "No S3 buckets found in stack"
    fi
}

# Function to terminate ECS services
terminate_ecs_services() {
    print_info "Terminating ECS services..."
    
    # Get ECS cluster name
    local cluster_name=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`ECSClusterName`].OutputValue' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$cluster_name" ] && [ "$cluster_name" != "None" ]; then
        # List and stop all services in the cluster
        local services=$(aws ecs list-services \
            --cluster "$cluster_name" \
            --region "$REGION" \
            --query 'serviceArns[*]' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$services" ]; then
            for service in $services; do
                local service_name=$(basename "$service")
                print_info "Stopping ECS service: $service_name"
                
                aws ecs update-service \
                    --cluster "$cluster_name" \
                    --service "$service_name" \
                    --desired-count 0 \
                    --region "$REGION" &>/dev/null && \
                print_success "Stopped service: $service_name" || \
                print_error "Failed to stop service: $service_name"
            done
            
            # Wait for services to stop
            print_info "Waiting for services to stop..."
            sleep 30
        else
            print_info "No ECS services found"
        fi
    else
        print_warning "ECS cluster not found"
    fi
}

# Function to delete CloudWatch log groups
delete_log_groups() {
    print_info "Deleting CloudWatch log groups..."
    
    local log_groups=$(aws logs describe-log-groups \
        --log-group-name-prefix "/aws/lambda/${ENVIRONMENT}-ollama" \
        --region "$REGION" \
        --query 'logGroups[*].logGroupName' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$log_groups" ]; then
        for log_group in $log_groups; do
            print_info "Deleting log group: $log_group"
            aws logs delete-log-group \
                --log-group-name "$log_group" \
                --region "$REGION" && \
            print_success "Deleted log group: $log_group" || \
            print_error "Failed to delete log group: $log_group"
        done
    fi
    
    # Delete ECS log groups
    local ecs_log_groups=$(aws logs describe-log-groups \
        --log-group-name-prefix "/ecs/${ENVIRONMENT}-ollama" \
        --region "$REGION" \
        --query 'logGroups[*].logGroupName' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$ecs_log_groups" ]; then
        for log_group in $ecs_log_groups; do
            print_info "Deleting ECS log group: $log_group"
            aws logs delete-log-group \
                --log-group-name "$log_group" \
                --region "$REGION" && \
            print_success "Deleted ECS log group: $log_group" || \
            print_error "Failed to delete ECS log group: $log_group"
        done
    fi
}

# Function to delete the CloudFormation stack
delete_stack() {
    print_info "Deleting CloudFormation stack: $STACK_NAME"
    
    if [ "$DRY_RUN" = "true" ]; then
        print_info "DRY RUN - Would delete stack: $STACK_NAME"
        return 0
    fi
    
    aws cloudformation delete-stack \
        --stack-name "$STACK_NAME" \
        --region "$REGION" && \
    print_success "Stack deletion initiated" || \
    print_error "Failed to initiate stack deletion"
    
    # Wait for stack deletion to complete
    print_info "Waiting for stack deletion to complete..."
    if aws cloudformation wait stack-delete-complete \
        --stack-name "$STACK_NAME" \
        --region "$REGION"; then
        print_success "Stack deleted successfully"
    else
        print_error "Stack deletion failed or timed out"
        show_stack_events
        return 1
    fi
}

# Function to show stack events
show_stack_events() {
    print_info "Recent stack events:"
    aws cloudformation describe-stack-events \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --max-items 10 \
        --query 'StackEvents[*].[Timestamp,ResourceStatus,ResourceType,LogicalResourceId,ResourceStatusReason]' \
        --output table 2>/dev/null || echo "No events found"
}

# Function to confirm deletion
confirm_deletion() {
    if [ "$FORCE" = "true" ]; then
        return 0
    fi
    
    echo ""
    print_warning "⚠️  WARNING: This will permanently delete the following resources:"
    echo ""
    echo "Stack Resources:"
    get_stack_resources
    echo ""
    
    if [ "$PRESERVE_DATA" != "true" ]; then
        print_warning "🗑️  DATA DELETION: All data in DynamoDB tables and S3 buckets will be permanently lost!"
    fi
    
    echo ""
    read -p "Are you sure you want to proceed? (type 'DELETE' to confirm): " confirmation
    
    if [ "$confirmation" != "DELETE" ]; then
        print_info "Cleanup cancelled by user"
        exit 0
    fi
}

# Parse command line arguments
BACKUP_DATA=false
FORCE=false
PRESERVE_DATA=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -s|--stack-name)
            STACK_NAME="$2"
            shift 2
            ;;
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --backup-data)
            BACKUP_DATA=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --preserve-data)
            PRESERVE_DATA=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
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

# Main execution
echo "=========================================="
echo "AWS Ollama Platform Cleanup Script"
echo "=========================================="
echo "Stack Name: $STACK_NAME"
echo "Region: $REGION"
echo "Environment: $ENVIRONMENT"
echo "Backup Data: $BACKUP_DATA"
echo "Preserve Data: $PRESERVE_DATA"
echo "Dry Run: $DRY_RUN"
echo "=========================================="

# Check if stack exists
if ! check_stack_exists; then
    print_error "Stack '$STACK_NAME' not found in region '$REGION'"
    exit 1
fi

# Show confirmation dialog
confirm_deletion

# Create backups if requested
if [ "$BACKUP_DATA" = "true" ]; then
    backup_dynamodb_tables
    backup_s3_buckets
fi

# Cleanup steps
print_info "Starting cleanup process..."

# Step 1: Terminate ECS services
terminate_ecs_services

# Step 2: Empty S3 buckets (required for deletion)
if [ "$PRESERVE_DATA" != "true" ]; then
    empty_s3_buckets
fi

# Step 3: Delete CloudWatch log groups
delete_log_groups

# Step 4: Delete the CloudFormation stack
delete_stack

# Step 5: Manual cleanup reminders
if [ "$DRY_RUN" != "true" ]; then
    echo ""
    print_success "=== CLEANUP COMPLETED ==="
    echo ""
    
    if [ "$BACKUP_DATA" = "true" ]; then
        print_info "📦 Backups have been created and are preserved"
    fi
    
    if [ "$PRESERVE_DATA" = "true" ]; then
        print_info "💾 Data has been preserved as requested"
    fi
    
    print_info "🧹 Manual cleanup recommendations:"
    echo "  1. Review any remaining CloudWatch alarms"
    echo "  2. Check for orphaned EBS volumes"
    echo "  3. Verify NAT Gateway deletion to avoid charges"
    echo "  4. Review Route 53 hosted zone if domain was used"
    echo ""
    print_success "AWS Ollama Platform has been successfully removed!"
fi