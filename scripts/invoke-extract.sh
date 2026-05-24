#!/bin/bash

# Script to invoke the Extract Lambda function

set -e

LAMBDA_FUNCTION_NAME="${1:-aws-hr-db-extract}"
REGION="${2:-us-east-1}"

echo "Invoking Lambda function: $LAMBDA_FUNCTION_NAME"

aws lambda invoke \
  --region "$REGION" \
  --function-name "$LAMBDA_FUNCTION_NAME" \
  --invocation-type RequestResponse \
  --payload '{}' \
  response.json

echo "Lambda invocation response:"
cat response.json
echo ""
