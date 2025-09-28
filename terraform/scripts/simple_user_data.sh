#!/bin/bash

set -e

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/user-data.log
}

log "Starting backend instance initialization..."

# Update system packages
log "Updating system packages..."
dnf update -y

# Install essential packages
log "Installing essential packages..."
dnf install -y git curl wget unzip tar gcc-c++ make python3 python3-pip

# Install Node.js 18.x using NodeSource repository
log "Installing Node.js 18.x..."
curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
dnf install -y nodejs

# Verify Node.js and npm installation
node_version=$(node --version)
npm_version=$(npm --version)
log "Node.js version: $node_version"
log "NPM version: $npm_version"

# Install PM2 globally for process management
log "Installing PM2 process manager..."
npm install -g pm2

# Install MongoDB 7.0
log "Installing MongoDB 7.0..."
cat > /etc/yum.repos.d/mongodb-org-7.0.repo << 'EOF'
[mongodb-org-7.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/amazon/2023/mongodb-org/7.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-7.0.asc
EOF

dnf install -y mongodb-org

# Configure MongoDB
log "Configuring MongoDB..."
systemctl enable mongod
systemctl start mongod

# Wait for MongoDB to start
sleep 10

# Verify MongoDB installation
log "Verifying MongoDB installation..."
if systemctl is-active --quiet mongod; then
    log "MongoDB is running successfully"
else
    log "ERROR: MongoDB failed to start"
    systemctl status mongod
fi

# Create application directory
log "Creating application directory..."
mkdir -p /opt/backend-app
mkdir -p /opt/backend-app/logs
mkdir -p /opt/backend-app/backups

# Create application user
log "Creating application user..."
useradd -r -s /bin/bash -d /opt/backend-app backend-user
chown -R backend-user:backend-user /opt/backend-app

# Create environment file
log "Creating environment configuration..."
cat > /opt/backend-app/.env << EOF
# Server Configuration
PORT=5000
NODE_ENV=production
API_VERSION=v1

# CORS Configuration
CORS_ORIGIN=https://d157ilt95f9lq6.cloudfront.net

# JWT Configuration
JWT_SECRET=your-super-secret-jwt-key-change-in-production-2024-070b21e6e6b3b61aaae655c35f2105ca
JWT_EXPIRES_IN=24h

# Rate Limiting
RATE_LIMIT_WINDOW_MS=60000
RATE_LIMIT_MAX_REQUESTS=100

# Logging
LOG_LEVEL=info

# MongoDB Configuration
MONGO_URI=mongodb://localhost:27017/book_review_platform
MONGO_MAX_POOL_SIZE=10
MONGO_SERVER_SELECTION_TIMEOUT_MS=5000
MONGO_SOCKET_TIMEOUT_MS=45000

# OpenAI Configuration
OPENAI_API_KEY=your-openai-api-key-here
OPENAI_MODEL=gpt-3.5-turbo
OPENAI_MAX_TOKENS=1000
OPENAI_TEMPERATURE=0.7
EOF

chown backend-user:backend-user /opt/backend-app/.env
chmod 600 /opt/backend-app/.env

# Create status file
log "Creating status file..."
cat > /opt/backend-app/status.json << EOF
{
  "initialization_completed": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "node_version": "$node_version",
  "npm_version": "$npm_version",
  "mongodb_status": "$(systemctl is-active mongod)",
  "ready_for_deployment": true
}
EOF

chown backend-user:backend-user /opt/backend-app/status.json

log "Backend instance initialization completed successfully!"
log "Instance is ready for application deployment."
log "Status file created at: /opt/backend-app/status.json"

log "User data script execution completed."
