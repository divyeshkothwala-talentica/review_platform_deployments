#!/bin/bash

# Comprehensive Backend API Testing Script
# This script tests all backend API endpoints after deployment

set -e

# Configuration
API_BASE_URL=""
TEST_USER_EMAIL="test-$(date +%s)@example.com"
TEST_USER_PASSWORD="TestPassword123!"
TEST_USER_USERNAME="testuser$(date +%s)"
AUTH_TOKEN=""
TEST_BOOK_ID=""
TEST_REVIEW_ID=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Logging functions
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[✅ PASS]${NC} $1"
    ((PASSED_TESTS++))
}

error() {
    echo -e "${RED}[❌ FAIL]${NC} $1"
    ((FAILED_TESTS++))
}

warning() {
    echo -e "${YELLOW}[⚠️ WARN]${NC} $1"
}

info() {
    echo -e "${CYAN}[ℹ️ INFO]${NC} $1"
}

test_header() {
    echo
    echo -e "${PURPLE}=== $1 ===${NC}"
    echo
}

# Function to make HTTP requests with error handling
make_request() {
    local method=$1
    local endpoint=$2
    local data=$3
    local headers=$4
    local expected_status=${5:-200}
    
    ((TOTAL_TESTS++))
    
    local url="$API_BASE_URL$endpoint"
    local curl_cmd="curl -s -w '%{http_code}' -X $method"
    
    if [ -n "$headers" ]; then
        curl_cmd="$curl_cmd $headers"
    fi
    
    if [ -n "$data" ]; then
        curl_cmd="$curl_cmd -d '$data'"
    fi
    
    curl_cmd="$curl_cmd '$url'"
    
    log "Testing: $method $endpoint"
    info "Command: $curl_cmd"
    
    # Execute request
    local response=$(eval $curl_cmd)
    local status_code="${response: -3}"
    local body="${response%???}"
    
    # Check status code
    if [ "$status_code" -eq "$expected_status" ]; then
        success "$method $endpoint - Status: $status_code"
        echo "$body" | jq '.' 2>/dev/null || echo "$body"
        echo "$body"
        return 0
    else
        error "$method $endpoint - Expected: $expected_status, Got: $status_code"
        echo "Response: $body"
        return 1
    fi
}

# Function to extract value from JSON response
extract_json_value() {
    local json=$1
    local key=$2
    echo "$json" | jq -r "$key // empty" 2>/dev/null
}

# Test health endpoints
test_health_endpoints() {
    test_header "Health & System Endpoints"
    
    # Basic health check
    local response=$(make_request "GET" "/health")
    if [ $? -eq 0 ]; then
        local status=$(extract_json_value "$response" ".data.status")
        if [ "$status" = "healthy" ]; then
            success "Health endpoint returns healthy status"
        else
            warning "Health endpoint status: $status"
        fi
    fi
    
    # Readiness probe
    make_request "GET" "/health/ready"
    
    # Liveness probe
    make_request "GET" "/health/live"
    
    # API version
    make_request "GET" "/api/v1"
}

# Test authentication endpoints
test_authentication() {
    test_header "Authentication Endpoints"
    
    # Test user registration
    local register_data="{
        \"username\": \"$TEST_USER_USERNAME\",
        \"email\": \"$TEST_USER_EMAIL\",
        \"password\": \"$TEST_USER_PASSWORD\"
    }"
    
    local register_response=$(make_request "POST" "/api/v1/auth/register" "$register_data" "-H 'Content-Type: application/json'" 201)
    
    if [ $? -eq 0 ]; then
        local user_id=$(extract_json_value "$register_response" ".data.user._id")
        if [ -n "$user_id" ]; then
            success "User registration successful - User ID: $user_id"
        fi
    fi
    
    # Test user login
    local login_data="{
        \"email\": \"$TEST_USER_EMAIL\",
        \"password\": \"$TEST_USER_PASSWORD\"
    }"
    
    local login_response=$(make_request "POST" "/api/v1/auth/login" "$login_data" "-H 'Content-Type: application/json'")
    
    if [ $? -eq 0 ]; then
        AUTH_TOKEN=$(extract_json_value "$login_response" ".data.token")
        if [ -n "$AUTH_TOKEN" ]; then
            success "User login successful - Token obtained"
            info "Auth token: ${AUTH_TOKEN:0:20}..."
        else
            error "Login successful but no token received"
        fi
    fi
    
    # Test token validation (profile endpoint)
    if [ -n "$AUTH_TOKEN" ]; then
        make_request "GET" "/api/v1/auth/profile" "" "-H 'Authorization: Bearer $AUTH_TOKEN'"
    fi
    
    # Test invalid login
    local invalid_login_data="{
        \"email\": \"invalid@example.com\",
        \"password\": \"wrongpassword\"
    }"
    
    make_request "POST" "/api/v1/auth/login" "$invalid_login_data" "-H 'Content-Type: application/json'" 401
}

