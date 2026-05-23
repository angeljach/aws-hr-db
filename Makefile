.PHONY: help build deploy destroy test invoke-extract clean

help:
	@echo "AWS HR Database - Available commands:"
	@echo ""
	@echo "Build & Deploy:"
	@echo "  make build          - Build Lambda functions"
	@echo "  make deploy         - Deploy infrastructure with Terraform"
	@echo "  make plan           - Show Terraform plan"
	@echo ""
	@echo "Operations:"
	@echo "  make invoke-extract - Invoke Extract Lambda"
	@echo "  make test           - Run tests"
	@echo ""
	@echo "Cleanup:"
	@echo "  make destroy        - Destroy all AWS resources"
	@echo "  make clean          - Remove build artifacts"
	@echo ""

build:
	@echo "Building Lambda functions..."
	@chmod +x scripts/build_lambdas.sh
	@scripts/build_lambdas.sh

deploy: build
	@echo "Deploying infrastructure..."
	@cd terraform && terraform init && terraform apply

plan:
	@echo "Running Terraform plan..."
	@cd terraform && terraform plan

invoke-extract:
	@echo "Invoking Extract Lambda..."
	@LAMBDA_NAME=$$(cd terraform && terraform output -raw extract_lambda_name 2>/dev/null || echo "aws-hr-db-extract"); \
	aws lambda invoke --function-name $$LAMBDA_NAME --invocation-type RequestResponse --payload '{}' response.json && \
	cat response.json && \
	echo ""

test:
	@echo "Running tests..."
	@echo "Tests not yet implemented"

destroy:
	@echo "WARNING: This will delete all AWS resources!"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		cd terraform && terraform destroy; \
	else \
		echo "Cancelled."; \
	fi

clean:
	@echo "Cleaning build artifacts..."
	@find lambda -name bootstrap -delete
	@rm -f response.json
	@echo "Done."

fmt:
	@echo "Formatting Terraform files..."
	@cd terraform && terraform fmt -recursive

validate:
	@echo "Validating Terraform..."
	@cd terraform && terraform validate

show-outputs:
	@echo "Terraform Outputs:"
	@cd terraform && terraform output

get-token:
	@echo "To get a Cognito token, run:"
	@COGNITO_DOMAIN=$$(cd terraform && terraform output -raw cognito_domain 2>/dev/null || echo "COGNITO_DOMAIN"); \
	echo "scripts/get_cognito_token.sh $$COGNITO_DOMAIN <CLIENT_ID> <USERNAME> <PASSWORD>"
