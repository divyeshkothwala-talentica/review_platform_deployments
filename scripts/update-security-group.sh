#!/bin/bash

set -e

echo "🔧 Updating Security Group Configuration..."

cd "$(dirname "$0")/../terraform"

# Check if terraform is initialized
if [ ! -d ".terraform" ]; then
    echo "Initializing Terraform..."
    terraform init
fi

# Plan the changes
echo "Planning Terraform changes..."
terraform plan -var-file="backend.tfvars" -out=security-group-update.tfplan

# Apply the changes
echo "Applying security group updates..."
terraform apply security-group-update.tfplan

# Clean up plan file
rm -f security-group-update.tfplan

echo "✅ Security group updated successfully!"
echo "The security group now allows:"
echo "- Port 5000 (Backend API)"
echo "- Port 80 (HTTP web access)"
echo "- Port 22 (SSH access)"
echo "- Port 5001 (Alternative API port)"