# Test books endpoints
test_books_api() {
    test_header "Books API Endpoints"
    
    # Get all books
    local books_response=$(make_request "GET" "/api/v1/books")
    if [ $? -eq 0 ]; then
        TEST_BOOK_ID=$(extract_json_value "$books_response" ".data[0]._id")
        if [ -n "$TEST_BOOK_ID" ]; then
            success "Books list retrieved - First book ID: $TEST_BOOK_ID"
        fi
    fi
    
    # Get books with pagination
    make_request "GET" "/api/v1/books?skip=0&limit=5"
    
    # Search books
    make_request "GET" "/api/v1/books/search?q=test"
    
    # Get books by genre (if supported)
    make_request "GET" "/api/v1/books?genre=fiction"
    
    # Get book by ID
    if [ -n "$TEST_BOOK_ID" ]; then
        make_request "GET" "/api/v1/books/$TEST_BOOK_ID"
    else
        warning "No book ID available for individual book test"
    fi
    
    # Test invalid book ID
    make_request "GET" "/api/v1/books/invalid-id" "" "" 404
}

# Test reviews endpoints
test_reviews_api() {
    test_header "Reviews API Endpoints"
    
    # Get all reviews
    local reviews_response=$(make_request "GET" "/api/v1/reviews")
    if [ $? -eq 0 ]; then
        TEST_REVIEW_ID=$(extract_json_value "$reviews_response" ".data[0]._id")
    fi
    
    # Get reviews with pagination
    make_request "GET" "/api/v1/reviews?skip=0&limit=5"
    
    # Get reviews for a specific book
    if [ -n "$TEST_BOOK_ID" ]; then
        make_request "GET" "/api/v1/reviews?bookId=$TEST_BOOK_ID"
    fi
    
    # Create a review (requires authentication)
    if [ -n "$AUTH_TOKEN" ] && [ -n "$TEST_BOOK_ID" ]; then
        local review_data="{
            \"bookId\": \"$TEST_BOOK_ID\",
            \"rating\": 5,
            \"comment\": \"Excellent book! This is a test review from automated testing.\"
        }"
        
        local create_review_response=$(make_request "POST" "/api/v1/reviews" "$review_data" "-H 'Content-Type: application/json' -H 'Authorization: Bearer $AUTH_TOKEN'" 201)
        
        if [ $? -eq 0 ]; then
            TEST_REVIEW_ID=$(extract_json_value "$create_review_response" ".data._id")
            if [ -n "$TEST_REVIEW_ID" ]; then
                success "Review created successfully - Review ID: $TEST_REVIEW_ID"
            fi
        fi
    else
        warning "Skipping review creation - missing auth token or book ID"
    fi
    
    # Get review by ID
    if [ -n "$TEST_REVIEW_ID" ]; then
        make_request "GET" "/api/v1/reviews/$TEST_REVIEW_ID"
    fi
    
    # Update review (if we created one)
    if [ -n "$AUTH_TOKEN" ] && [ -n "$TEST_REVIEW_ID" ]; then
        local update_data="{
            \"rating\": 4,
            \"comment\": \"Updated review comment from automated testing.\"
        }"
        
        make_request "PUT" "/api/v1/reviews/$TEST_REVIEW_ID" "$update_data" "-H 'Content-Type: application/json' -H 'Authorization: Bearer $AUTH_TOKEN'"
    fi
    
    # Test unauthorized review creation
    if [ -n "$TEST_BOOK_ID" ]; then
        local unauthorized_review="{
            \"bookId\": \"$TEST_BOOK_ID\",
            \"rating\": 3,
            \"comment\": \"This should fail without auth\"
        }"
        
        make_request "POST" "/api/v1/reviews" "$unauthorized_review" "-H 'Content-Type: application/json'" 401
    fi
}

# Test favorites endpoints
test_favorites_api() {
    test_header "Favorites API Endpoints"
    
    if [ -z "$AUTH_TOKEN" ]; then
        warning "Skipping favorites tests - no authentication token"
        return
    fi
    
    # Get user favorites
    make_request "GET" "/api/v1/favorites" "" "-H 'Authorization: Bearer $AUTH_TOKEN'"
    
    # Add book to favorites
    if [ -n "$TEST_BOOK_ID" ]; then
        local favorite_data="{\"bookId\": \"$TEST_BOOK_ID\"}"
        make_request "POST" "/api/v1/favorites" "$favorite_data" "-H 'Content-Type: application/json' -H 'Authorization: Bearer $AUTH_TOKEN'" 201
        
        # Check if book is now in favorites
        local favorites_response=$(make_request "GET" "/api/v1/favorites" "" "-H 'Authorization: Bearer $AUTH_TOKEN'")
        if [ $? -eq 0 ]; then
            local favorite_count=$(extract_json_value "$favorites_response" ".data | length")
            if [ "$favorite_count" -gt 0 ]; then
                success "Book added to favorites successfully"
            fi
        fi
        
        # Remove book from favorites
        make_request "DELETE" "/api/v1/favorites/$TEST_BOOK_ID" "" "-H 'Authorization: Bearer $AUTH_TOKEN'"
    fi
    
    # Test unauthorized access
    make_request "GET" "/api/v1/favorites" "" "" 401
}

