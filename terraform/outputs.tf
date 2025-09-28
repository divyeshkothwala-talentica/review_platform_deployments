output "backend_instance_id" {
  description = "ID of the backend EC2 instance"
  value       = aws_instance.backend_instance.id
}

output "backend_public_ip" {
  description = "Public IP address of the backend instance"
  value       = aws_eip.backend_eip.public_ip
}

output "backend_private_ip" {
  description = "Private IP address of the backend instance"
  value       = aws_instance.backend_instance.private_ip
}

output "backend_api_url" {
  description = "Backend API URL"
  value       = "http://${aws_eip.backend_eip.public_ip}:5000"
}

output "backend_api_health_url" {
  description = "Backend API health check URL"
  value       = "http://${aws_eip.backend_eip.public_ip}:5000/health"
}

output "backend_ssh_command" {
  description = "SSH command to connect to the backend instance"
  value       = "ssh -i ~/.ssh/your-key.pem ec2-user@${aws_eip.backend_eip.public_ip}"
}

output "backend_vpc_id" {
  description = "ID of the backend VPC"
  value       = aws_vpc.backend_vpc.id
}

output "backend_subnet_id" {
  description = "ID of the backend public subnet"
  value       = aws_subnet.backend_public_subnet.id
}

output "backend_security_group_id" {
  description = "ID of the backend security group"
  value       = aws_security_group.backend_sg.id
}

output "backend_s3_bucket" {
  description = "S3 bucket for backend artifacts"
  value       = aws_s3_bucket.backend_artifacts.bucket
}

output "backend_cloudwatch_log_group" {
  description = "CloudWatch log group for backend logs"
  value       = aws_cloudwatch_log_group.backend_logs.name
}

output "github_actions_backend_role_arn" {
  description = "ARN of the GitHub Actions role for backend deployment"
  value       = aws_iam_role.github_actions_backend_role.arn
}

output "backend_instance_profile_arn" {
  description = "ARN of the backend instance profile"
  value       = aws_iam_instance_profile.backend_ec2_profile.arn
}

output "mongodb_connection_string" {
  description = "MongoDB connection string for the application"
  value       = "mongodb://localhost:27017/${var.mongo_db_name}"
  sensitive   = false
}

output "deployment_instructions" {
  description = "Instructions for deploying the backend application"
  value = <<-EOT
    Backend Infrastructure Deployed Successfully!
    
    Instance Details:
    - Instance ID: ${aws_instance.backend_instance.id}
    - Public IP: ${aws_eip.backend_eip.public_ip}
    - API URL: http://${aws_eip.backend_eip.public_ip}:5000
    
    SSH Access:
    ssh -i ~/.ssh/your-key.pem ec2-user@${aws_eip.backend_eip.public_ip}
    
    Next Steps:
    1. Wait for the instance to complete initialization (check cloud-init logs)
    2. Deploy your application using the GitHub Actions pipeline
    3. Test the API endpoints at http://${aws_eip.backend_eip.public_ip}:5000/health
    4. Import MongoDB data using the provided scripts
    
    Monitoring:
    - CloudWatch Logs: ${aws_cloudwatch_log_group.backend_logs.name}
    - S3 Artifacts: ${aws_s3_bucket.backend_artifacts.bucket}
  EOT
}
