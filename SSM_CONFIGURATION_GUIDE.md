# AWS Systems Manager Configuration Guide

This guide provides complete instructions for configuring AWS Systems Manager (SSM) for EC2 instance `i-0976dee0653da4175` in AWS account `936167486253`.

## 🎯 Overview

AWS Systems Manager provides secure, browser-based shell access to EC2 instances without requiring SSH keys or opening inbound ports. This configuration enables:

- **Session Manager**: Browser-based shell access
- **Run Command**: Execute commands remotely
- **Patch Manager**: Automated patching
- **Parameter Store**: Secure configuration management

## 📋 Prerequisites

Before starting, ensure you have:

1. **AWS CLI** installed and configured
2. **Terraform** >= 1.0 installed
3. **Session Manager Plugin** for AWS CLI (optional but recommended)
4. **Appropriate AWS permissions** for EC2, IAM, and SSM

### Install Session Manager Plugin

```bash
# macOS
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac/sessionmanager-bundle.zip" -o "sessionmanager-bundle.zip"
unzip sessionmanager-bundle.zip
sudo ./sessionmanager-bundle/install -i /usr/local/sessionmanagerplugin -b /usr/local/bin/session-manager-plugin

# Linux
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm" -o "session-manager-plugin.rpm"
sudo yum install -y session-manager-plugin.rpm

# Windows
# Download and install from: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html
```

## 🚀 Quick Setup

### Option 1: Automated Setup (Recommended)

Run the automated configuration script:

```bash
cd deployment/scripts
./configure-ssm.sh
```

This script will:
1. ✅ Verify AWS CLI configuration
2. ✅ Check EC2 instance status
3. ✅ Apply Terraform changes
4. ✅ Verify SSM agent installation
5. ✅ Test connectivity

### Option 2: Manual Setup

If you prefer manual configuration, follow these steps:

#### Step 1: Apply Terraform Changes

```bash
cd deployment/terraform
terraform init
terraform plan
terraform apply
```

#### Step 2: Verify Configuration

```bash
# Check if instance is visible in SSM
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=i-0976dee0653da4175" \
  --region us-east-1

# Connect via Session Manager
aws ssm start-session \
  --target i-0976dee0653da4175 \
  --region us-east-1
```

## 🔧 Configuration Details

### IAM Role Configuration

The Terraform configuration adds the following to the existing EC2 IAM role:

```hcl
# Attach AWS Systems Manager managed policy to EC2 role
resource "aws_iam_role_policy_attachment" "backend_ec2_ssm_policy_attachment" {
  role       = aws_iam_role.backend_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
```

### Security Group Configuration

The security group already includes the required outbound HTTPS rule:

```hcl
# HTTPS outbound (required for SSM)
egress {
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  description = "HTTPS outbound"
}
```

### SSM Agent Installation

The user data script now includes SSM agent installation:

```bash
# Install and configure AWS Systems Manager Agent
dnf install -y amazon-ssm-agent
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent
```

## 🔍 Verification Steps

### 1. Check Instance Registration

```bash
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=i-0976dee0653da4175" \
  --region us-east-1 \
  --query 'InstanceInformationList[0].[InstanceId,PingStatus,LastPingDateTime]' \
  --output table
```

Expected output:
```
-----------------------------------------
|        DescribeInstanceInformation    |
+----------------+----------+-----------+
|  i-0976dee0653da4175  |  Online  |  2024-01-XX  |
+----------------+----------+-----------+
```

### 2. Test Session Manager Connection

```bash
# Connect via AWS CLI
aws ssm start-session \
  --target i-0976dee0653da4175 \
  --region us-east-1

# Or use AWS Console
# https://console.aws.amazon.com/systems-manager/session-manager/i-0976dee0653da4175?region=us-east-1
```

### 3. Verify SSM Agent Status on Instance

Once connected via Session Manager:

```bash
# Check SSM agent status
sudo systemctl status amazon-ssm-agent

# Check SSM agent logs
sudo journalctl -u amazon-ssm-agent -f

# Restart SSM agent if needed
sudo systemctl restart amazon-ssm-agent
```

## 🐛 Troubleshooting

### Common Issues and Solutions

#### 1. Instance Not Visible in SSM

**Symptoms:**
- `aws ssm describe-instance-information` returns empty
- Cannot connect via Session Manager

**Solutions:**
```bash
# Check IAM instance profile
aws ec2 describe-instances \
  --instance-ids i-0976dee0653da4175 \
  --query 'Reservations[0].Instances[0].IamInstanceProfile'

# Verify IAM role has SSM policy
aws iam list-attached-role-policies \
  --role-name review-platform-backend-ec2-role

# Check SSM agent status on instance (via SSH)
ssh -i ~/.ssh/your-key.pem ec2-user@<PUBLIC_IP>
sudo systemctl status amazon-ssm-agent
```

#### 2. SSM Agent Not Running

**Symptoms:**
- Instance visible but ping status is "Connection Lost"
- Session Manager fails to connect

