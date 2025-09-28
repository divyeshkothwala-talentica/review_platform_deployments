#!/bin/bash

# SSH Key Generation Script for Backend Deployment
# This script generates SSH keys required for EC2 access

set -e

# Configuration
KEY_NAME="review-platform-backend"
KEY_DIR="$HOME/.ssh"
KEY_FILE="$KEY_DIR/$KEY_NAME"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check if SSH directory exists
check_ssh_directory() {
    if [ ! -d "$KEY_DIR" ]; then
        log "Creating SSH directory: $KEY_DIR"
        mkdir -p "$KEY_DIR"
        chmod 700 "$KEY_DIR"
    fi
}

# Function to generate SSH keys
generate_ssh_keys() {
    log "Generating SSH key pair for backend deployment..."
    
    # Check if keys already exist
    if [ -f "$KEY_FILE" ] || [ -f "$KEY_FILE.pub" ]; then
        warning "SSH keys already exist:"
        [ -f "$KEY_FILE" ] && echo "  Private key: $KEY_FILE"
        [ -f "$KEY_FILE.pub" ] && echo "  Public key: $KEY_FILE.pub"
        
        read -p "Do you want to overwrite existing keys? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Keeping existing keys"
            return 0
        fi
        
        log "Removing existing keys..."
        rm -f "$KEY_FILE" "$KEY_FILE.pub"
    fi
    
    # Generate new SSH key pair
    log "Creating new SSH key pair..."
    if ssh-keygen -t rsa -b 4096 -f "$KEY_FILE" -N "" -C "review-platform-backend-$(date +%Y%m%d)"; then
        success "SSH key pair generated successfully"
    else
        error "Failed to generate SSH key pair"
        exit 1
    fi
    
    # Set proper permissions
    chmod 600 "$KEY_FILE"
    chmod 644 "$KEY_FILE.pub"
    
    success "SSH keys created:"
    echo "  Private key: $KEY_FILE"
    echo "  Public key: $KEY_FILE.pub"
}

# Function to display key information
display_key_info() {
    log "SSH Key Information:"
    echo
    echo "Private Key File: $KEY_FILE"
    echo "Public Key File: $KEY_FILE.pub"
    echo
    
    if [ -f "$KEY_FILE.pub" ]; then
        echo "Public Key Content:"
        echo "==================="
        cat "$KEY_FILE.pub"
        echo
        echo "==================="
        echo
    fi
    
    echo "Key Fingerprint:"
    if [ -f "$KEY_FILE" ]; then
        ssh-keygen -lf "$KEY_FILE"
    fi
    echo
}

# Function to create Terraform variables
create_terraform_vars() {
    local tfvars_file="$1"
    
    if [ -z "$tfvars_file" ]; then
        tfvars_file="../backend.tfvars"
    fi
    
    log "Creating Terraform variables file: $tfvars_file"
    
    if [ ! -f "$KEY_FILE" ] || [ ! -f "$KEY_FILE.pub" ]; then
        error "SSH keys not found. Please generate keys first."
        return 1
    fi
    
    # Read public and private keys
    local public_key=$(cat "$KEY_FILE.pub")
    local private_key=$(cat "$KEY_FILE" | sed ':a;N;$!ba;s/\n/\\n/g')
    
    # Create or update tfvars file
    cat > "$tfvars_file" << EOF
# AWS Configuration
aws_region = "us-east-1"
environment = "production"
project_name = "review-platform"

# Network Configuration
vpc_cidr = "10.0.0.0/16"
public_subnet_cidr = "10.0.1.0/24"

# EC2 Configuration
instance_type = "t3.medium"

# SSH Key Configuration (Generated: $(date))
public_key = "$public_key"
private_key = "$private_key"

# Application Configuration
openai_api_key = "your-openai-api-key-here"
cors_origin = "https://d157ilt95f9lq6.cloudfront.net"
jwt_secret = "your-super-secret-jwt-key-change-in-production-2024-$(openssl rand -hex 16)"
mongo_db_name = "book_review_platform"

# GitHub Configuration (Update with your repository)
github_repo = "your-username/your-repo"

# Optional Configuration
domain_name = ""
certificate_arn = ""
enable_monitoring = true
backup_retention_days = 7
allowed_ssh_cidr = ["0.0.0.0/0"]
node_version = "18"
npm_version = "latest"
EOF

    success "Terraform variables file created: $tfvars_file"
    warning "Please update the 'github_repo' variable with your actual repository"
}

