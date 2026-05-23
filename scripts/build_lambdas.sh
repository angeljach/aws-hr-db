#!/bin/bash

# Script to build Lambda functions for AWS Lambda

set -e

echo "Building Extract & Encrypt Lambda..."
cd lambda/extract_encrypt

# Download dependencies
go mod download
go mod tidy

# Build for Amazon Linux 2
GOOS=linux GOARCH=amd64 go build -o bootstrap main.go

# Verify the binary was created
if [ ! -f bootstrap ]; then
  echo "Error: bootstrap binary not created"
  exit 1
fi

echo "Extract Lambda built successfully"

cd ../..

echo "Building Query & Decrypt Lambda..."
cd lambda/query_decrypt

# Download dependencies
go mod download
go mod tidy

# Build for Amazon Linux 2
GOOS=linux GOARCH=amd64 go build -o bootstrap main.go

# Verify the binary was created
if [ ! -f bootstrap ]; then
  echo "Error: bootstrap binary not created"
  exit 1
fi

echo "Query Lambda built successfully"

cd ../..

echo "All Lambda functions built successfully!"