# Test recommendations endpoints
test_recommendations_api() {
    test_header "Recommendations API Endpoints"
    
    if [ -z "$AUTH_TOKEN" ]; then
        warning "Skipping recommendations tests - no authentication token"
        return
    fi
    
    # Get recommendations
    make_request "GET" "/api/v1/recommendations" "" "-H 'Authorization: Bearer $AUTH_TOKEN'"
    
    # Get recommendations with parameters
    make_request "GET" "/api/v1/recommendations?limit=5" "" "-H 'Authorization: Bearer $AUTH_TOKEN'"
    
    # Test recommendation feedback (if endpoint exists)
    local feedback_data="{
        \"recommendationId\": \"test-rec-id\",
        \"feedback\": \"helpful\",
        \"rating\": 5
    }"
    
    # This might return 404 if not implemented, which is okay
    make_request "POST" "/api/v1/recommendations/feedback" "$feedback_data" "-H 'Content-Type: application/json' -H 'Authorization: Bearer $AUTH_TOKEN'" 201 || true
    
    # Test unauthorized access
    make_request "GET" "/api/v1/recommendations" "" "" 401
}

# Test user profile endpoints
test_user_profile() {
    test_header "User Profile Endpoints"
    
    if [ -z "$AUTH_TOKEN" ]; then
        warning "Skipping user profile tests - no authentication token"
        return
    fi
    
    # Get user profile
    local profile_response=$(make_request "GET" "/api/v1/users/profile" "" "-H 'Authorization: Bearer $AUTH_TOKEN'")
    
    # Update user profile
    local update_data="{
        \"bio\": \"Updated bio from automated testing\",
        \"favoriteGenres\": [\"fiction\", \"mystery\"]
    }"
    
    make_request "PUT" "/api/v1/users/profile" "$update_data" "-H 'Content-Type: application/json' -H 'Authorization: Bearer $AUTH_TOKEN'"
    
    # Get updated profile
    make_request "GET" "/api/v1/users/profile" "" "-H 'Authorization: Bearer $AUTH_TOKEN'"
    
    # Test unauthorized access
    make_request "GET" "/api/v1/users/profile" "" "" 401
}

# Test error handling
test_error_handling() {
    test_header "Error Handling & Edge Cases"
    
    # Test non-existent endpoints
    make_request "GET" "/api/v1/nonexistent" "" "" 404
    
    # Test malformed JSON
    make_request "POST" "/api/v1/auth/login" "invalid-json" "-H 'Content-Type: application/json'" 400
    
    # Test missing required fields
    local incomplete_data="{\"email\": \"test@example.com\"}"
    make_request "POST" "/api/v1/auth/login" "$incomplete_data" "-H 'Content-Type: application/json'" 400
    
    # Test invalid HTTP methods
    make_request "PATCH" "/health" "" "" 405 || make_request "PATCH" "/health" "" "" 404
}

# Test rate limiting (if implemented)
test_rate_limiting() {
    test_header "Rate Limiting Tests"
    
    info "Testing rate limiting by making rapid requests..."
    
    local rate_limit_hit=false
    for i in {1..20}; do
        local response=$(curl -s -w '%{http_code}' "$API_BASE_URL/health")
        local status_code="${response: -3}"
        
        if [ "$status_code" -eq 429 ]; then
            success "Rate limiting is working - got 429 status"
            rate_limit_hit=true
            break
        fi
        
        sleep 0.1
    done
    
    if [ "$rate_limit_hit" = false ]; then
        warning "Rate limiting not detected (this may be expected)"
    fi
}

# Performance tests
test_performance() {
    test_header "Basic Performance Tests"
    
    info "Testing response times..."
    
    # Test health endpoint performance
    local start_time=$(date +%s%N)
    make_request "GET" "/health" > /dev/null 2>&1
    local end_time=$(date +%s%N)
    local duration=$(( (end_time - start_time) / 1000000 ))
    
    if [ $duration -lt 1000 ]; then
        success "Health endpoint response time: ${duration}ms (< 1s)"
    else
        warning "Health endpoint response time: ${duration}ms (>= 1s)"
    fi
    
    # Test books endpoint performance
    start_time=$(date +%s%N)
    make_request "GET" "/api/v1/books?limit=10" > /dev/null 2>&1
    end_time=$(date +%s%N)
    duration=$(( (end_time - start_time) / 1000000 ))
    
    if [ $duration -lt 2000 ]; then
        success "Books endpoint response time: ${duration}ms (< 2s)"
    else
        warning "Books endpoint response time: ${duration}ms (>= 2s)"
    fi
}

