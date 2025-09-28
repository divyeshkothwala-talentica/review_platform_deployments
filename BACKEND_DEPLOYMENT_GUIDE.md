# Backend Deployment Guide

This guide provides step-by-step instructions for deploying the Book Review Platform backend to AWS using Terraform and GitHub Actions.

## 📋 Prerequisites

### Required Tools
- **Terraform** >= 1.6.0
- **AWS CLI** >= 2.0
- **Node.js** >= 18.0
- **Git**
- **SSH client**

### Required Accounts & Access
- AWS Account with programmatic access
- GitHub repository with Actions enabled
- OpenAI API key for recommendations

## 🚀 Quick Start

### 1. Generate SSH Keys

```bash
cd /Users/divyeshk/learning/deployment/terraform/scripts
chmod +x generate-ssh-keys.sh
./generate-ssh-keys.sh
```

This will:
- Generate SSH key pair for EC2 access
- Create `backend.tfvars` with your keys
- Display usage instructions

### 2. Configure GitHub Secrets

Add the following secrets to your GitHub repository:

```
AWS_ROLE_ARN=arn:aws:iam::ACCOUNT:role/github-actions-role
TF_STATE_BUCKET=your-terraform-state-bucket
SSH_PUBLIC_KEY=<content of ~/.ssh/review-platform-backend.pub>
SSH_PRIVATE_KEY=<content of ~/.ssh/review-platform-backend>
OPENAI_API_KEY=your-openai-api-key-here
JWT_SECRET=your-super-secret-jwt-key-change-in-production-2024
```

### 3. Deploy Infrastructure

#### Option A: Using GitHub Actions (Recommended)
1. Go to your repository's Actions tab
2. Run "Backend Infrastructure Deployment" workflow
3. Select "apply" action and "production" environment
4. Wait for deployment to complete

#### Option B: Manual Deployment
```bash
cd /Users/divyeshk/learning/deployment/terraform

# Initialize Terraform
terraform init

# Review the plan
terraform plan -var-file=backend.tfvars

# Apply the infrastructure
terraform apply -var-file=backend.tfvars
```

### 4. Deploy Application Code

#### Using GitHub Actions (Recommended)
1. Run "Backend Application Deployment" workflow
2. Enable "Run comprehensive API tests after deployment"
3. Optionally enable "Run database migration"

#### Manual Deployment
```bash
# Get the EC2 IP from Terraform output
EC2_IP=$(terraform output -raw backend_public_ip)

# Build and deploy (from backend directory)
cd /Users/divyeshk/learning/be-review-platform/backend
npm run build
tar -czf backend-deployment.tar.gz dist/ package.json package-lock.json

# Upload to EC2
scp -i ~/.ssh/review-platform-backend backend-deployment.tar.gz ec2-user@$EC2_IP:/tmp/

# Deploy on EC2
ssh -i ~/.ssh/review-platform-backend ec2-user@$EC2_IP "sudo /opt/backend-app/deploy.sh"
```

### 5. Migrate Database

```bash
cd /Users/divyeshk/learning/deployment/terraform/scripts
chmod +x mongodb-migration.sh

# Migrate local database to EC2
./mongodb-migration.sh migrate $EC2_IP ~/.ssh/review-platform-backend
```

### 6. Test Deployment

```bash
cd /Users/divyeshk/learning/deployment/scripts
chmod +x test-backend-apis.sh

# Run comprehensive API tests
./test-backend-apis.sh http://$EC2_IP:5000
```

## 📁 Project Structure

```
deployment/
├── terraform/
│   ├── backend-main.tf           # Main infrastructure
│   ├── backend-variables.tf      # Variable definitions
│   ├── backend-outputs.tf        # Output values
│   ├── backend.tfvars.example    # Example variables
│   └── scripts/
│       ├── user_data.sh          # EC2 initialization
│       ├── generate-ssh-keys.sh  # SSH key generation
│       └── mongodb-migration.sh  # Database migration
├── pipelines/.github/workflows/
│   ├── infrastructure-backend.yml # Infrastructure pipeline
│   └── deploy-backend.yml        # Application deployment
└── scripts/
    └── test-backend-apis.sh      # API testing script
```

## 🏗️ Infrastructure Components

### AWS Resources Created
- **VPC** with public subnet and internet gateway
- **EC2 Instance** (t3.medium) with Amazon Linux 2023
- **Security Group** with ports 22, 5000, 5001, 27017
- **Elastic IP** for stable public access
- **S3 Bucket** for deployment artifacts
- **IAM Roles** for EC2 and GitHub Actions
- **CloudWatch Log Group** for application logs

### Software Installed
- **Node.js 18.x** with npm
- **MongoDB 7.0** with automatic startup
- **PM2** for process management
- **CloudWatch Agent** for monitoring
- **AWS CLI** for S3 access

## 🔧 Configuration

### Environment Variables
The application uses these environment variables:

```env
PORT=5000
NODE_ENV=production
API_VERSION=v1
CORS_ORIGIN=https://d157ilt95f9lq6.cloudfront.net
JWT_SECRET=your-jwt-secret
JWT_EXPIRES_IN=24h
MONGO_URI=mongodb://localhost:27017/book_review_platform
OPENAI_API_KEY=your-openai-key
```

