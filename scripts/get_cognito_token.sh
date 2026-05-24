#!/bin/bash

# Helper script to get a Cognito ID token via the cognito-idp InitiateAuth API.
# Uses curl against https://cognito-idp.<region>.amazonaws.com — the InitiateAuth
# call with USER_PASSWORD_AUTH is unauthenticated (no SigV4 needed) so we don't
# require the AWS CLI. We DO require jq for safe JSON encoding/decoding.
#
# Cognito's /oauth2/token endpoint does NOT support grant_type=password, so we
# call the cognito-idp service directly. USER_PASSWORD_AUTH is enabled in
# explicit_auth_flows in the Terraform Cognito module.
#
# Prints the IdToken to stdout on success. Errors (NotAuthorizedException,
# UserNotFoundException, etc.) are printed to stderr and the script exits 1.

set -euo pipefail

CLIENT_ID="${1:-}"
USERNAME="${2:-}"
PASSWORD="${3:-}"
REGION="${4:-us-east-1}"

if [ -z "$CLIENT_ID" ] || [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
    echo "Usage: $0 <CLIENT_ID> <USERNAME> <PASSWORD> [REGION]" >&2
    echo "" >&2
    echo "Example:" >&2
    echo "  $0 581u45n6i37jq65mo80bodj0v7 admin@example.com Password123!" >&2
    echo "" >&2
    echo "Requires: curl, jq" >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required but not installed (brew install jq)." >&2
    exit 1
fi

# Build the request body with jq so quotes/special chars in passwords are
# escaped correctly (don't string-interpolate user input into JSON by hand).
BODY=$(jq -n \
  --arg cid "$CLIENT_ID" \
  --arg u   "$USERNAME" \
  --arg p   "$PASSWORD" \
  '{AuthFlow:"USER_PASSWORD_AUTH",ClientId:$cid,AuthParameters:{USERNAME:$u,PASSWORD:$p}}')

RESPONSE=$(curl -sS -X POST "https://cognito-idp.${REGION}.amazonaws.com/" \
  -H "Content-Type: application/x-amz-json-1.1" \
  -H "X-Amz-Target: AWSCognitoIdentityProviderService.InitiateAuth" \
  --data-binary "$BODY")

TOKEN=$(echo "$RESPONSE" | jq -r '.AuthenticationResult.IdToken // empty')

if [ -z "$TOKEN" ]; then
    echo "ERROR: no IdToken in response for user '$USERNAME'." >&2
    echo "$RESPONSE" | jq . >&2
    exit 1
fi

echo "$TOKEN"