# Generate test report
generate_report() {
    test_header "Test Summary Report"
    
    local success_rate=0
    if [ $TOTAL_TESTS -gt 0 ]; then
        success_rate=$(( (PASSED_TESTS * 100) / TOTAL_TESTS ))
    fi
    
    echo
    echo "=== BACKEND API TEST RESULTS ==="
    echo "API Base URL: $API_BASE_URL"
    echo "Test Execution Time: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
    echo
    echo "📊 Test Statistics:"
    echo "  Total Tests: $TOTAL_TESTS"
    echo "  Passed: $PASSED_TESTS"
    echo "  Failed: $FAILED_TESTS"
    echo "  Success Rate: $success_rate%"
    echo
    
    if [ $FAILED_TESTS -eq 0 ]; then
        echo -e "${GREEN}🎉 ALL TESTS PASSED!${NC}"
        echo "The backend API is functioning correctly."
    elif [ $success_rate -ge 80 ]; then
        echo -e "${YELLOW}⚠️ MOSTLY SUCCESSFUL${NC}"
        echo "Most tests passed, but some issues were found."
    else
        echo -e "${RED}❌ SIGNIFICANT ISSUES FOUND${NC}"
        echo "Multiple tests failed. Please review the API implementation."
    fi
    
    echo
    echo "=== Test Categories ==="
    echo "✅ Health & System Endpoints"
    echo "✅ Authentication"
    echo "✅ Books API"
    echo "✅ Reviews API"
    echo "✅ Favorites API"
    echo "✅ Recommendations API"
    echo "✅ User Profile"
    echo "✅ Error Handling"
    echo "✅ Rate Limiting"
    echo "✅ Performance"
    echo
    
    # Create detailed report file
    cat > api-test-report.json << EOF
{
  "test_summary": {
    "api_base_url": "$API_BASE_URL",
    "execution_time": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "total_tests": $TOTAL_TESTS,
    "passed_tests": $PASSED_TESTS,
    "failed_tests": $FAILED_TESTS,
    "success_rate": $success_rate
  },
  "test_user": {
    "email": "$TEST_USER_EMAIL",
    "username": "$TEST_USER_USERNAME",
    "auth_token_obtained": $([ -n "$AUTH_TOKEN" ] && echo "true" || echo "false")
  },
  "test_data": {
    "book_id_used": "$TEST_BOOK_ID",
    "review_id_created": "$TEST_REVIEW_ID"
  }
}
EOF
    
    success "Detailed test report saved to: api-test-report.json"
}

# Cleanup function
cleanup() {
    test_header "Cleanup"
    
    if [ -n "$AUTH_TOKEN" ] && [ -n "$TEST_REVIEW_ID" ]; then
        info "Cleaning up test review..."
        make_request "DELETE" "/api/v1/reviews/$TEST_REVIEW_ID" "" "-H 'Authorization: Bearer $AUTH_TOKEN'" || true
    fi
    
    info "Test cleanup completed"
}

# Main function
main() {
    local api_url=$1
    
    if [ -z "$api_url" ]; then
        echo "Usage: $0 <api_base_url>"
        echo "Example: $0 http://54.123.45.67:5000"
        exit 1
    fi
    
    # Remove trailing slash
    API_BASE_URL="${api_url%/}"
    
    echo
    echo "🧪 Starting Comprehensive Backend API Tests"
    echo "API Base URL: $API_BASE_URL"
    echo "Test User: $TEST_USER_EMAIL"
    echo "Timestamp: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
    echo
    
    # Check if API is reachable
    if ! curl -f --connect-timeout 10 --max-time 30 "$API_BASE_URL/health" > /dev/null 2>&1; then
        error "API is not reachable at $API_BASE_URL"
        echo "Please ensure the backend is running and accessible."
        exit 1
    fi
    
    success "API is reachable, starting tests..."
    
    # Run all test suites
    test_health_endpoints
    test_authentication
    test_books_api
    test_reviews_api
    test_favorites_api
    test_recommendations_api
    test_user_profile
    test_error_handling
    test_rate_limiting
    test_performance
    
    # Generate report
    generate_report
    
    # Cleanup
    cleanup
    
    # Exit with appropriate code
    if [ $FAILED_TESTS -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

# Handle script interruption
trap cleanup EXIT

# Run main function
main "$@"
