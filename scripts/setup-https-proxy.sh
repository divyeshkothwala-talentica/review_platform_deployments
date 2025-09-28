#!/bin/bash

set -e

echo "🔧 Setting up HTTPS reverse proxy with self-signed certificate..."

# Install nginx
echo "📦 Installing nginx..."
sudo dnf install -y nginx

# Create SSL certificate directory
echo "📁 Creating SSL certificate directory..."
sudo mkdir -p /etc/nginx/ssl

# Generate self-signed SSL certificate
echo "🔐 Generating self-signed SSL certificate..."
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/backend.key \
    -out /etc/nginx/ssl/backend.crt \
    -subj "/C=US/ST=State/L=City/O=Organization/CN=44.194.207.22"

# Set proper permissions
sudo chmod 600 /etc/nginx/ssl/backend.key
sudo chmod 644 /etc/nginx/ssl/backend.crt

# Create nginx configuration
echo "⚙️ Creating nginx configuration..."
sudo tee /etc/nginx/conf.d/backend-api.conf << 'EOF'
# Backend API HTTPS Reverse Proxy Configuration

# Redirect HTTP to HTTPS
server {
    listen 80;
    server_name 44.194.207.22;
    return 301 https://$server_name$request_uri;
}

# HTTPS server
server {
    listen 443 ssl http2;
    server_name 44.194.207.22;

    # SSL Configuration
    ssl_certificate /etc/nginx/ssl/backend.crt;
    ssl_certificate_key /etc/nginx/ssl/backend.key;
    
    # SSL Security Settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA384;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # Security Headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # CORS Headers
    add_header Access-Control-Allow-Origin "https://d157ilt95f9lq6.cloudfront.net" always;
    add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" always;
    add_header Access-Control-Allow-Headers "Origin, X-Requested-With, Content-Type, Accept, Authorization, X-API-Version" always;
    add_header Access-Control-Allow-Credentials "true" always;

    # Handle preflight requests
    if ($request_method = 'OPTIONS') {
        add_header Access-Control-Allow-Origin "https://d157ilt95f9lq6.cloudfront.net";
        add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS";
        add_header Access-Control-Allow-Headers "Origin, X-Requested-With, Content-Type, Accept, Authorization, X-API-Version";
        add_header Access-Control-Allow-Credentials "true";
        add_header Content-Length 0;
        add_header Content-Type text/plain;
        return 204;
    }

    # Proxy to Node.js application
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Buffer settings
        proxy_buffering on;
        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_busy_buffers_size 256k;
    }

    # Health check endpoint
    location /health {
        proxy_pass http://127.0.0.1:5000/health;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Quick timeout for health checks
        proxy_connect_timeout 5s;
        proxy_send_timeout 5s;
        proxy_read_timeout 5s;
    }

    # Logging
    access_log /var/log/nginx/backend-api.access.log;
    error_log /var/log/nginx/backend-api.error.log;
}

# Alternative HTTPS server on port 5000 (for backward compatibility)
server {
    listen 5000 ssl http2;
    server_name 44.194.207.22;

    # SSL Configuration (same as above)
    ssl_certificate /etc/nginx/ssl/backend.crt;
    ssl_certificate_key /etc/nginx/ssl/backend.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA384;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # CORS Headers
    add_header Access-Control-Allow-Origin "https://d157ilt95f9lq6.cloudfront.net" always;
    add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" always;
    add_header Access-Control-Allow-Headers "Origin, X-Requested-With, Content-Type, Accept, Authorization, X-API-Version" always;
    add_header Access-Control-Allow-Credentials "true" always;

    # Handle preflight requests
    if ($request_method = 'OPTIONS') {
        add_header Access-Control-Allow-Origin "https://d157ilt95f9lq6.cloudfront.net";
        add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS";
        add_header Access-Control-Allow-Headers "Origin, X-Requested-With, Content-Type, Accept, Authorization, X-API-Version";
        add_header Access-Control-Allow-Credentials "true";
        add_header Content-Length 0;
        add_header Content-Type text/plain;
        return 204;
    }

    # Proxy to Node.js application
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }

    # Logging
    access_log /var/log/nginx/backend-api-5000.access.log;
    error_log /var/log/nginx/backend-api-5000.error.log;
}
EOF

# Test nginx configuration
echo "🧪 Testing nginx configuration..."
sudo nginx -t

# Enable and start nginx
echo "🚀 Starting nginx..."
sudo systemctl enable nginx
sudo systemctl start nginx

# Configure firewall for HTTPS
echo "🔥 Configuring firewall..."
if systemctl is-active --quiet firewalld; then
    sudo firewall-cmd --permanent --add-service=http
    sudo firewall-cmd --permanent --add-service=https
    sudo firewall-cmd --permanent --add-port=5000/tcp
    sudo firewall-cmd --reload
fi

# Show status
echo "📊 Checking nginx status..."
sudo systemctl status nginx --no-pager

echo "✅ HTTPS reverse proxy setup completed!"
echo ""
echo "🌐 Your application is now accessible via:"
echo "   - https://44.194.207.22 (standard HTTPS port 443)"
echo "   - https://44.194.207.22:5000 (custom HTTPS port 5000)"
echo "   - http://44.194.207.22 (redirects to HTTPS)"
echo ""
echo "⚠️  Note: Self-signed certificate will show browser warnings"
echo "   Accept the certificate to proceed"
echo ""
echo "🔍 To test:"
echo "   curl -k https://44.194.207.22/health"
echo "   curl -k https://44.194.207.22:5000/health"
