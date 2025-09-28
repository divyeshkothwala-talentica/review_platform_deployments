#!/bin/bash

# MongoDB Data Migration Script
# This script exports data from local MongoDB and imports it to the EC2 instance

set -e

# Configuration
LOCAL_DB_NAME="book_review_platform"
REMOTE_DB_NAME="book_review_platform"
BACKUP_DIR="/tmp/mongodb_migration"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check if MongoDB is running locally
check_local_mongodb() {
    log "Checking local MongoDB connection..."
    if ! mongosh --eval "db.runCommand('ping')" --quiet > /dev/null 2>&1; then
        error "Cannot connect to local MongoDB. Please ensure MongoDB is running locally."
        exit 1
    fi
    success "Local MongoDB connection verified"
}

# Function to check if database exists locally
check_local_database() {
    log "Checking if local database '$LOCAL_DB_NAME' exists..."
    
    if ! mongosh $LOCAL_DB_NAME --eval "db.stats()" --quiet > /dev/null 2>&1; then
        error "Database '$LOCAL_DB_NAME' not found locally."
        error "Please ensure the database exists and contains data."
        exit 1
    fi
    
    # Get collection count
    local collections=$(mongosh $LOCAL_DB_NAME --eval "db.getCollectionNames().length" --quiet)
    if [ "$collections" -eq 0 ]; then
        warning "Database '$LOCAL_DB_NAME' exists but has no collections."
    else
        success "Database '$LOCAL_DB_NAME' found with $collections collections"
    fi
}

# Function to export local database
export_local_database() {
    log "Exporting local database '$LOCAL_DB_NAME'..."
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    # Export database
    if mongodump --db $LOCAL_DB_NAME --out "$BACKUP_DIR/dump_$TIMESTAMP"; then
        success "Database exported successfully to $BACKUP_DIR/dump_$TIMESTAMP"
    else
        error "Failed to export database"
        exit 1
    fi
    
    # Create compressed archive
    log "Creating compressed archive..."
    cd "$BACKUP_DIR"
    if tar -czf "mongodb_export_$TIMESTAMP.tar.gz" "dump_$TIMESTAMP"; then
        success "Archive created: mongodb_export_$TIMESTAMP.tar.gz"
    else
        error "Failed to create archive"
        exit 1
    fi
}

# Function to upload to EC2 instance
upload_to_ec2() {
    local ec2_ip=$1
    local key_file=$2
    
    if [ -z "$ec2_ip" ] || [ -z "$key_file" ]; then
        error "Usage: upload_to_ec2 <ec2_ip> <key_file>"
        return 1
    fi
    
    log "Uploading database archive to EC2 instance ($ec2_ip)..."
    
    # Check if key file exists
    if [ ! -f "$key_file" ]; then
        error "SSH key file not found: $key_file"
        return 1
    fi
    
    # Upload archive
    if scp -i "$key_file" -o StrictHostKeyChecking=no \
        "$BACKUP_DIR/mongodb_export_$TIMESTAMP.tar.gz" \
        "ec2-user@$ec2_ip:/tmp/"; then
        success "Archive uploaded successfully"
    else
        error "Failed to upload archive"
        return 1
    fi
}