**Solutions:**
```bash
# Connect via SSH and restart SSM agent
ssh -i ~/.ssh/your-key.pem ec2-user@<PUBLIC_IP>
sudo systemctl restart amazon-ssm-agent
sudo systemctl enable amazon-ssm-agent

# Check agent logs
sudo journalctl -u amazon-ssm-agent -n 50
```

#### 3. Permission Denied Errors

**Symptoms:**
- "User is not authorized to perform: ssm:StartSession"

**Solutions:**
```bash
# Check your AWS user/role permissions
aws sts get-caller-identity

# Ensure your user has SSM permissions
# Required policies: AmazonSSMFullAccess or custom policy with:
# - ssm:StartSession
# - ssm:TerminateSession
# - ssm:ResumeSession
```

#### 4. Network Connectivity Issues

**Symptoms:**
- SSM agent cannot reach AWS endpoints

**Solutions:**
```bash
# Verify outbound HTTPS connectivity from instance
curl -I https://ssm.us-east-1.amazonaws.com
curl -I https://ssmmessages.us-east-1.amazonaws.com
curl -I https://ec2messages.us-east-1.amazonaws.com

# Check security group rules
aws ec2 describe-security-groups \
  --group-ids <SECURITY_GROUP_ID> \
  --query 'SecurityGroups[0].EgressRules'
```

### Debug Commands

```bash
# Check instance metadata
curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/

# Check SSM agent configuration
sudo cat /etc/amazon/ssm/amazon-ssm-agent.json

# Test SSM connectivity
sudo /usr/bin/amazon-ssm-agent -register -code "activation-code" -id "activation-id" -region "us-east-1"
```

## 📊 Monitoring and Maintenance

### CloudWatch Logs

SSM agent logs are automatically sent to CloudWatch:

```bash
# View SSM agent logs
aws logs describe-log-groups --log-group-name-prefix "/aws/amazoncloudwatch-agent"

# Stream logs
aws logs tail /aws/amazoncloudwatch-agent/i-0976dee0653da4175 --follow
```

### Regular Maintenance

```bash
# Update SSM agent (run monthly)
sudo yum update amazon-ssm-agent

# Check for available patches
aws ssm describe-available-patches \
  --filters "Key=PRODUCT,Values=AmazonLinux2023"

# Run patch scan
aws ssm send-command \
  --document-name "AWS-RunPatchBaseline" \
  --parameters "Operation=Scan" \
  --targets "Key=instanceids,Values=i-0976dee0653da4175"
```

## 🔐 Security Best Practices

### 1. Least Privilege Access

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ssm:StartSession"
      ],
      "Resource": [
        "arn:aws:ec2:us-east-1:936167486253:instance/i-0976dee0653da4175"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "ssm:TerminateSession",
        "ssm:ResumeSession"
      ],
      "Resource": [
        "arn:aws:ssm:*:*:session/${aws:username}-*"
      ]
    }
  ]
}
```

### 2. Session Logging

Enable session logging to S3 or CloudWatch:

```bash
# Create session preferences
aws ssm put-document \
  --name "SSM-SessionManagerRunShell" \
  --document-type "Session" \
  --document-format JSON \
  --content file://session-preferences.json
```

### 3. Network Isolation

For enhanced security, consider using VPC endpoints:

```hcl
# SSM VPC Endpoint
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.backend_vpc.id
  service_name        = "com.amazonaws.us-east-1.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.backend_public_subnet.id]
  security_group_ids  = [aws_security_group.vpc_endpoint_sg.id]
}
```

## 📞 Support and Resources

### AWS Documentation
- [Session Manager User Guide](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
- [SSM Agent Installation](https://docs.aws.amazon.com/systems-manager/latest/userguide/ssm-agent.html)
- [Troubleshooting SSM](https://docs.aws.amazon.com/systems-manager/latest/userguide/troubleshooting-remote-commands.html)

### Quick Reference Commands

```bash
# Connect to instance
aws ssm start-session --target i-0976dee0653da4175 --region us-east-1

# Check instance status
aws ssm describe-instance-information --filters "Key=InstanceIds,Values=i-0976dee0653da4175" --region us-east-1

# Run command on instance
aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["echo Hello World"]' \
  --targets "Key=instanceids,Values=i-0976dee0653da4175" \
  --region us-east-1

# Get command output
aws ssm get-command-invocation \
  --command-id <COMMAND_ID> \
  --instance-id i-0976dee0653da4175 \
  --region us-east-1
```

---

## ✅ Configuration Summary

After running this configuration, you will have:

- ✅ **IAM Role**: Updated with AmazonSSMManagedInstanceCore policy
- ✅ **Security Group**: Allows outbound HTTPS (port 443)
- ✅ **SSM Agent**: Installed and running on EC2 instance
- ✅ **Session Manager**: Ready for browser-based access
- ✅ **Monitoring**: CloudWatch integration enabled

**🎉 You can now securely access your EC2 instance without SSH keys or open inbound ports!**

### Next Steps
1. Test Session Manager connection
2. Set up session logging (optional)
3. Configure automated patching (optional)
4. Implement least-privilege IAM policies (recommended)
