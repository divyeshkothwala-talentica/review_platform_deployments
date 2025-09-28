#!/bin/bash

# Frontend Environment Configuration
# This script creates the necessary environment files for the frontend

# Configuration
BACKEND_API_URL="http://43.205.211.216:5000"
FRONTEND_DIR="$(dirname "$0")/../../fe_review_platform"

# Create .env.development
cat > "$FRONTEND_DIR/.env.development" << EOF
REACT_APP_API_URL=$BACKEND_API_URL
REACT_APP_ENVIRONMENT=development
GENERATE_SOURCEMAP=true
EOF

# Create .env.production
cat > "$FRONTEND_DIR/.env.production" << EOF
REACT_APP_API_URL=$BACKEND_API_URL
REACT_APP_ENVIRONMENT=production
GENERATE_SOURCEMAP=false
EOF

# Create .env.local (for local development override)
cat > "$FRONTEND_DIR/.env.local" << EOF
REACT_APP_API_URL=$BACKEND_API_URL
REACT_APP_ENVIRONMENT=local
EOF

echo "Environment files created successfully!"
echo "Backend API URL: $BACKEND_API_URL"
