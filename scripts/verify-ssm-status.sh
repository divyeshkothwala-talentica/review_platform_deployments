#!/bin/bash

set -e

# Configuration
INSTANCE_ID="i-0976dee0653da4175"
AWS_REGION="us-east-1"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Check AWS CLI configuration
check_aws_cli() {
    log "Checking AWS CLI configuration..."
    
    if ! command -v aws > /dev/null 2>&1; then
        error "AWS CLI is not installed"
        return 1
    fi
    
    if ! aws sts get-caller-identity > /dev/null 2>&1; then
        error "AWS CLI is not configured or credentials are invalid"
        return 1
    fi
    
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    success "AWS CLI configured for account: $account_id"
    return 0
}

# Check EC2 instance status
check_instance_status() {
    log "Checking EC2 instance status..."
    
    local instance_info=$(aws ec2 describe-instances \
        --instance-ids $INSTANCE_ID \
        --region $AWS_REGION \
        --query 'Reservations[0].Instances[0].[State.Name,IamInstanceProfile.Arn]' \
        --output text 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        error "Failed to get instance information"
        return 1
    fi
    
    local state=$(echo $instance_info | cut -f1)
    local iam_profile=$(echo $instance_info | cut -f2)
    
    if [ "$state" = "running" ]; then
        success "Instance is running"
    else
        warning "Instance state: $state"
    fi
    
    if [ "$iam_profile" != "None" ] && [ -n "$iam_profile" ]; then
        success "IAM instance profile attached: $(basename $iam_profile)"
    else
        error "No IAM instance profile attached"
        return 1
    fi
    
    return 0
}

# Check IAM role permissions
check_iam_permissions() {
    log "Checking IAM role permissions..."
    
    # Get instance profile name
    local profile_arn=$(aws ec2 describe-instances \
        --instance-ids $INSTANCE_ID \
        --region $AWS_REGION \
        --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' \
        --output text)
    
    if [ "$profile_arn" = "None" ] || [ -z "$profile_arn" ]; then
        error "No IAM instance profile found"
        return 1
    fi
    
    local profile_name=$(basename $profile_arn)
    local role_name=$(aws iam get-instance-profile \
        --instance-profile-name $profile_name \
        --query 'InstanceProfile.Roles[0].RoleName' \
        --output text)
    
    # Check if SSM policy is attached
    local ssm_policy_attached=$(aws iam list-attached-role-policies \
        --role-name $role_name \
        --query 'AttachedPolicies[?PolicyArn==`arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore`].PolicyName' \
        --output text)
    
    if [ -n "$ssm_policy_attached" ]; then
        success "AmazonSSMManagedInstanceCore policy is attached to role: $role_name"
    else
        error "AmazonSSMManagedInstanceCore policy is NOT attached to role: $role_name"
        return 1
    fi
    
    return 0
}

# Check security group rules
check_security_group() {
    log "Checking security group rules..."
    
    local sg_id=$(aws ec2 describe-instances \
        --instance-ids $INSTANCE_ID \
        --region $AWS_REGION \
        --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' \
        --output text)
    
    # Check for HTTPS outbound rule
    local https_rule=$(aws ec2 describe-security-groups \
        --group-ids $sg_id \
        --region $AWS_REGION \
        --query 'SecurityGroups[0].IpPermissionsEgress[?FromPort==`443` && ToPort==`443`]' \
        --output text)
    
    if [ -n "$https_rule" ]; then
        success "Security group allows outbound HTTPS (port 443)"
    else
        error "Security group does NOT allow outbound HTTPS (port 443)"
        return 1
    fi
    
    return 0
}

# Check SSM agent status
check_ssm_agent() {
    log "Checking SSM agent status..."
    
    local ssm_info=$(aws ssm describe-instance-information \
        --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
        --region $AWS_REGION \
        --query 'InstanceInformationList[0].[PingStatus,LastPingDateTime,AgentVersion]' \
        --output text 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$ssm_info" ] || [ "$ssm_info" = "None" ]; then
        error "Instance is not registered with SSM"
        warning "This may take a few minutes after initial configuration"
        return 1
    fi
    
    local ping_status=$(echo $ssm_info | cut -f1)
    local last_ping=$(echo $ssm_info | cut -f2)
    local agent_version=$(echo $ssm_info | cut -f3)
    
    if [ "$ping_status" = "Online" ]; then
        success "SSM agent is online"
        success "Last ping: $last_ping"
        success "Agent version: $agent_version"
    else
        warning "SSM agent status: $ping_status"
        return 1
    fi
    
    return 0
}

# Test Session Manager connectivity
test_session_manager() {
    log "Testing Session Manager connectivity..."
    
    if ! command -v session-manager-plugin > /dev/null 2>&1; then
        warning "Session Manager plugin not installed"
        log "Install from: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
        return 1
    fi
    
    success "Session Manager plugin is installed"
    
    # Test if we can start a session (this will fail but we can check the error)
    local test_result=$(aws ssm start-session \
        --target $INSTANCE_ID \
        --region $AWS_REGION \
        --dry-run 2>&1 || true)
    
    if echo "$test_result" | grep -q "DryRunOperation"; then
        success "Session Manager connectivity test passed"
    elif echo "$test_result" | grep -q "TargetNotConnected"; then
        error "Instance is not connected to SSM"
        return 1
    else
        warning "Session Manager test inconclusive"
        log "Try connecting manually: aws ssm start-session --target $INSTANCE_ID --region $AWS_REGION"
    fi
    
    return 0
}

# Display connection instructions
display_connection_info() {
    log "=== Connection Information ==="
    echo
    log "🔗 Connect via AWS CLI:"
    echo "   aws ssm start-session --target $INSTANCE_ID --region $AWS_REGION"
    echo
    log "🌐 Connect via AWS Console:"
    echo "   https://console.aws.amazon.com/systems-manager/session-manager/$INSTANCE_ID?region=$AWS_REGION"
    echo
    log "📋 Run commands remotely:"
    echo "   aws ssm send-command \\"
    echo "     --document-name \"AWS-RunShellScript\" \\"
    echo "     --parameters 'commands=[\"echo Hello World\"]' \\"
    echo "     --targets \"Key=instanceids,Values=$INSTANCE_ID\" \\"
    echo "     --region $AWS_REGION"
    echo
}

# Main execution
main() {
    echo "=== AWS Systems Manager Status Check ==="
    echo "Instance: $INSTANCE_ID"
    echo "Region: $AWS_REGION"
    echo

    local checks_passed=0
    local total_checks=6

    # Run all checks
    if check_aws_cli; then
        ((checks_passed++))
    fi

    if check_instance_status; then
        ((checks_passed++))
    fi

    if check_iam_permissions; then
        ((checks_passed++))
    fi

    if check_security_group; then
        ((checks_passed++))
    fi

    if check_ssm_agent; then
        ((checks_passed++))
    fi

    if test_session_manager; then
        ((checks_passed++))
    fi

    echo
    echo "=== Summary ==="
    if [ $checks_passed -eq $total_checks ]; then
        success "All checks passed ($checks_passed/$total_checks)"
        success "AWS Systems Manager is fully configured and ready!"
        display_connection_info
    else
        warning "Some checks failed ($checks_passed/$total_checks)"
        log "Review the errors above and run the configuration script if needed:"
        log "  ./configure-ssm.sh"
    fi
}

# Run main function
main "$@"
