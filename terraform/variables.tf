variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "review-platform"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "public_key" {
  description = "Public key for EC2 access"
  type        = string
  sensitive   = true
}

variable "private_key" {
  description = "Private key for EC2 access"
  type        = string
  sensitive   = true
}

variable "openai_api_key" {
  description = "OpenAI API key for recommendations"
  type        = string
  sensitive   = true
}

variable "cors_origin" {
  description = "CORS origin for the frontend"
  type        = string
  default     = "https://d157ilt95f9lq6.cloudfront.net"
}

variable "jwt_secret" {
  description = "JWT secret for authentication"
  type        = string
  sensitive   = true
  default     = "your-super-secret-jwt-key-change-in-production-2024"
}

variable "mongo_db_name" {
  description = "MongoDB database name"
  type        = string
  default     = "book_review_platform"
}

variable "github_repo" {
  description = "GitHub repository for CI/CD"
  type        = string
  default     = "your-username/your-repo"
}

variable "domain_name" {
  description = "Domain name for the backend API (optional)"
  type        = string
  default     = ""
}

variable "certificate_arn" {
  description = "SSL certificate ARN (optional)"
  type        = string
  default     = ""
}

variable "enable_monitoring" {
  description = "Enable CloudWatch monitoring"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
}

variable "allowed_ssh_cidr" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_version" {
  description = "Node.js version to install"
  type        = string
  default     = "18"
}

variable "npm_version" {
  description = "NPM version to install"
  type        = string
  default     = "latest"
}
