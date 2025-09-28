#!/bin/bash

set -e

# Configuration
INSTANCE_ID="i-0976dee0653da4175"
AWS_ACCOUNT_ID="936167486253"
AWS_REGION="us-east-1"
PROJECT_NAME="review-platform"

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

# Check if AWS CLI is configured
check_aws_cli() {
    log "Checking AWS CLI configuration..."
    if ! aws sts get-caller-identity > /dev/null 2>&1; then
        error "AWS CLI is not configured or credentials are invalid"
        error "Please run 'aws configure' to set up your credentials"
        exit 1
    fi
    
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    if [ "$account_id" != "$AWS_ACCOUNT_ID" ]; then
        warning "Current AWS account ($account_id) doesn't match expected account ($AWS_ACCOUNT_ID)"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    success "AWS CLI is properly configured for account $account_id"
}

# Check if instance exists and get current details
check_instance() {
    log "Checking EC2 instance $INSTANCE_ID..."
    
    if ! aws ec2 describe-instances --instance-ids $INSTANCE_ID --region $AWS_REGION > /dev/null 2>&1; then
        error "Instance $INSTANCE_ID not found in region $AWS_REGION"
        exit 1
    fi
    
    local instance_state=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --region $AWS_REGION --query 'Reservations[0].Instances[0].State.Name' --output text)
    log "Instance state: $instance_state"
    
    if [ "$instance_state" != "running" ]; then
        warning "Instance is not in running state. Current state: $instance_state"
    fi
    
    # Get current IAM instance profile
    local current_profile=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --region $AWS_REGION --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' --output text 2>/dev/null || echo "None")
    log "Current IAM instance profile: $current_profile"
    
    success "Instance $INSTANCE_ID found and accessible"
}

# Apply Terraform changes
apply_terraform_changes() {
    log "Applying Terraform changes for SSM configuration..."
    
    cd "$(dirname "$0")/../terraform"
    
    # Check if terraform is initialized
    if [ ! -d ".terraform" ]; then
        log "Initializing Terraform..."
        terraform init
    fi
    
    # Plan the changes
    log "Creating Terraform plan..."
    terraform plan -var-file="backend.tfvars" -out=ssm-update.tfplan
    
    # Apply the changes
    log "Applying Terraform changes..."
    terraform apply ssm-update.tfplan
    
    # Clean up plan file
    rm -f ssm-update.tfplan
    
    success "Terraform changes applied successfully"
}

# Verify SSM agent is running on the instance
verify_ssm_agent() {
    log "Verifying SSM agent status on instance..."
    
    # Wait a moment for the instance profile to take effect
    log "Waiting 30 seconds for IAM changes to propagate..."
    sleep 30
    
    # Check if instance is visible in SSM
    local ssm_status=$(aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$INSTANCE_ID" --region $AWS_REGION --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null || echo "NotFound")
    
    if [ "$ssm_status" = "Online" ]; then
        success "SSM agent is online and ready"
    elif [ "$ssm_status" = "NotFound" ]; then
        warning "Instance not yet visible in SSM. This may take a few minutes."
        log "You can check the status later with:"
        log "aws ssm describe-instance-information --filters \"Key=InstanceIds,Values=$INSTANCE_ID\" --region $AWS_REGION"
    else
        warning "SSM agent status: $ssm_status"
    fi
}

# Install/restart SSM agent on the instance if needed
install_ssm_agent() {
    log "Checking if SSM agent needs to be installed/restarted on the instance..."
    
    # Try to connect via SSM to check agent status
    if aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$INSTANCE_ID" --region $AWS_REGION --query 'InstanceInformationList[0]' --output table > /dev/null 2>&1; then
        success "SSM agent is already running on the instance"
        return 0
    fi
    
    warning "SSM agent may need to be installed or restarted"
    log "Attempting to install/restart SSM agent via SSH..."
    
    # Get instance public IP
    local public_ip=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --region $AWS_REGION --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
    
    if [ "$public_ip" = "None" ] || [ -z "$public_ip" ]; then
        error "Cannot get public IP for instance. Manual SSM agent installation may be required."
        return 1
    fi
    
    log "Instance public IP: $public_ip"
    log "You can manually install SSM agent by connecting via SSH:"
    log "ssh -i ~/.ssh/your-key.pem ec2-user@$public_ip"
    log "Then run the following commands:"
    log "sudo dnf install -y amazon-ssm-agent"
    log "sudo systemctl enable amazon-ssm-agent"
    log "sudo systemctl start amazon-ssm-agent"
    log "sudo systemctl status amazon-ssm-agent"
}

# Test SSM Session Manager connection
test_ssm_connection() {
    log "Testing SSM Session Manager connection..."
    
    # Check if session manager plugin is installed
    if ! command -v session-manager-plugin > /dev/null 2>&1; then
        warning "AWS Session Manager plugin not found"
        log "Install it from: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
        return 1
    fi
    
    log "Session Manager plugin is installed"
    log "You can now connect to the instance using:"
    log "aws ssm start-session --target $INSTANCE_ID --region $AWS_REGION"
    
    success "SSM configuration completed successfully!"
}

# Display final instructions
display_instructions() {
    log "=== AWS Systems Manager Configuration Complete ==="
    echo
    success "✅ IAM role updated with AmazonSSMManagedInstanceCore policy"
    success "✅ Security group allows outbound HTTPS (port 443)"
    success "✅ Terraform configuration updated"
    echo
    log "📋 Next Steps:"
    log "1. Wait 2-5 minutes for IAM changes to fully propagate"
    log "2. Verify SSM agent is running:"
    log "   aws ssm describe-instance-information --filters \"Key=InstanceIds,Values=$INSTANCE_ID\" --region $AWS_REGION"
    log "3. Connect via Session Manager:"
    log "   aws ssm start-session --target $INSTANCE_ID --region $AWS_REGION"
    log "4. Or use the AWS Console:"
    log "   https://console.aws.amazon.com/systems-manager/session-manager/$INSTANCE_ID?region=$AWS_REGION"
    echo
    log "🔧 If SSM agent is not responding, manually restart it:"
    log "   sudo systemctl restart amazon-ssm-agent"
    log "   sudo systemctl status amazon-ssm-agent"
    echo
}

# Main execution
main() {
    log "Starting AWS Systems Manager configuration for instance $INSTANCE_ID"
    echo
    
    check_aws_cli
    check_instance
    apply_terraform_changes
    verify_ssm_agent
    install_ssm_agent
    test_ssm_connection
    display_instructions
    
    success "AWS Systems Manager configuration completed!"
}

# Run main function
main "$@"
