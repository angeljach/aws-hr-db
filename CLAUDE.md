# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**AWS HR Database** is a serverless proof-of-concept that demonstrates secure employee data management with role-based access control. It's a complete AWS architecture (Terraform IaC) with Lambda functions (Go), PostgreSQL (RDS), Cognito authentication, and API Gateway, all designed to stay within the free tier.

**Key Components:**
- 2 Lambda functions (Go 1.21) for data extraction/encryption and querying/decryption
- PostgreSQL RDS in private subnets
- Cognito for authentication and role management (3 roles: admin, limited, premium)
- API Gateway exposing 2 endpoints with pagination
- AES-256-GCM client-side encryption (no KMS to minimize costs)

## Build & Deploy

### Building Lambda Functions

```bash
# Build all Lambdas (compiles to bootstrap binaries)
make build

# Or directly:
scripts/build_lambdas.sh
```

**Important**: The build script uses `go build -C` to respect the Go workspace configuration. If you modify the script, avoid using `cd` into Lambda directories, as this breaks workspace module resolution.

### Deploying Infrastructure

```bash
# Show what Terraform will do
make plan

# Deploy infrastructure (runs build first)
make deploy

# Terraform commands from terraform/ directory:
cd terraform
terraform init
terraform apply
```

### Key Build Artifacts

After building, these binaries are created:
- `lambda/extract_encrypt/bootstrap` (12MB)
- `lambda/query_decrypt/bootstrap` (12MB)

These are uploaded to Lambda during Terraform apply.

## Code Architecture

### Go Workspace Structure

The project uses a **Go workspace** (`go.work`) to manage local module dependencies:

```
go.work
├── use ./lambda/shared              # AES-256-GCM utilities
├── use ./lambda/extract_encrypt     # Extract & Encrypt Lambda
└── use ./lambda/query_decrypt       # Query & Decrypt Lambda
```

**Module Names** (defined in each go.mod):
- `local.aws-hr-db/shared`
- `local.aws-hr-db/lambda/extract_encrypt`
- `local.aws-hr-db/lambda/query_decrypt`

**⚠️ Critical**: Each module must have a unique name in the workspace. If you get "module appears multiple times" error, verify all go.mod files have distinct module names.

### Lambda Functions

#### Extract & Encrypt (`lambda/extract_encrypt/main.go`)

Inserts 20 dummy employee records with encrypted sensitive fields:
- **Input**: Empty (triggered manually or via schedule)
- **Output**: Count of inserted rows
- **Operations**:
  - Generates dummy employee data
  - Encrypts `phone`, `address`, `salary` using AES-256-GCM
  - Inserts into `employees` table via database connection string from environment

**Key Environment Variables**:
- `ENCRYPTION_KEY` - Hex-encoded 32-byte AES key
- `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD` - PostgreSQL connection

#### Query & Decrypt (`lambda/query_decrypt/main.go`)

Queries employees with role-based field filtering:
- **Input**: APIGatewayProxyRequest (from API Gateway)
- **Routes**:
  - `GET /employees` - List all with pagination (page, limit query params)
  - `GET /employees/{id}` - Get single employee
- **Output**: Decrypted fields filtered by user role (from Cognito claims)

**Role-Based Access**:
```go
var roleAccess = map[string][]string{
  "admin":   {"employee_id", "first_name", ..., "phone", "address", "salary"},
  "limited": {"employee_id", "first_name", "last_name", "email", "department", "hire_date"},
  "premium": {"employee_id", "first_name", ..., "phone"}, // no address/salary
}
```

**Key Environment Variables**:
- `ENCRYPTION_KEY` - For decryption
- Same database connection variables as extract function

#### Shared Encryption (`lambda/shared/crypto.go`)

Provides AES-256-GCM encryption/decryption:
- `EncryptAES256GCM(plaintext, key)` - Returns base64-encoded ciphertext
- `DecryptAES256GCM(ciphertext, key)` - Returns plaintext
- `GenerateEncryptionKey()` - Creates random 32-byte key as hex string

Both Lambdas import this module: `import "local.aws-hr-db/shared"`

### Terraform Architecture

**Modules** (terraform/modules/):
- **vpc**: Creates VPC (10.0.0.0/16) with public and private subnets, IGW, NAT
- **rds**: PostgreSQL 14 in private subnets with encrypted fields schema
- **lambda**: Defines both Lambda functions with environment variables, VPC config, IAM roles
- **cognito**: User pool with 3 test users (admin, limited, premium) and their groups
- **api_gateway**: REST API with 2 resources, Cognito authorizer, Lambda integrations

