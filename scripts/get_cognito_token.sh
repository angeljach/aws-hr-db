#!/bin/bash

# Helper script to get Cognito tokens

COGNITO_DOMAIN="${1}"
CLIENT_ID="${2}"
USERNAME="${3}"
PASSWORD="${4}"
REGION="${5:-us-east-1}"

if [ -z "$COGNITO_DOMAIN" ] || [ -z "$CLIENT_ID" ] || [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
    echo "Usage: $0 <COGNITO_DOMAIN> <CLIENT_ID> <USERNAME> <PASSWORD> [REGION]"
    echo ""
    echo "Example:"
    echo "$0 mydomain.auth.us-east-1.amazoncognito.com abc123xyz admin@example.com Password123!"
    exit 1
fi

echo "Getting token from Cognito..."
echo "Domain: $COGNITO_DOMAIN"
echo "Client ID: $CLIENT_ID"
echo "Username: $USERNAME"

curl -X POST "https://$COGNITO_DOMAIN/oauth2/token" \
  --data-urlencode "grant_type=password" \
  --data-urlencode "client_id=$CLIENT_ID" \
  --data-urlencode "username=$USERNAME" \
  --data-urlencode "password=$PASSWORD" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -v