# Function to import data on EC2 instance
import_on_ec2() {
    local ec2_ip=$1
    local key_file=$2
    
    if [ -z "$ec2_ip" ] || [ -z "$key_file" ]; then
        error "Usage: import_on_ec2 <ec2_ip> <key_file>"
        return 1
    fi
    
    log "Importing data on EC2 instance..."
    
    # Create import script
    cat > /tmp/import_script.sh << 'EOF'
#!/bin/bash

set -e

ARCHIVE_FILE="/tmp/mongodb_export_*.tar.gz"
TEMP_DIR="/tmp/mongodb_import"
DB_NAME="book_review_platform"

echo "Starting MongoDB import process..."

# Find the archive file
ARCHIVE=$(ls $ARCHIVE_FILE 2>/dev/null | head -1)
if [ -z "$ARCHIVE" ]; then
    echo "ERROR: Archive file not found"
    exit 1
fi

echo "Found archive: $ARCHIVE"

# Create temporary directory
mkdir -p $TEMP_DIR
cd $TEMP_DIR

# Extract archive
echo "Extracting archive..."
tar -xzf "$ARCHIVE"

# Find dump directory
DUMP_DIR=$(find . -name "dump_*" -type d | head -1)
if [ -z "$DUMP_DIR" ]; then
    echo "ERROR: Dump directory not found in archive"
    exit 1
fi

echo "Found dump directory: $DUMP_DIR"

# Import database
echo "Importing database '$DB_NAME'..."
if mongorestore --db $DB_NAME --drop "$DUMP_DIR/$DB_NAME/"; then
    echo "Database imported successfully"
    
    # Verify import
    echo "Verifying import..."
    COLLECTIONS=$(mongosh $DB_NAME --eval "db.getCollectionNames().length" --quiet)
    echo "Imported collections count: $COLLECTIONS"
    
    # Show collection details
    echo "Collection details:"
    mongosh $DB_NAME --eval "
        db.getCollectionNames().forEach(function(collection) {
            var count = db[collection].countDocuments();
            print(collection + ': ' + count + ' documents');
        });
    " --quiet
    
else
    echo "ERROR: Failed to import database"
    exit 1
fi

# Cleanup
echo "Cleaning up temporary files..."
rm -rf $TEMP_DIR
rm -f "$ARCHIVE"

echo "MongoDB import completed successfully!"
EOF

    # Upload and execute import script
    if scp -i "$key_file" -o StrictHostKeyChecking=no \
        /tmp/import_script.sh "ec2-user@$ec2_ip:/tmp/"; then
        
        log "Executing import script on EC2 instance..."
        if ssh -i "$key_file" -o StrictHostKeyChecking=no \
            "ec2-user@$ec2_ip" "chmod +x /tmp/import_script.sh && /tmp/import_script.sh"; then
            success "Data imported successfully on EC2 instance"
        else
            error "Failed to execute import script"
            return 1
        fi
    else
        error "Failed to upload import script"
        return 1
    fi
    
    # Cleanup local script
    rm -f /tmp/import_script.sh
}

# Function to verify import
verify_import() {
    local ec2_ip=$1
    local key_file=$2
    
    log "Verifying data import on EC2 instance..."
    
    # Create verification script
    cat > /tmp/verify_script.sh << 'EOF'
#!/bin/bash

DB_NAME="book_review_platform"

echo "=== MongoDB Import Verification ==="
echo "Database: $DB_NAME"
echo "Timestamp: $(date)"
echo

# Check if MongoDB is running
if ! systemctl is-active --quiet mongod; then
    echo "ERROR: MongoDB service is not running"
    exit 1
fi

echo "✓ MongoDB service is running"

# Check database connection
if ! mongosh --eval "db.runCommand('ping')" --quiet > /dev/null 2>&1; then
    echo "ERROR: Cannot connect to MongoDB"
    exit 1
fi

echo "✓ MongoDB connection successful"

# Check if database exists
if ! mongosh $DB_NAME --eval "db.stats()" --quiet > /dev/null 2>&1; then
    echo "ERROR: Database '$DB_NAME' not found"
    exit 1
fi

echo "✓ Database '$DB_NAME' exists"

# Get collection information
echo
echo "=== Collection Summary ==="
mongosh $DB_NAME --eval "
    var collections = db.getCollectionNames();
    if (collections.length === 0) {
        print('No collections found');
    } else {
        collections.forEach(function(collection) {
            var count = db[collection].countDocuments();
            print(collection + ': ' + count + ' documents');
        });
    }
" --quiet

echo
echo "=== Sample Data Check ==="

# Check for users collection
if mongosh $DB_NAME --eval "db.users.findOne()" --quiet > /dev/null 2>&1; then
    echo "✓ Users collection has data"
else
    echo "⚠ Users collection is empty or missing"
fi

# Check for books collection
if mongosh $DB_NAME --eval "db.books.findOne()" --quiet > /dev/null 2>&1; then
    echo "✓ Books collection has data"
else
    echo "⚠ Books collection is empty or missing"
fi

# Check for reviews collection
if mongosh $DB_NAME --eval "db.reviews.findOne()" --quiet > /dev/null 2>&1; then
    echo "✓ Reviews collection has data"
else
    echo "⚠ Reviews collection is empty or missing"
fi

echo
echo "=== Database Statistics ==="
mongosh $DB_NAME --eval "db.stats()" --quiet

echo
echo "Verification completed!"
EOF

    # Upload and execute verification script
    if scp -i "$key_file" -o StrictHostKeyChecking=no \
        /tmp/verify_script.sh "ec2-user@$ec2_ip:/tmp/"; then
        
        if ssh -i "$key_file" -o StrictHostKeyChecking=no \
            "ec2-user@$ec2_ip" "chmod +x /tmp/verify_script.sh && /tmp/verify_script.sh"; then
            success "Verification completed"
        else
            warning "Verification script failed"
        fi
    else
        warning "Failed to upload verification script"
    fi
    
    # Cleanup
    rm -f /tmp/verify_script.sh
}

