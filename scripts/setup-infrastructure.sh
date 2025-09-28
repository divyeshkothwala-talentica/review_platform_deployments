#!/bin/bash

# Frontend Infrastructure Setup Script
# This script sets up the AWS infrastructure for the frontend deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
TERRAFORM_DIR="$(dirname "$0")/../terraform"
REQUIRED_TOOLS=("terraform" "aws")

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    for tool in "${REQUIRED_TOOLS[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool is not installed. Please install it first."
            exit 1
        fi
    done
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    log_success "All prerequisites met"
}

setup_terraform_vars() {
    log_info "Setting up Terraform variables..."
    
    if [[ ! -f "$TERRAFORM_DIR/terraform.tfvars" ]]; then
        if [[ -f "$TERRAFORM_DIR/terraform.tfvars.example" ]]; then
            cp "$TERRAFORM_DIR/terraform.tfvars.example" "$TERRAFORM_DIR/terraform.tfvars"
            log_warning "Created terraform.tfvars from example. Please update the values before proceeding."
            log_info "Edit $TERRAFORM_DIR/terraform.tfvars with your specific values:"
            log_info "  - bucket_name: Must be globally unique"
            log_info "  - github_repo: Your GitHub repository (owner/repo-name)"
            log_info "  - environment: dev/staging/prod"
            echo
            read -p "Press Enter after updating terraform.tfvars to continue..."
        else
            log_error "terraform.tfvars.example not found"
            exit 1
        fi
    fi
}

validate_bucket_name() {
    local bucket_name
    bucket_name=$(grep "bucket_name" "$TERRAFORM_DIR/terraform.tfvars" | cut -d'"' -f2)
    
    if [[ -z "$bucket_name" || "$bucket_name" == "review-platform-frontend-dev-unique-suffix" ]]; then
        log_error "Please update the bucket_name in terraform.tfvars with a unique value"
        exit 1
    fi
    
    # Check if bucket already exists
    if aws s3 ls "s3://$bucket_name" &> /dev/null; then
        log_error "Bucket '$bucket_name' already exists. Please choose a different name."
        exit 1
    fi
    
    log_success "Bucket name '$bucket_name' is available"
}

init_terraform() {
    log_info "Initializing Terraform..."
    cd "$TERRAFORM_DIR"
    
    terraform init
    
    if [[ $? -eq 0 ]]; then
        log_success "Terraform initialized successfully"
    else
        log_error "Terraform initialization failed"
        exit 1
    fi
}

plan_terraform() {
    log_info "Creating Terraform plan..."
    cd "$TERRAFORM_DIR"
    
    terraform plan -out=tfplan
    
    if [[ $? -eq 0 ]]; then
        log_success "Terraform plan created successfully"
        echo
        log_info "Review the plan above. Do you want to apply these changes?"
        read -p "Type 'yes' to continue: " confirm
        
        if [[ "$confirm" != "yes" ]]; then
            log_info "Deployment cancelled by user"
            exit 0
        fi
    else
        log_error "Terraform plan failed"
        exit 1
    fi
}

apply_terraform() {
    log_info "Applying Terraform configuration..."
    cd "$TERRAFORM_DIR"
    
    terraform apply tfplan
    
    if [[ $? -eq 0 ]]; then
        log_success "Infrastructure deployed successfully!"
        echo
        log_info "Getting deployment information..."
        terraform output
    else
        log_error "Terraform apply failed"
        exit 1
    fi
}

setup_github_secrets() {
    log_info "Setting up GitHub repository secrets..."
    echo
    log_warning "Please add the following secrets to your GitHub repository:"
    echo
    
    cd "$TERRAFORM_DIR"
    
    echo "AWS_ROLE_ARN: $(terraform output -raw github_actions_role_arn)"
    echo "S3_BUCKET_NAME: $(terraform output -raw s3_bucket_name)"
    echo "CLOUDFRONT_DISTRIBUTION_ID: $(terraform output -raw cloudfront_distribution_id)"
    echo "CLOUDFRONT_DOMAIN_NAME: $(terraform output -raw cloudfront_domain_name)"
    echo "BACKEND_API_URL: $(terraform output -raw backend_api_url)"
    echo "ENVIRONMENT: $(grep environment terraform.tfvars | cut -d'"' -f2)"
    echo
    log_info "Go to: https://github.com/YOUR_USERNAME/YOUR_REPO/settings/secrets/actions"
}

main() {
    log_info "Starting frontend infrastructure setup..."
    echo
    
    check_prerequisites
    setup_terraform_vars
    validate_bucket_name
    init_terraform
    plan_terraform
    apply_terraform
    setup_github_secrets
    
    echo
    log_success "Frontend infrastructure setup completed!"
    log_info "Website URL: https://$(cd "$TERRAFORM_DIR" && terraform output -raw cloudfront_domain_name)"
}

# Run main function
main "$@"
