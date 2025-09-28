terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Data source for the latest Amazon Linux 2023 AMI with Node.js 18
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# VPC for the backend infrastructure
resource "aws_vpc" "backend_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.project_name}-backend-vpc"
    Environment = var.environment
    Project     = "Review Platform Backend"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "backend_igw" {
  vpc_id = aws_vpc.backend_vpc.id

  tags = {
    Name        = "${var.project_name}-backend-igw"
    Environment = var.environment
    Project     = "Review Platform Backend"
  }
}

# Public subnet for the EC2 instance
resource "aws_subnet" "backend_public_subnet" {
  vpc_id                  = aws_vpc.backend_vpc.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project_name}-backend-public-subnet"
    Environment = var.environment
    Project     = "Review Platform Backend"
  }
}

# Route table for public subnet
resource "aws_route_table" "backend_public_rt" {
  vpc_id = aws_vpc.backend_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.backend_igw.id
  }

  tags = {
    Name        = "${var.project_name}-backend-public-rt"
    Environment = var.environment
    Project     = "Review Platform Backend"
  }
}

# Route table association
resource "aws_route_table_association" "backend_public_rta" {
  subnet_id      = aws_subnet.backend_public_subnet.id
  route_table_id = aws_route_table.backend_public_rt.id
}

# Security group for the backend EC2 instance
resource "aws_security_group" "backend_sg" {
  name        = "${var.project_name}-backend-sg"
  description = "Security group for backend EC2 instance"
  vpc_id      = aws_vpc.backend_vpc.id

  # HTTPS access for the API (with self-signed certificate)
  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Backend API HTTPS access"
  }

  # Standard HTTPS port
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Standard HTTPS access"
  }

  # HTTP port 80 for health checks and redirects
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP health checks and redirects"
  }

  # Alternative port for API
  ingress {
    from_port   = 5001
    to_port     = 5001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Backend API alternative port"
  }

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access"
  }

  # MongoDB access (for local connections)
  ingress {
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "MongoDB access within VPC"
  }

  # HTTPS outbound
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS outbound"
  }

  # HTTP outbound
  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP outbound"
  }

  # DNS outbound
  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "DNS outbound"
  }

  # All outbound traffic for package installations
  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name        = "${var.project_name}-backend-sg"
    Environment = var.environment
    Project     = "Review Platform Backend"
  }
}

# Key pair for EC2 access
resource "aws_key_pair" "backend_key" {
  key_name   = "${var.project_name}-backend-key"
  public_key = var.public_key

  tags = {
    Name        = "${var.project_name}-backend-key"
    Environment = var.environment
    Project     = "Review Platform Backend"
  }
}

# IAM role for EC2 instance
resource "aws_iam_role" "backend_ec2_role" {
  name = "${var.project_name}-backend-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-backend-ec2-role"
    Environment = var.environment
    Project     = "Review Platform Backend"
  }
}

# IAM policy for EC2 instance
resource "aws_iam_policy" "backend_ec2_policy" {
  name        = "${var.project_name}-backend-ec2-policy"
  description = "Policy for backend EC2 instance"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          "arn:aws:s3:::${var.project_name}-backend-artifacts/*"
        ]
      }
    ]
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "backend_ec2_policy_attachment" {
  role       = aws_iam_role.backend_ec2_role.name
  policy_arn = aws_iam_policy.backend_ec2_policy.arn
}

# Attach AWS Systems Manager managed policy to EC2 role
resource "aws_iam_role_policy_attachment" "backend_ec2_ssm_policy_attachment" {
  role       = aws_iam_role.backend_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAM instance profile
resource "aws_iam_instance_profile" "backend_ec2_profile" {
  name = "${var.project_name}-backend-ec2-profile"
  role = aws_iam_role.backend_ec2_role.name
}

# S3 bucket for deployment artifacts
resource "aws_s3_bucket" "backend_artifacts" {
  bucket = "${var.project_name}-backend-artifacts-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "${var.project_name}-backend-artifacts"
    Environment = var.environment
    Project     = "Review Platform Backend"
  }
}

# Random ID for bucket suffix
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "backend_artifacts_versioning" {
  bucket = aws_s3_bucket.backend_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "backend_artifacts_encryption" {
  bucket = aws_s3_bucket.backend_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# User data script for EC2 instance
locals {
  user_data = base64encode(file("${path.module}/scripts/simple_user_data.sh"))
}

# EC2 instance for the backend
resource "aws_instance" "backend_instance" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.backend_key.key_name
  vpc_security_group_ids = [aws_security_group.backend_sg.id]
  subnet_id              = aws_subnet.backend_public_subnet.id
  iam_instance_profile   = aws_iam_instance_profile.backend_ec2_profile.name

  user_data = local.user_data

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    delete_on_termination = true
    encrypted             = true
  }

  tags = {
    Name        = "${var.project_name}-backend-instance"
    Environment = var.environment
    Project     = "Review Platform Backend"
  }

}

# Elastic IP for the backend instance
resource "aws_eip" "backend_eip" {
  instance = aws_instance.backend_instance.id
  domain   = "vpc"

  tags = {
    Name        = "${var.project_name}-backend-eip"
    Environment = var.environment
    Project     = "Review Platform Backend"
  }

  depends_on = [aws_internet_gateway.backend_igw]
}

# CloudWatch Log Group for application logs
resource "aws_cloudwatch_log_group" "backend_logs" {
  name              = "/aws/ec2/${var.project_name}-backend"
  retention_in_days = 14

  tags = {
    Name        = "${var.project_name}-backend-logs"
    Environment = var.environment
    Project     = "Review Platform Backend"
  }
}

# Data source for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# GitHub Actions IAM role for backend deployment
resource "aws_iam_role" "github_actions_backend_role" {
  name = "${var.project_name}-github-actions-backend-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.github_actions.arn
        }
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-github-actions-backend-role"
    Environment = var.environment
    Project     = "Review Platform Backend"
  }
}

# OIDC provider for GitHub Actions (reuse if exists)
# Use existing GitHub Actions OIDC Provider
data "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
}

# IAM policy for GitHub Actions backend deployment
resource "aws_iam_policy" "github_actions_backend_policy" {
  name        = "${var.project_name}-github-actions-backend-policy"
  description = "Policy for GitHub Actions to deploy backend"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.backend_artifacts.arn,
          "${aws_s3_bucket.backend_artifacts.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:SendCommand",
          "ssm:GetCommandInvocation",
          "ssm:DescribeInstanceInformation"
        ]
        Resource = [
          "arn:aws:ssm:*:*:document/AWS-RunShellScript",
          "arn:aws:ec2:*:*:instance/${aws_instance.backend_instance.id}"
        ]
      }
    ]
  })
}

# Attach policy to GitHub Actions role
resource "aws_iam_role_policy_attachment" "github_actions_backend_policy_attachment" {
  role       = aws_iam_role.github_actions_backend_role.name
  policy_arn = aws_iam_policy.github_actions_backend_policy.arn
}
