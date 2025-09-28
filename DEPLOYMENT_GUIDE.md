# Complete Frontend Deployment Guide

This guide provides step-by-step instructions for deploying the Review Platform frontend to AWS using S3 and CloudFront.

## 🎯 Overview

The deployment creates:
- **S3 Bucket**: Static website hosting
- **CloudFront Distribution**: Global CDN with caching
- **IAM Roles**: GitHub Actions integration
- **CI/CD Pipelines**: Automated deployment workflows

**Backend Integration**: The frontend is configured to communicate with the backend at `http://43.205.211.216:5000`

## 📋 Prerequisites

Before starting, ensure you have:

1. **AWS Account** with appropriate permissions
2. **AWS CLI** installed and configured
3. **Terraform** >= 1.0 installed
4. **Node.js** >= 18 installed
5. **GitHub Repository** for the project
6. **Git** configured locally

### AWS Permissions Required

Your AWS user/role needs these permissions:
- S3: Full access for bucket management
- CloudFront: Full access for distribution management
- IAM: Create roles and policies
- Route53: (Optional) For custom domains

## 🚀 Step-by-Step Deployment

### Step 1: Clone and Prepare Repository

```bash
# If not already done, initialize git repository
cd /Users/divyeshk/learning
git init
git add .
git commit -m "Initial commit with deployment infrastructure"

# Push to GitHub (replace with your repository)
git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO.git
git push -u origin main
```

### Step 2: Configure Infrastructure

```bash
cd deployment/terraform

# Copy and edit configuration
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:
```hcl
# AWS Configuration
aws_region = "us-east-1"
environment = "dev"

# Project Configuration
project_name = "review-platform-frontend"
bucket_name = "review-platform-frontend-dev-YOUR-UNIQUE-SUFFIX"

# CloudFront Configuration
cloudfront_price_class = "PriceClass_100"

# GitHub Configuration
github_repo = "YOUR_USERNAME/YOUR_REPO_NAME"

# Backend Configuration
backend_api_url = "http://43.205.211.216:5000"
```

### Step 3: Deploy Infrastructure

```bash
cd ../scripts
./setup-infrastructure.sh
```

This script will:
1. Validate prerequisites
2. Initialize Terraform
3. Create deployment plan
4. Deploy AWS resources
5. Display GitHub secrets configuration

### Step 4: Configure GitHub Repository

Add these secrets to your GitHub repository at `Settings > Secrets and variables > Actions`:

```
AWS_ROLE_ARN=<from_terraform_output>
S3_BUCKET_NAME=<from_terraform_output>
CLOUDFRONT_DISTRIBUTION_ID=<from_terraform_output>
CLOUDFRONT_DOMAIN_NAME=<from_terraform_output>
BACKEND_API_URL=http://43.205.211.216:5000
ENVIRONMENT=dev
```

### Step 5: Copy GitHub Workflows

```bash
# Copy workflow files to your repository root
cp -r deployment/pipelines/.github .github

# Commit and push
git add .github/
git commit -m "Add CI/CD workflows"
git push
```

### Step 6: Configure Frontend Environment

```bash
cd deployment/config
./frontend-env.sh
```

This creates the necessary environment files for the frontend.

### Step 7: Deploy Frontend

**Option A: Manual Deployment**
```bash
cd deployment/scripts
./deploy-frontend.sh --environment dev
```

**Option B: Automatic Deployment**
```bash
# Push changes to trigger automatic deployment
git add fe_review_platform/
git commit -m "Update frontend configuration"
git push
```

## 🔧 Configuration Details

### Frontend Environment Variables

The frontend uses these environment variables:

| Variable | Description | Value |
|----------|-------------|-------|
| `REACT_APP_API_URL` | Backend API endpoint | `http://43.205.211.216:5000` |
| `REACT_APP_ENVIRONMENT` | Current environment | `dev/staging/prod` |
| `GENERATE_SOURCEMAP` | Generate source maps | `false` (production) |

### AWS Resources Created

| Resource | Purpose | Configuration |
|----------|---------|---------------|
| S3 Bucket | Static hosting | Private, versioned |
| CloudFront | CDN | Global distribution |
| IAM Role | GitHub Actions | Minimal permissions |
| OAC | S3 access control | Secure access |

### Caching Strategy

| Content Type | Cache Duration | Headers |
|--------------|----------------|---------|
| HTML files | No cache | `max-age=0,must-revalidate` |
| Static assets | 1 year | `max-age=31536000,immutable` |
| Service Worker | No cache | `max-age=0,must-revalidate` |

## 🔍 Verification Steps

### 1. Infrastructure Verification

```bash
cd deployment/terraform
terraform output
```

Expected outputs:
- `website_url`: Your CloudFront URL
- `s3_bucket_name`: S3 bucket name
- `cloudfront_distribution_id`: Distribution ID

### 2. Frontend Verification

```bash
# Test local build
cd fe_review_platform
npm install
npm run build

# Check environment configuration
cat .env.production
```

### 3. Deployment Verification

