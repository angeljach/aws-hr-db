resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.project_name}-api"
  description = "HR Database API Gateway"
}

# /employees resource
resource "aws_api_gateway_resource" "employees" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "employees"
}

# /employees/{id} resource
resource "aws_api_gateway_resource" "employee_id" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.employees.id
  path_part   = "{id}"
}

# GET /employees method
resource "aws_api_gateway_method" "get_employees" {
  rest_api_id      = aws_api_gateway_rest_api.main.id
  resource_id      = aws_api_gateway_resource.employees.id
  http_method      = "GET"
  authorization    = "COGNITO_USER_POOLS"
  authorizer_id    = aws_api_gateway_authorizer.cognito.id
  request_parameters = {
    "method.request.querystring.page"  = false
    "method.request.querystring.limit" = false
  }
}

# GET /employees/{id} method
resource "aws_api_gateway_method" "get_employee" {
  rest_api_id      = aws_api_gateway_rest_api.main.id
  resource_id      = aws_api_gateway_resource.employee_id.id
  http_method      = "GET"
  authorization    = "COGNITO_USER_POOLS"
  authorizer_id    = aws_api_gateway_authorizer.cognito.id
  request_parameters = {
    "method.request.path.id" = true
  }
}

# Lambda integration for GET /employees
resource "aws_api_gateway_integration" "employees_lambda" {
  rest_api_id      = aws_api_gateway_rest_api.main.id
  resource_id      = aws_api_gateway_resource.employees.id
  http_method      = aws_api_gateway_method.get_employees.http_method
  type             = "AWS_PROXY"
  integration_http_method = "POST"
  uri              = var.query_lambda_invoke_arn
}

# Lambda integration for GET /employees/{id}
resource "aws_api_gateway_integration" "employee_lambda" {
  rest_api_id      = aws_api_gateway_rest_api.main.id
  resource_id      = aws_api_gateway_resource.employee_id.id
  http_method      = aws_api_gateway_method.get_employee.http_method
  type             = "AWS_PROXY"
  integration_http_method = "POST"
  uri              = var.query_lambda_invoke_arn
}

# Cognito Authorizer
resource "aws_api_gateway_authorizer" "cognito" {
  name            = "${var.project_name}-cognito-authorizer"
  rest_api_id     = aws_api_gateway_rest_api.main.id
  type            = "COGNITO_USER_POOLS"
  provider_arns   = [var.cognito_user_pool_arn]
  identity_source = "method.request.header.Authorization"
}

# Lambda permission to invoke from API Gateway
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.query_lambda_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

# Deployment
resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id

  depends_on = [
    aws_api_gateway_integration.employees_lambda,
    aws_api_gateway_integration.employee_lambda
  ]
}

# Stage
resource "aws_api_gateway_stage" "main" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = var.api_stage
}

# CloudWatch Log Group for API Gateway
resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${var.project_name}"
  retention_in_days = 7
}