### Application Structure
```
/opt/backend-app/
├── current/              # Current deployment
├── logs/                 # Application logs
├── backups/              # Database backups
├── .env                  # Environment configuration
├── ecosystem.config.js   # PM2 configuration
├── deploy.sh            # Deployment script
├── backup-mongodb.sh    # Database backup
└── restore-mongodb.sh   # Database restore
```

## 🔍 Monitoring & Troubleshooting

### Check Application Status
```bash
# SSH to instance
ssh -i ~/.ssh/review-platform-backend ec2-user@$EC2_IP

# Check PM2 status
sudo -u backend-user pm2 list

# View logs
sudo tail -f /opt/backend-app/logs/combined.log

# Check MongoDB status
sudo systemctl status mongod

# Test health endpoint
curl http://localhost:5000/health
```

### Common Issues

#### Application Not Starting
```bash
# Check PM2 logs
sudo -u backend-user pm2 logs

# Check system logs
sudo journalctl -u backend-app

# Restart application
sudo systemctl restart backend-app
```

#### Database Connection Issues
```bash
# Check MongoDB status
sudo systemctl status mongod

# View MongoDB logs
sudo tail -f /var/log/mongodb/mongod.log

# Restart MongoDB
sudo systemctl restart mongod
```

#### Network Issues
```bash
# Check security group rules
aws ec2 describe-security-groups --group-ids sg-xxxxx

# Test port connectivity
telnet $EC2_IP 5000

# Check firewall (if enabled)
sudo firewall-cmd --list-all
```

## 📊 API Endpoints

### Health & System
- `GET /health` - Basic health check
- `GET /health/ready` - Readiness probe
- `GET /health/live` - Liveness probe
- `GET /api/v1` - API version info

### Authentication
- `POST /api/v1/auth/register` - User registration
- `POST /api/v1/auth/login` - User login
- `GET /api/v1/auth/profile` - Get user profile

### Books
- `GET /api/v1/books` - List books
- `GET /api/v1/books/:id` - Get book by ID
- `GET /api/v1/books/search` - Search books

### Reviews
- `GET /api/v1/reviews` - List reviews
- `POST /api/v1/reviews` - Create review
- `GET /api/v1/reviews/:id` - Get review by ID
- `PUT /api/v1/reviews/:id` - Update review
- `DELETE /api/v1/reviews/:id` - Delete review

### Favorites
- `GET /api/v1/favorites` - Get user favorites
- `POST /api/v1/favorites` - Add to favorites
- `DELETE /api/v1/favorites/:bookId` - Remove from favorites

### Recommendations
- `GET /api/v1/recommendations` - Get AI recommendations
- `POST /api/v1/recommendations/feedback` - Provide feedback

### User Profile
- `GET /api/v1/users/profile` - Get profile
- `PUT /api/v1/users/profile` - Update profile

## 🔄 CI/CD Workflows

### Infrastructure Pipeline
**Trigger**: Manual or push to `main` (terraform files)
**Steps**:
1. Validate Terraform configuration
2. Plan infrastructure changes
3. Apply changes (with approval)
4. Verify deployment

### Application Pipeline
**Trigger**: Manual or push to `main` (backend code)
**Steps**:
1. Build and test application
2. Create deployment package
3. Deploy to EC2
4. Run health checks
5. Execute API tests

## 🔒 Security Considerations

### Network Security
- Security group restricts access to necessary ports
- SSH access can be limited to specific IP ranges
- HTTPS should be configured for production

### Application Security
- JWT tokens for authentication
- Input validation on all endpoints
- Rate limiting configured
- CORS properly configured

### Data Security
- MongoDB access restricted to VPC
- Regular database backups
- Environment variables for secrets
- IAM roles with minimal permissions

## 🚀 Production Checklist

### Before Deployment
- [ ] SSH keys generated and secured
- [ ] GitHub secrets configured
- [ ] AWS permissions verified
- [ ] Domain/SSL certificate ready (optional)

### After Deployment
- [ ] Health checks passing
- [ ] Database migrated successfully
- [ ] All API endpoints tested
- [ ] Monitoring configured
- [ ] Backup schedule verified

### Ongoing Maintenance
- [ ] Monitor CloudWatch logs
- [ ] Regular security updates
- [ ] Database backup verification
- [ ] Performance monitoring
- [ ] SSL certificate renewal (if applicable)

## 📞 Support

### Useful Commands
```bash
# Get infrastructure outputs
terraform output

# Check deployment status
curl http://$EC2_IP:5000/health

# View application logs
ssh -i ~/.ssh/review-platform-backend ec2-user@$EC2_IP \
  "sudo tail -f /opt/backend-app/logs/combined.log"

# Restart application
ssh -i ~/.ssh/review-platform-backend ec2-user@$EC2_IP \
  "sudo systemctl restart backend-app"

# Run API tests
./deployment/scripts/test-backend-apis.sh http://$EC2_IP:5000
```

### Log Locations
- Application logs: `/opt/backend-app/logs/`
- MongoDB logs: `/var/log/mongodb/mongod.log`
- System logs: `journalctl -u backend-app`
- CloudWatch: `/aws/ec2/review-platform-backend`

This deployment guide ensures a robust, scalable, and maintainable backend infrastructure for the Book Review Platform.