1. **Visit the website URL** from Terraform output
2. **Check browser network tab** for API calls to backend
3. **Verify CORS** - no CORS errors in console
4. **Test functionality** - login, browse books, etc.

## 🐛 Troubleshooting

### Common Issues

#### 1. Bucket Name Already Exists
```
Error: BucketAlreadyExists
```
**Solution**: Change `bucket_name` in `terraform.tfvars` to a unique value.

#### 2. GitHub Actions Permission Denied
```
Error: AccessDenied when calling AssumeRoleWithWebIdentity
```
**Solution**: 
- Verify GitHub repository name in `terraform.tfvars`
- Check GitHub secrets are correctly set
- Ensure OIDC provider is configured

#### 3. CORS Errors in Browser
```
Access to fetch at 'http://43.205.211.216:5000' from origin 'https://xxx.cloudfront.net' has been blocked by CORS policy
```
**Solution**: Configure CORS on backend server:
```javascript
app.use(cors({
  origin: ['https://YOUR_CLOUDFRONT_DOMAIN.cloudfront.net'],
  credentials: true
}));
```

#### 4. CloudFront Not Updating
**Solution**: 
- Wait 5-15 minutes for cache invalidation
- Force refresh with Ctrl+F5
- Check CloudFront invalidation status in AWS Console

#### 5. Build Failures
```
npm run build fails
```
**Solution**:
- Check Node.js version (>= 18 required)
- Clear node_modules: `rm -rf node_modules && npm install`
- Check for TypeScript errors: `npm run build`

### Logs and Monitoring

#### GitHub Actions Logs
- Go to repository > Actions tab
- Click on failed workflow
- Check individual job logs

#### AWS CloudWatch Logs
- CloudFront access logs (if enabled)
- S3 access logs (if enabled)

#### Browser Developer Tools
- Network tab for API calls
- Console for JavaScript errors
- Application tab for local storage

## 🔄 Maintenance Operations

### Update Backend URL

```bash
# Update configuration
cd deployment/terraform
# Edit terraform.tfvars - change backend_api_url
terraform apply

# Update frontend
cd ../config
# Edit frontend-env.sh - change BACKEND_API_URL
./frontend-env.sh

# Redeploy
cd ../scripts
./deploy-frontend.sh
```

### Scale CloudFront

```bash
cd deployment/terraform
# Edit terraform.tfvars - change cloudfront_price_class to PriceClass_200 or PriceClass_All
terraform apply
```

### Add Custom Domain

1. **Get SSL Certificate** (AWS Certificate Manager)
2. **Update Terraform** configuration
3. **Configure DNS** (Route53 or external)

### Rollback Deployment

```bash
# Rollback to previous commit
git checkout <previous-commit>
cd deployment/scripts
./deploy-frontend.sh

# Or rollback infrastructure
cd deployment/terraform
terraform apply -target=<specific-resource>
```

## 🔐 Security Best Practices

### Infrastructure Security
- ✅ S3 bucket is private (no public access)
- ✅ CloudFront OAC restricts S3 access
- ✅ IAM roles have minimal permissions
- ✅ HTTPS enforced for all traffic

### Application Security
- ✅ Environment variables for configuration
- ✅ No sensitive data in frontend code
- ✅ CORS properly configured
- ✅ Source maps disabled in production

### CI/CD Security
- ✅ GitHub Actions uses OIDC (no long-term keys)
- ✅ Secrets stored in GitHub repository secrets
- ✅ Terraform state secured (consider remote backend)

## 📊 Performance Optimization

### Current Optimizations
- ✅ CloudFront global CDN
- ✅ Gzip compression enabled
- ✅ Optimized cache headers
- ✅ Static asset caching (1 year)
- ✅ HTML no-cache for SPA routing

### Additional Optimizations
- [ ] Enable CloudFront compression
- [ ] Implement service worker caching
- [ ] Add performance monitoring
- [ ] Optimize bundle size

## 📞 Support and Next Steps

### Immediate Next Steps
1. ✅ Infrastructure deployed
2. ✅ Frontend configured for backend integration
3. ✅ CI/CD pipelines ready
4. 🔄 Test complete user workflow
5. 🔄 Monitor performance and errors

### Future Enhancements
- [ ] Custom domain with SSL
- [ ] Staging environment
- [ ] Blue-green deployments
- [ ] Performance monitoring
- [ ] Error tracking (Sentry)
- [ ] Analytics integration

### Getting Help
- **Infrastructure Issues**: Check Terraform documentation
- **Deployment Issues**: Review GitHub Actions logs
- **Frontend Issues**: Check browser developer tools
- **Backend Integration**: Verify CORS configuration

---

## 📋 Quick Reference Commands

```bash
# Deploy infrastructure
cd deployment/scripts && ./setup-infrastructure.sh

# Deploy frontend
cd deployment/scripts && ./deploy-frontend.sh

# Check infrastructure status
cd deployment/terraform && terraform output

# Update frontend environment
cd deployment/config && ./frontend-env.sh

# View deployment logs
# Go to GitHub repository > Actions tab
```

**🎉 Congratulations!** Your frontend is now deployed and ready to serve users globally through CloudFront CDN.