# Function to cleanup local files
cleanup() {
    log "Cleaning up local files..."
    if [ -d "$BACKUP_DIR" ]; then
        rm -rf "$BACKUP_DIR"
        success "Local backup files cleaned up"
    fi
}

# Main migration function
migrate_database() {
    local ec2_ip=$1
    local key_file=$2
    
    if [ -z "$ec2_ip" ] || [ -z "$key_file" ]; then
        echo "Usage: $0 migrate <ec2_ip> <ssh_key_file>"
        echo "Example: $0 migrate 54.123.45.67 ~/.ssh/review-platform-backend.pem"
        exit 1
    fi
    
    log "Starting MongoDB migration process..."
    log "Source: Local MongoDB ($LOCAL_DB_NAME)"
    log "Target: EC2 Instance ($ec2_ip)"
    
    # Pre-migration checks
    check_local_mongodb
    check_local_database
    
    # Export data
    export_local_database
    
    # Upload to EC2
    upload_to_ec2 "$ec2_ip" "$key_file"
    
    # Import on EC2
    import_on_ec2 "$ec2_ip" "$key_file"
    
    # Verify import
    verify_import "$ec2_ip" "$key_file"
    
    # Cleanup
    cleanup
    
    success "MongoDB migration completed successfully!"
    log "Your database is now available on the EC2 instance"
}

# Function to show usage
show_usage() {
    echo "MongoDB Migration Tool"
    echo
    echo "Usage:"
    echo "  $0 migrate <ec2_ip> <ssh_key_file>    - Migrate database to EC2"
    echo "  $0 export                             - Export local database only"
    echo "  $0 verify <ec2_ip> <ssh_key_file>     - Verify remote database"
    echo "  $0 help                               - Show this help"
    echo
    echo "Examples:"
    echo "  $0 migrate 54.123.45.67 ~/.ssh/review-platform-backend.pem"
    echo "  $0 export"
    echo "  $0 verify 54.123.45.67 ~/.ssh/review-platform-backend.pem"
    echo
    echo "Prerequisites:"
    echo "  - Local MongoDB running with '$LOCAL_DB_NAME' database"
    echo "  - SSH access to EC2 instance"
    echo "  - MongoDB installed and running on EC2 instance"
}

# Main script logic
case "${1:-}" in
    "migrate")
        migrate_database "$2" "$3"
        ;;
    "export")
        check_local_mongodb
        check_local_database
        export_local_database
        success "Export completed. Archive location: $BACKUP_DIR/mongodb_export_$TIMESTAMP.tar.gz"
        ;;
    "verify")
        verify_import "$2" "$3"
        ;;
    "help"|"-h"|"--help")
        show_usage
        ;;
    *)
        error "Invalid command: ${1:-}"
        echo
        show_usage
        exit 1
        ;;
esac
