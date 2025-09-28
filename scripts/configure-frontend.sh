#!/bin/bash

# Frontend Configuration Script
# Updates the frontend to integrate with the specified backend API

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
FRONTEND_DIR="$(dirname "$0")/../../fe_review_platform"
BACKEND_URL="http://43.205.211.216:5000"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -u, --url           Backend API URL [default: http://43.205.211.216:5000]"
    echo "  -e, --environment   Environment (dev/staging/prod) [default: dev]"
    echo "  -h, --help         Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Use default backend URL"
    echo "  $0 -u https://api.example.com        # Use custom backend URL"
    echo "  $0 -u http://localhost:5000 -e dev   # Use local backend for development"
}

parse_arguments() {
    ENVIRONMENT="dev"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -u|--url)
                BACKEND_URL="$2"
                shift 2
                ;;
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

validate_backend_url() {
    log_info "Validating backend URL: $BACKEND_URL"
    
    # Basic URL format validation
    if [[ ! "$BACKEND_URL" =~ ^https?:// ]]; then
        log_error "Invalid URL format. URL must start with http:// or https://"
        exit 1
    fi
    
    # Test backend connectivity (optional - may fail if backend is not running)
    log_info "Testing backend connectivity..."
    if curl -s --connect-timeout 5 "$BACKEND_URL/health" > /dev/null 2>&1; then
        log_success "Backend is reachable"
    else
        log_warning "Backend is not reachable (this is okay if it's not running yet)"
    fi
}

update_api_service() {
    log_info "Updating API service configuration..."
    
    local api_file="$FRONTEND_DIR/src/services/api.ts"
    
    if [[ ! -f "$api_file" ]]; then
        log_error "API service file not found: $api_file"
        exit 1
    fi
    
    # Create backup
    cp "$api_file" "$api_file.backup"
    
    # Update the default API URL in the constructor
    sed -i.tmp "s|this\.baseURL = process\.env\.REACT_APP_API_URL || '[^']*';|this.baseURL = process.env.REACT_APP_API_URL || '$BACKEND_URL';|g" "$api_file"
    
    # Update the getBase function
    sed -i.tmp "s|return process\.env\.REACT_APP_API_URL || '[^']*';|return process.env.REACT_APP_API_URL || '$BACKEND_URL';|g" "$api_file"
    
    # Remove temporary file
    rm -f "$api_file.tmp"
    
    log_success "API service updated"
}

create_env_files() {
    log_info "Creating environment configuration files..."
    
    cd "$FRONTEND_DIR"
    
    # Create .env.development
    cat > .env.development << EOF
REACT_APP_API_URL=$BACKEND_URL
REACT_APP_ENVIRONMENT=development
GENERATE_SOURCEMAP=true
EOF
    
    # Create .env.production
    cat > .env.production << EOF
REACT_APP_API_URL=$BACKEND_URL
REACT_APP_ENVIRONMENT=$ENVIRONMENT
GENERATE_SOURCEMAP=false
EOF
    
    # Create .env.local (for local development override)
    cat > .env.local << EOF
REACT_APP_API_URL=$BACKEND_URL
REACT_APP_ENVIRONMENT=local
EOF
    
    log_success "Environment files created"
}

update_package_json() {
    log_info "Checking package.json configuration..."
    
    local package_file="$FRONTEND_DIR/package.json"
    
    if [[ ! -f "$package_file" ]]; then
        log_error "package.json not found: $package_file"
        exit 1
    fi
    
    # Check if proxy is set (remove it as we're using CORS)
    if grep -q '"proxy"' "$package_file"; then
        log_warning "Removing proxy configuration from package.json (using CORS instead)"
        # Create backup
        cp "$package_file" "$package_file.backup"
        # Remove proxy line
        sed -i.tmp '/"proxy"/d' "$package_file"
        rm -f "$package_file.tmp"
    fi
    
    log_success "package.json configuration verified"
}

create_cors_info() {
    log_info "Creating CORS configuration information..."
    
    cat > "$FRONTEND_DIR/CORS_SETUP.md" << EOF
# CORS Configuration for Backend

To enable the frontend to communicate with the backend at $BACKEND_URL, ensure the backend has CORS configured properly.

## Required CORS Headers

The backend should include these headers in responses:

\`\`\`
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS
Access-Control-Allow-Headers: Content-Type, Authorization
Access-Control-Max-Age: 86400
\`\`\`

## Backend Configuration Example (Express.js)

\`\`\`javascript
const cors = require('cors');

app.use(cors({
  origin: ['http://localhost:3000', 'https://your-cloudfront-domain.cloudfront.net'],
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  credentials: true
}));
\`\`\`

## Testing CORS

Test CORS configuration with:
\`\`\`bash
curl -H "Origin: http://localhost:3000" \\
     -H "Access-Control-Request-Method: GET" \\
     -H "Access-Control-Request-Headers: Content-Type" \\
     -X OPTIONS \\
     $BACKEND_URL/v1/health
\`\`\`

## Current Configuration

- Backend URL: $BACKEND_URL
- Environment: $ENVIRONMENT
- Frontend will run on: http://localhost:3000 (development)
EOF
    
    log_success "CORS information created at $FRONTEND_DIR/CORS_SETUP.md"
}

test_configuration() {
    log_info "Testing frontend configuration..."
    
    cd "$FRONTEND_DIR"
    
    # Check if dependencies are installed
    if [[ ! -d "node_modules" ]]; then
        log_info "Installing dependencies..."
        npm install
    fi
    
    # Test build (quick check)
    log_info "Testing build configuration..."
    if npm run build > /dev/null 2>&1; then
        log_success "Build test passed"
        # Clean up test build
        rm -rf build
    else
        log_warning "Build test failed - this may be due to missing dependencies or other issues"
    fi
}

show_summary() {
    log_success "Frontend configuration completed!"
    echo
    log_info "Configuration Summary:"
    echo "  🔗 Backend API URL: $BACKEND_URL"
    echo "  🌍 Environment: $ENVIRONMENT"
    echo "  📁 Frontend Directory: $FRONTEND_DIR"
    echo
    log_info "Environment Files Created:"
    echo "  📄 .env.development - Development configuration"
    echo "  📄 .env.production - Production configuration"
    echo "  📄 .env.local - Local development override"
    echo
    log_info "Next Steps:"
    echo "  1. Ensure backend CORS is configured (see CORS_SETUP.md)"
    echo "  2. Test locally: cd $FRONTEND_DIR && npm start"
    echo "  3. Deploy: cd deployment/scripts && ./deploy-frontend.sh"
    echo
    log_warning "Note: Make sure the backend at $BACKEND_URL is running and accessible"
}

main() {
    log_info "Starting frontend configuration..."
    echo
    
    parse_arguments "$@"
    
    # Check if frontend directory exists
    if [[ ! -d "$FRONTEND_DIR" ]]; then
        log_error "Frontend directory not found: $FRONTEND_DIR"
        exit 1
    fi
    
    validate_backend_url
    update_api_service
    create_env_files
    update_package_json
    create_cors_info
    test_configuration
    show_summary
}

# Run main function
main "$@"
