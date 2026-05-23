#!/bin/bash

# Script to build Lambda functions for AWS Lambda

set -e

echo "Building Extract & Encrypt Lambda..."

# Build from root using workspace (go build handles dependencies)
GOOS=linux GOARCH=amd64 go build -C lambda/extract_encrypt -o bootstrap main.go

# Verify the binary was created
if [ ! -f lambda/extract_encrypt/bootstrap ]; then
  echo "Error: extract_encrypt bootstrap binary not created"
  exit 1
fi

echo "Extract Lambda built successfully"

echo "Building Query & Decrypt Lambda..."

# Build from root using workspace (go build handles dependencies)
GOOS=linux GOARCH=amd64 go build -C lambda/query_decrypt -o bootstrap main.go

# Verify the binary was created
if [ ! -f lambda/query_decrypt/bootstrap ]; then
  echo "Error: query_decrypt bootstrap binary not created"
  exit 1
fi

echo "Query Lambda built successfully"

echo "All Lambda functions built successfully!"
