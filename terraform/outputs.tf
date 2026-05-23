output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = module.rds.db_endpoint
}

output "api_gateway_url" {
  description = "API Gateway base URL"
  value       = module.api_gateway.api_url
}

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = module.cognito.user_pool_id
}

output "cognito_client_id" {
  description = "Cognito App Client ID"
  value       = module.cognito.client_id
}

output "cognito_domain" {
  description = "Cognito domain"
  value       = module.cognito.domain
}

output "extract_lambda_name" {
  description = "Extract Lambda function name"
  value       = module.lambda.extract_lambda_name
}

output "extract_lambda_arn" {
  description = "Extract Lambda function ARN"
  value       = module.lambda.extract_lambda_arn
}
