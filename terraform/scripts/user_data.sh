#!/bin/bash

# User data script for backend EC2 instance initialization
# This script sets up Node.js 18+, MongoDB, and prepares the environment

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
dnf install -y \
    git \
    curl \
    wget \
    unzip \
    tar \
    gcc-c++ \
    make \
    python3 \
    python3-pip \
    amazon-cloudwatch-agent \
    awscli

# Install Node.js 18.x using NodeSource repository
log "Installing Node.js 18.x..."
curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
dnf install -y nodejs

# Verify Node.js and npm installation
log "Verifying Node.js installation..."
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
CORS_ORIGIN=${cors_origin}

# JWT Configuration
JWT_SECRET=${jwt_secret}
JWT_EXPIRES_IN=24h

# Rate Limiting
RATE_LIMIT_WINDOW_MS=60000
RATE_LIMIT_MAX_REQUESTS=100

# Logging
LOG_LEVEL=info

# MongoDB Configuration
MONGO_URI=mongodb://localhost:27017/${mongo_db_name}
MONGO_MAX_POOL_SIZE=10
MONGO_SERVER_SELECTION_TIMEOUT_MS=5000
MONGO_SOCKET_TIMEOUT_MS=45000

# OpenAI Configuration
OPENAI_API_KEY=${openai_api_key}
OPENAI_MODEL=gpt-3.5-turbo
OPENAI_MAX_TOKENS=1000
OPENAI_TEMPERATURE=0.7
EOF

chown backend-user:backend-user /opt/backend-app/.env
chmod 600 /opt/backend-app/.env

# Create PM2 ecosystem file
log "Creating PM2 ecosystem configuration..."
cat > /opt/backend-app/ecosystem.config.js << 'EOF'
module.exports = {
  apps: [{
    name: 'backend-api',
    script: './dist/app.js',
    cwd: '/opt/backend-app',
    instances: 1,
    exec_mode: 'cluster',
    env: {
      NODE_ENV: 'production',
      PORT: 5000
    },
    error_file: '/opt/backend-app/logs/err.log',
    out_file: '/opt/backend-app/logs/out.log',
    log_file: '/opt/backend-app/logs/combined.log',
    time: true,
    max_memory_restart: '1G',
    restart_delay: 4000,
    max_restarts: 10,
    min_uptime: '10s'
  }]
};
EOF

chown backend-user:backend-user /opt/backend-app/ecosystem.config.js

# Create deployment script
log "Creating deployment script..."
cat > /opt/backend-app/deploy.sh << 'EOF'
#!/bin/bash

set -e

APP_DIR="/opt/backend-app"
BACKUP_DIR="/opt/backend-app/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $APP_DIR/logs/deploy.log
}

log "Starting deployment process..."

# Create backup of current deployment
if [ -d "$APP_DIR/current" ]; then
    log "Creating backup of current deployment..."
    tar -czf "$BACKUP_DIR/backup_$TIMESTAMP.tar.gz" -C "$APP_DIR" current
fi

# Download and extract new deployment
log "Downloading deployment artifact from S3..."
cd $APP_DIR
aws s3 cp s3://${s3_bucket}/backend-latest.tar.gz ./backend-latest.tar.gz

# Extract new deployment
log "Extracting new deployment..."
rm -rf new_deployment
mkdir -p new_deployment
tar -xzf backend-latest.tar.gz -C new_deployment

# Install dependencies
log "Installing dependencies..."
cd new_deployment
npm ci --production

# Build application
log "Building application..."
npm run build

# Stop current application
log "Stopping current application..."
pm2 stop backend-api || true

# Replace current deployment
log "Replacing current deployment..."
cd $APP_DIR
rm -rf current
mv new_deployment current
cd current

# Start application
log "Starting application..."
pm2 start ecosystem.config.js

# Verify deployment
log "Verifying deployment..."
sleep 10
if pm2 list | grep -q "backend-api.*online"; then
    log "Deployment successful!"
    
    # Test health endpoint
    if curl -f http://localhost:5000/health > /dev/null 2>&1; then
        log "Health check passed!"
    else
        log "WARNING: Health check failed"
    fi
else
    log "ERROR: Deployment failed - application not running"
    exit 1
fi

# Cleanup
log "Cleaning up..."
rm -f $APP_DIR/backend-latest.tar.gz

# Clean old backups (keep last 5)
log "Cleaning old backups..."
cd $BACKUP_DIR
ls -t backup_*.tar.gz | tail -n +6 | xargs -r rm -f

log "Deployment completed successfully!"
EOF

chmod +x /opt/backend-app/deploy.sh
chown backend-user:backend-user /opt/backend-app/deploy.sh

# Create MongoDB backup script
log "Creating MongoDB backup script..."
cat > /opt/backend-app/backup-mongodb.sh << 'EOF'
#!/bin/bash

set -e

BACKUP_DIR="/opt/backend-app/backups/mongodb"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DB_NAME="${mongo_db_name}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /opt/backend-app/logs/backup.log
}

log "Starting MongoDB backup..."

# Create backup directory
mkdir -p $BACKUP_DIR

# Create backup
log "Creating backup of database: $DB_NAME"
mongodump --db $DB_NAME --out $BACKUP_DIR/dump_$TIMESTAMP

# Compress backup
log "Compressing backup..."
cd $BACKUP_DIR
tar -czf "mongodb_backup_$TIMESTAMP.tar.gz" dump_$TIMESTAMP
rm -rf dump_$TIMESTAMP

# Upload to S3
log "Uploading backup to S3..."
aws s3 cp "mongodb_backup_$TIMESTAMP.tar.gz" s3://${s3_bucket}/backups/

