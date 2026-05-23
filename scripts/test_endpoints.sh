#!/bin/bash

# Script to test API Gateway endpoints

set -e

API_URL="${1:-http://localhost:3000}"
ADMIN_TOKEN="${2:-}"
REGION="${3:-us-east-1}"

echo "Testing API Gateway endpoints..."
echo "API URL: $API_URL"

# Get authentication token if not provided
if [ -z "$ADMIN_TOKEN" ]; then
    echo "Getting authentication token from Cognito..."
    # This would be replaced with actual Cognito OAuth flow
    # For now, we'll show the curl command
    echo "Please get a token from Cognito and pass it as the second argument"
    echo "Example: ./test_endpoints.sh <API_URL> <TOKEN>"
    exit 1
fi

echo ""
echo "Testing GET /employees (with pagination)..."
curl -X GET "$API_URL/dev/employees?page=1&limit=10" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -v

echo ""
echo "Testing GET /employees/1..."
curl -X GET "$API_URL/dev/employees/1" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -v

echo ""
echo "Testing completed!"
