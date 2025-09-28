# Review Platform Deployments

This repository contains the complete infrastructure and deployment setup for the Review Platform application, including both frontend and backend deployment configurations.

## 🏗️ Architecture Overview

The deployment architecture consists of:

- **Frontend**: AWS S3 + CloudFront for React application hosting
- **Backend**: AWS EC2 with MongoDB for API services
- **Infrastructure**: Terraform for Infrastructure as Code
- **CI/CD**: GitHub Actions for automated deployments
- **Security**: IAM roles and policies for secure deployments
- **Management**: AWS Systems Manager for secure instance access

## 📁 Directory Structure

```
deployment/
├── terraform/                 # Infrastructure as Code
│   ├── main.tf               # Main Terraform configuration
│   ├── variables.tf          # Input variables
│   ├── outputs.tf            # Output values
│   └── scripts/              # Infrastructure scripts
├── pipelines/                # CI/CD Pipelines
│   └── .github/workflows/
│       ├── infrastructure.yml     # Infrastructure deployment
│       ├── deploy-frontend.yml    # Frontend deployment
│       └── deploy-backend.yml     # Backend deployment
├── scripts/                  # Deployment scripts
│   ├── setup-infrastructure.sh   # Infrastructure setup
│   ├── deploy-frontend.sh        # Frontend deployment
│   ├── configure-ssm.sh          # AWS Systems Manager setup
│   ├── verify-ssm-status.sh      # SSM status verification
│   └── test-backend-apis.sh      # Backend API testing
├── config/                   # Configuration files
└── docs/                     # Documentation
```

## 🚀 Quick Start

### Prerequisites

1. **AWS CLI** configured with appropriate credentials
2. **Terraform** >= 1.0 installed
3. **Node.js** >= 18 for building the frontend
4. **GitHub repository** for CI/CD integration

### 1. Infrastructure Setup

1. **Configure Terraform variables:**
   ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your specific values
   ```

2. **Deploy infrastructure:**
   ```bash
   cd ../scripts
   ./setup-infrastructure.sh
   ```

### 2. GitHub Repository Setup

Add the following secrets to your GitHub repository at `Settings > Secrets and variables > Actions`:

```
AWS_ROLE_ARN=<github_actions_role_arn>
S3_BUCKET_NAME=<s3_bucket_name>
CLOUDFRONT_DISTRIBUTION_ID=<cloudfront_distribution_id>
CLOUDFRONT_DOMAIN_NAME=<cloudfront_domain_name>
BACKEND_API_URL=http://43.205.211.216:5000
ENVIRONMENT=dev
```

### 3. Application Deployment

**Frontend Deployment:**
```bash
cd scripts
./deploy-frontend.sh --environment dev --api-url http://43.205.211.216:5000
```

**Backend Deployment:**
- Backend is deployed on EC2 instance via Terraform
- API endpoints available at: https://44.194.207.22
- Secure access via AWS Systems Manager Session Manager

**AWS Systems Manager Setup:**
```bash
cd scripts
./configure-ssm.sh
./verify-ssm-status.sh
```

## 🔧 Configuration

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `aws_region` | AWS region for resources | `us-east-1` | No |
| `environment` | Environment name | `dev` | No |
| `project_name` | Project name | `review-platform` | No |
| `bucket_name` | S3 bucket name (must be unique) | - | Yes |
| `github_repo` | GitHub repository (owner/repo) | - | Yes |
| `backend_api_url` | Backend API URL | `http://43.205.211.216:5000` | No |

## 🔄 CI/CD Pipelines

### Infrastructure Pipeline
- Validates and deploys AWS infrastructure
- Manages Terraform state and resources

### Frontend Pipeline
- Builds React application
- Deploys to S3 and invalidates CloudFront

### Backend Pipeline
- Deploys Node.js API to EC2
- Manages MongoDB database setup

## 🔐 Security Considerations

- **IAM Roles**: Minimal permissions for GitHub Actions
- **S3 Access**: Restricted to CloudFront only
- **HTTPS**: Enforced for all traffic
- **API Security**: CORS and authentication configured

## 📊 Performance Optimization

- **CloudFront**: Global CDN for fast content delivery
- **Caching**: Optimized cache headers for static assets
- **Compression**: Gzip compression enabled
- **Database**: MongoDB with proper indexing

## 📞 Support

For issues or questions:
1. Check the troubleshooting documentation
2. Review GitHub Actions logs for deployment issues
3. Verify AWS CloudWatch logs for runtime issues
4. Ensure all prerequisites are properly configured

## 🚀 Next Steps

After successful deployment:
1. Configure custom domain (optional)
2. Set up SSL certificate with ACM (optional)
3. Configure monitoring and alerting
4. Set up staging environment
5. Implement blue-green deployment strategy
