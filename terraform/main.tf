terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "Terraform"
    }
  }
}

# VPC y Networking
module "vpc" {
  source = "./modules/vpc"

  project_name = var.project_name
  aws_region   = var.aws_region
  
  vpc_cidr = "10.0.0.0/16"
  
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
}

# RDS PostgreSQL
module "rds" {
  source = "./modules/rds"

  project_name = var.project_name
  
  db_name     = var.db_name
  db_user     = var.db_user
  db_password = var.db_password
  
  vpc_id              = module.vpc.vpc_id
  db_subnet_group_id  = module.vpc.db_subnet_group_id
  db_security_group   = module.vpc.db_security_group_id
  
  depends_on = [module.vpc]
}

# Lambda Functions
module "lambda" {
  source = "./modules/lambda"

  project_name = var.project_name
  aws_region   = var.aws_region
  
  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  lambda_security_group = module.vpc.lambda_security_group_id
  
  db_host      = module.rds.db_address
  db_name      = var.db_name
  db_user      = var.db_user
  db_password  = var.db_password
  encryption_key = var.encryption_key
  
  depends_on = [module.rds]
}

# Cognito
module "cognito" {
  source = "./modules/cognito"

  project_name = var.project_name
  
  admin_user    = var.cognito_admin_user
  admin_password = var.cognito_admin_password
  limited_user  = var.cognito_limited_user
  limited_password = var.cognito_limited_password
  premium_user  = var.cognito_premium_user
  premium_password = var.cognito_premium_password
}

# API Gateway
module "api_gateway" {
  source = "./modules/api_gateway"

  project_name = var.project_name
  api_stage    = var.api_stage
  
  query_lambda_arn        = module.lambda.query_lambda_arn
  query_lambda_invoke_arn = module.lambda.query_lambda_invoke_arn
  query_lambda_name       = module.lambda.query_lambda_name
  
  cognito_user_pool_id = module.cognito.user_pool_id
  cognito_user_pool_arn = module.cognito.user_pool_arn
  
  depends_on = [module.lambda, module.cognito]
}
