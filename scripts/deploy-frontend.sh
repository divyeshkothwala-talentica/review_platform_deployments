#!/bin/bash

# Frontend Deployment Script
# This script builds and deploys the React frontend to S3 and CloudFront

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
FRONTEND_DIR="$(dirname "$0")/../../fe_review_platform"
TERRAFORM_DIR="$(dirname "$0")/../terraform"
BUILD_DIR="$FRONTEND_DIR/build"

# Default values
ENVIRONMENT="dev"
BACKEND_API_URL="http://43.205.211.216:5000"

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

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -e, --environment    Environment (dev/staging/prod) [default: dev]"
    echo "  -a, --api-url        Backend API URL [default: http://43.205.211.216:5000]"
    echo "  -h, --help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Deploy with defaults"
    echo "  $0 -e prod -a https://api.example.com # Deploy to prod with custom API"
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -a|--api-url)
                BACKEND_API_URL="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Node.js is installed
    if ! command -v node &> /dev/null; then
        log_error "Node.js is not installed. Please install Node.js first."
        exit 1
    fi
    
    # Check if npm is installed
    if ! command -v npm &> /dev/null; then
        log_error "npm is not installed. Please install npm first."
        exit 1
    fi
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check if frontend directory exists
    if [[ ! -d "$FRONTEND_DIR" ]]; then
        log_error "Frontend directory not found: $FRONTEND_DIR"
        exit 1
    fi
    
    # Check if Terraform outputs are available
    if [[ ! -f "$TERRAFORM_DIR/terraform.tfstate" ]]; then
        log_error "Terraform state not found. Please run infrastructure setup first."
        exit 1
    fi
    
    log_success "All prerequisites met"
}

get_terraform_outputs() {
    log_info "Getting infrastructure information..."
    
    cd "$TERRAFORM_DIR"
    
    S3_BUCKET=$(terraform output -raw s3_bucket_name 2>/dev/null)
    CLOUDFRONT_DISTRIBUTION_ID=$(terraform output -raw cloudfront_distribution_id 2>/dev/null)
    CLOUDFRONT_DOMAIN=$(terraform output -raw cloudfront_domain_name 2>/dev/null)
    
    if [[ -z "$S3_BUCKET" || -z "$CLOUDFRONT_DISTRIBUTION_ID" ]]; then
        log_error "Could not get Terraform outputs. Please ensure infrastructure is deployed."
        exit 1
    fi
    
    log_success "Infrastructure information retrieved"
    log_info "S3 Bucket: $S3_BUCKET"
    log_info "CloudFront Distribution: $CLOUDFRONT_DISTRIBUTION_ID"
    log_info "Website URL: https://$CLOUDFRONT_DOMAIN"
}

install_dependencies() {
    log_info "Installing dependencies..."
    
    cd "$FRONTEND_DIR"
    
    if [[ -f "package-lock.json" ]]; then
        npm ci
    else
        npm install
    fi
    
    log_success "Dependencies installed"
}

create_env_file() {
    log_info "Creating environment configuration..."
    
    cd "$FRONTEND_DIR"
    
    cat > .env.production << EOF
REACT_APP_API_URL=$BACKEND_API_URL
REACT_APP_ENVIRONMENT=$ENVIRONMENT
GENERATE_SOURCEMAP=false
EOF
    
    log_success "Environment file created"
    log_info "Backend API URL: $BACKEND_API_URL"
    log_info "Environment: $ENVIRONMENT"
}

run_tests() {
    log_info "Running tests..."
    
    cd "$FRONTEND_DIR"
    
    # Run tests in CI mode
    npm test -- --coverage --watchAll=false --passWithNoTests
    
    if [[ $? -eq 0 ]]; then
        log_success "All tests passed"
    else
        log_error "Tests failed"
        exit 1
    fi
}

build_application() {
    log_info "Building application..."
    
    cd "$FRONTEND_DIR"
    
    # Clean previous build
    if [[ -d "$BUILD_DIR" ]]; then
        rm -rf "$BUILD_DIR"
    fi
    
    # Build the application
    npm run build
    
    if [[ $? -eq 0 && -d "$BUILD_DIR" ]]; then
        log_success "Application built successfully"
        log_info "Build size: $(du -sh "$BUILD_DIR" | cut -f1)"
    else
        log_error "Build failed"
        exit 1
    fi
}

deploy_to_s3() {
    log_info "Deploying to S3..."
    
    cd "$FRONTEND_DIR"
    
    # Sync static assets with long cache
    aws s3 sync "$BUILD_DIR/" "s3://$S3_BUCKET/" \
        --delete \
        --cache-control "public,max-age=31536000,immutable" \
        --exclude "*.html" \
        --exclude "service-worker.js" \
        --exclude "manifest.json"
    
    # Sync HTML files with no cache
    aws s3 sync "$BUILD_DIR/" "s3://$S3_BUCKET/" \
        --cache-control "public,max-age=0,must-revalidate" \
        --include "*.html" \
        --include "service-worker.js" \
        --include "manifest.json"
    
    if [[ $? -eq 0 ]]; then
        log_success "Files uploaded to S3"
    else
        log_error "S3 deployment failed"
        exit 1
    fi
}

invalidate_cloudfront() {
    log_info "Invalidating CloudFront cache..."
    
    INVALIDATION_ID=$(aws cloudfront create-invalidation \
        --distribution-id "$CLOUDFRONT_DISTRIBUTION_ID" \
        --paths "/*" \
        --query 'Invalidation.Id' \
        --output text)
    
    if [[ $? -eq 0 ]]; then
        log_success "CloudFront invalidation created: $INVALIDATION_ID"
        log_info "Cache invalidation may take 5-15 minutes to complete"
    else
        log_error "CloudFront invalidation failed"
        exit 1
    fi
}

show_deployment_info() {
    log_success "Frontend deployment completed successfully!"
    echo
    log_info "Deployment Information:"
    echo "  🌐 Website URL: https://$CLOUDFRONT_DOMAIN"
    echo "  🔗 Backend API: $BACKEND_API_URL"
    echo "  📦 S3 Bucket: $S3_BUCKET"
    echo "  🚀 Environment: $ENVIRONMENT"
    echo
    log_info "The application will be available at the website URL once CloudFront cache is updated."
}

main() {
    log_info "Starting frontend deployment..."
    echo
    
    parse_arguments "$@"
    check_prerequisites
    get_terraform_outputs
    install_dependencies
    create_env_file
    run_tests
    build_application
    deploy_to_s3
    invalidate_cloudfront
    show_deployment_info
}

# Run main function
main "$@"
