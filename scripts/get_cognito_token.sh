#!/bin/bash

# Helper script to get a Cognito ID token via the cognito-idp InitiateAuth API.
# Cognito's /oauth2/token endpoint does NOT support grant_type=password, so we
# use USER_PASSWORD_AUTH directly (already enabled in explicit_auth_flows).
# Prints the IdToken to stdout — that's what the API Gateway Cognito User Pool
# authorizer validates and where the cognito:groups claim lives.

CLIENT_ID="${1}"
USERNAME="${2}"
PASSWORD="${3}"
REGION="${4:-us-east-1}"

if [ -z "$CLIENT_ID" ] || [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
    echo "Usage: $0 <CLIENT_ID> <USERNAME> <PASSWORD> [REGION]" >&2
    echo "" >&2
    echo "Example:" >&2
    echo "  $0 581u45n6i37jq65mo80bodj0v7 admin@example.com Password123!" >&2
    echo "" >&2
    echo "Tip: export TOKEN=\$($0 <CLIENT_ID> <USER> <PASS>)" >&2
    exit 1
fi

aws cognito-idp initiate-auth \
  --region "$REGION" \
  --auth-flow USER_PASSWORD_AUTH \
  --client-id "$CLIENT_ID" \
  --auth-parameters USERNAME="$USERNAME",PASSWORD="$PASSWORD" \
  --query 'AuthenticationResult.IdToken' \
  --output text