# Clean old local backups (keep last 3)
log "Cleaning old backups..."
ls -t mongodb_backup_*.tar.gz | tail -n +4 | xargs -r rm -f

log "MongoDB backup completed successfully!"
EOF

chmod +x /opt/backend-app/backup-mongodb.sh
chown backend-user:backend-user /opt/backend-app/backup-mongodb.sh

# Create MongoDB restore script
log "Creating MongoDB restore script..."
cat > /opt/backend-app/restore-mongodb.sh << 'EOF'
#!/bin/bash

set -e

BACKUP_FILE=$1
DB_NAME="${mongo_db_name}"

if [ -z "$BACKUP_FILE" ]; then
    echo "Usage: $0 <backup_file.tar.gz>"
    exit 1
fi

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /opt/backend-app/logs/restore.log
}

log "Starting MongoDB restore from: $BACKUP_FILE"

# Extract backup
TEMP_DIR=$(mktemp -d)
cd $TEMP_DIR
tar -xzf "$BACKUP_FILE"

# Restore database
log "Restoring database: $DB_NAME"
mongorestore --db $DB_NAME --drop dump_*/$DB_NAME/

# Cleanup
rm -rf $TEMP_DIR

log "MongoDB restore completed successfully!"
EOF

chmod +x /opt/backend-app/restore-mongodb.sh
chown backend-user:backend-user /opt/backend-app/restore-mongodb.sh

# Configure CloudWatch agent
log "Configuring CloudWatch agent..."
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/opt/backend-app/logs/*.log",
                        "log_group_name": "/aws/ec2/${project_name}-backend",
                        "log_stream_name": "{instance_id}/application",
                        "timezone": "UTC"
                    },
                    {
                        "file_path": "/var/log/mongodb/mongod.log",
                        "log_group_name": "/aws/ec2/${project_name}-backend",
                        "log_stream_name": "{instance_id}/mongodb",
                        "timezone": "UTC"
                    }
                ]
            }
        }
    },
    "metrics": {
        "namespace": "Backend/Application",
        "metrics_collected": {
            "cpu": {
                "measurement": ["cpu_usage_idle", "cpu_usage_iowait", "cpu_usage_user", "cpu_usage_system"],
                "metrics_collection_interval": 60
            },
            "disk": {
                "measurement": ["used_percent"],
                "metrics_collection_interval": 60,
                "resources": ["*"]
            },
            "mem": {
                "measurement": ["mem_used_percent"],
                "metrics_collection_interval": 60
            }
        }
    }
}
EOF

# Start CloudWatch agent
log "Starting CloudWatch agent..."
systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent

# Setup cron jobs
log "Setting up cron jobs..."
cat > /tmp/backend-cron << 'EOF'
# MongoDB backup every day at 2 AM
0 2 * * * /opt/backend-app/backup-mongodb.sh

# Application log rotation
0 0 * * * find /opt/backend-app/logs -name "*.log" -type f -mtime +7 -delete
EOF

crontab -u backend-user /tmp/backend-cron
rm /tmp/backend-cron

# Create systemd service for PM2
log "Creating systemd service for PM2..."
cat > /etc/systemd/system/backend-app.service << 'EOF'
[Unit]
Description=Backend API Application
After=network.target mongod.service

[Service]
Type=forking
User=backend-user
WorkingDirectory=/opt/backend-app
ExecStart=/usr/bin/pm2 start ecosystem.config.js
ExecReload=/usr/bin/pm2 reload ecosystem.config.js
ExecStop=/usr/bin/pm2 stop ecosystem.config.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable backend-app

# Create health check script
log "Creating health check script..."
cat > /opt/backend-app/health-check.sh << 'EOF'
#!/bin/bash

HEALTH_URL="http://localhost:5000/health"
MAX_RETRIES=3
RETRY_DELAY=5

for i in $(seq 1 $MAX_RETRIES); do
    if curl -f $HEALTH_URL > /dev/null 2>&1; then
        echo "Health check passed"
        exit 0
    else
        echo "Health check failed (attempt $i/$MAX_RETRIES)"
        if [ $i -lt $MAX_RETRIES ]; then
            sleep $RETRY_DELAY
        fi
    fi
done

echo "Health check failed after $MAX_RETRIES attempts"
exit 1
EOF

chmod +x /opt/backend-app/health-check.sh
chown backend-user:backend-user /opt/backend-app/health-check.sh

# Create initial deployment placeholder
log "Creating initial deployment structure..."
mkdir -p /opt/backend-app/current
cat > /opt/backend-app/current/package.json << 'EOF'
{
  "name": "backend-placeholder",
  "version": "1.0.0",
  "scripts": {
    "start": "echo 'Waiting for deployment...'"
  }
}
EOF

chown -R backend-user:backend-user /opt/backend-app

# Configure firewall (if needed)
log "Configuring firewall..."
# Amazon Linux 2023 uses firewalld by default
if systemctl is-active --quiet firewalld; then
    firewall-cmd --permanent --add-port=5000/tcp
    firewall-cmd --permanent --add-port=5001/tcp
    firewall-cmd --reload
fi

# Final system configuration
log "Final system configuration..."

# Increase file limits for Node.js
cat >> /etc/security/limits.conf << 'EOF'
backend-user soft nofile 65536
backend-user hard nofile 65536
EOF

# Configure sysctl for better performance
cat >> /etc/sysctl.conf << 'EOF'
# Backend application optimizations
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
vm.swappiness = 10
EOF

sysctl -p

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

# Signal completion
/opt/aws/bin/cfn-signal -e $? --stack ${project_name} --resource BackendInstance --region $(curl -s http://169.254.169.254/latest/meta-data/placement/region) || true

log "User data script execution completed."