# Function to show usage instructions
show_usage_instructions() {
    echo
    success "SSH Keys Generated Successfully!"
    echo
    echo "Next Steps:"
    echo "==========="
    echo
    echo "1. Update Terraform Variables:"
    echo "   - Edit the generated tfvars file with your specific values"
    echo "   - Update the 'github_repo' variable with your repository"
    echo
    echo "2. Deploy Infrastructure:"
    echo "   cd /Users/divyeshk/learning/deployment/terraform"
    echo "   terraform init"
    echo "   terraform plan -var-file=backend.tfvars"
    echo "   terraform apply -var-file=backend.tfvars"
    echo
    echo "3. SSH to EC2 Instance (after deployment):"
    echo "   ssh -i $KEY_FILE ec2-user@<instance-ip>"
    echo
    echo "4. Migrate Database:"
    echo "   ./scripts/mongodb-migration.sh migrate <instance-ip> $KEY_FILE"
    echo
    echo "Security Notes:"
    echo "==============="
    echo "- Keep your private key secure and never share it"
    echo "- The private key is stored at: $KEY_FILE"
    echo "- Set proper file permissions (already done)"
    echo "- Consider using SSH agent for key management"
    echo
}

# Function to validate keys
validate_keys() {
    log "Validating SSH keys..."
    
    if [ ! -f "$KEY_FILE" ]; then
        error "Private key not found: $KEY_FILE"
        return 1
    fi
    
    if [ ! -f "$KEY_FILE.pub" ]; then
        error "Public key not found: $KEY_FILE.pub"
        return 1
    fi
    
    # Check key format
    if ssh-keygen -lf "$KEY_FILE" > /dev/null 2>&1; then
        success "Private key is valid"
    else
        error "Private key is invalid or corrupted"
        return 1
    fi
    
    if ssh-keygen -lf "$KEY_FILE.pub" > /dev/null 2>&1; then
        success "Public key is valid"
    else
        error "Public key is invalid or corrupted"
        return 1
    fi
    
    # Check permissions
    local private_perms=$(stat -c "%a" "$KEY_FILE" 2>/dev/null || stat -f "%A" "$KEY_FILE" 2>/dev/null)
    if [ "$private_perms" != "600" ]; then
        warning "Private key permissions are $private_perms, should be 600"
        chmod 600 "$KEY_FILE"
        success "Fixed private key permissions"
    fi
    
    success "SSH keys validation passed"
}

# Function to show help
show_help() {
    echo "SSH Key Generation Script for Backend Deployment"
    echo
    echo "Usage:"
    echo "  $0 [command] [options]"
    echo
    echo "Commands:"
    echo "  generate                    - Generate new SSH key pair"
    echo "  info                        - Display key information"
    echo "  validate                    - Validate existing keys"
    echo "  tfvars [file]              - Create Terraform variables file"
    echo "  help                        - Show this help"
    echo
    echo "Examples:"
    echo "  $0 generate                 - Generate SSH keys"
    echo "  $0 info                     - Show key information"
    echo "  $0 tfvars backend.tfvars    - Create Terraform variables"
    echo
    echo "Files:"
    echo "  Private Key: $KEY_FILE"
    echo "  Public Key: $KEY_FILE.pub"
}

# Main script logic
main() {
    case "${1:-generate}" in
        "generate")
            check_ssh_directory
            generate_ssh_keys
            validate_keys
            display_key_info
            create_terraform_vars
            show_usage_instructions
            ;;
        "info")
            display_key_info
            ;;
        "validate")
            validate_keys
            ;;
        "tfvars")
            create_terraform_vars "$2"
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            error "Unknown command: $1"
            echo
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