**Key Files**:
- `terraform/main.tf` - Instantiates all modules
- `terraform/locals.tf` - Shared values (naming, defaults)
- `terraform/variables.tf` - Input variables for customization
- `terraform/terraform.tfvars` - Configuration values (copy this from .tfvars.example if present)
- `terraform/outputs.tf` - Returns API URL, Lambda names, Cognito pool ID

**⚠️ Important**: Before deploying, update `terraform/terraform.tfvars` with:
- `db_password` (actual password, not default)
- `cognito_*_password` (actual test user passwords)
- `encryption_key` (generate with `openssl rand -hex 32`)

### Database Schema

Single table created automatically by Lambda on first run:
```sql
CREATE TABLE employees (
  employee_id SERIAL PRIMARY KEY,
  first_name, last_name, email, department, hire_date VARCHAR,
  phone_encrypted, address_encrypted, salary_encrypted VARCHAR(500),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
```

Encrypted fields are stored as base64-encoded ciphertext.

## Development Workflow

### Adding Features

1. **Go code changes**: Edit `lambda/*/main.go` or `lambda/shared/crypto.go`
2. **Rebuild binaries**: `make build`
3. **Redeploy**: `make deploy` (or just `terraform apply` if no Terraform changes)

### Testing Locally

Extract Lambda (insert dummy data):
```bash
make invoke-extract
```

Query Lambda requires Cognito token. Get one via:
```bash
scripts/get_cognito_token.sh <COGNITO_DOMAIN> <CLIENT_ID> <USERNAME> <PASSWORD>
```

Then call API:
```bash
curl -H "Authorization: Bearer $TOKEN" https://your-api-url/dev/employees
```

### Debugging

**Build failures**: Check that all Lambda directories have valid go.mod files and the workspace correctly lists them.

**Lambda execution errors**: Check CloudWatch logs:
```bash
aws logs tail /aws/lambda/aws-hr-db-extract --follow
```

**Database connection errors**: Verify RDS is running and security groups allow Lambda to connect (handled by Terraform module).

**Cognito token errors**: Ensure the user exists in the Cognito pool and belongs to the correct group (admin/limited/premium).

## Common Tasks

### Generating Encryption Key
```bash
openssl rand -hex 32
```

### Viewing Terraform State
```bash
cd terraform
terraform output -json
```

### Cleaning Up
```bash
make clean          # Remove bootstrap binaries and response.json
make destroy        # Destroy all AWS resources (with confirmation)
```

### Validating Terraform
```bash
cd terraform
terraform validate
terraform fmt -recursive  # Auto-format all .tf files
```

## Costs & Free Tier

**Included in AWS Free Tier:**
- RDS db.t3.micro: 750 hours/month
- Lambda: 1M invocations/month, 400,000 GB-seconds/month
- API Gateway: 1M requests/month
- Cognito: 50K monthly active users
- Data transfer: 1GB/month outbound

**Cost**: ~$0/month (within first 12 months), ~$20-25/month after free tier expires (mainly RDS).

## Troubleshooting

### "module local.aws-hr-db appears multiple times in workspace"
**Cause**: Two go.mod files have the same module name.
**Fix**: Ensure each Lambda's go.mod has a unique module name like `local.aws-hr-db/lambda/extract_encrypt`.

### Build script fails at "go mod download"
**Cause**: Workspace not recognized when using `cd` into subdirectories.
**Fix**: Use `go build -C` instead of `cd` (already fixed in build_lambdas.sh).

### Lambda execution timeout
**Cause**: RDS not accessible (security group issue) or encryption key missing.
**Fix**: Check security group allows port 5432, verify ENCRYPTION_KEY env var is set.

### Cognito token invalid
**Cause**: User doesn't exist in pool or group misconfigured.
**Fix**: Verify user in AWS Console or via:
```bash
aws cognito-idp list-users --user-pool-id <POOL_ID>
```

## References

- [AWS Lambda Go Runtime](https://docs.aws.amazon.com/lambda/latest/dg/golang-handler.html)
- [Go Workspaces](https://go.dev/doc/tutorial/workspaces)
- [API Gateway + Cognito](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-use-lambda-authorizer.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
