# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for Lambda to access RDS and CloudWatch
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project_name}-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ]
        Resource = "*"
      }
    ]
  })
}

# Package Lambda binaries as ZIP for deployment
data "archive_file" "extract" {
  type        = "zip"
  source_file = "${path.module}/../../../lambda/extract_encrypt/bootstrap"
  output_path = "${path.module}/../../../lambda/extract_encrypt/bootstrap.zip"
}

data "archive_file" "query" {
  type        = "zip"
  source_file = "${path.module}/../../../lambda/query_decrypt/bootstrap"
  output_path = "${path.module}/../../../lambda/query_decrypt/bootstrap.zip"
}

# CloudWatch Log Group for Extract Lambda
resource "aws_cloudwatch_log_group" "extract_lambda" {
  name              = "/aws/lambda/${var.project_name}-extract"
  retention_in_days = 7
}

# CloudWatch Log Group for Query Lambda
resource "aws_cloudwatch_log_group" "query_lambda" {
  name              = "/aws/lambda/${var.project_name}-query"
  retention_in_days = 7
}

# Lambda Extract & Encrypt
resource "aws_lambda_function" "extract" {
  filename         = data.archive_file.extract.output_path
  source_code_hash = data.archive_file.extract.output_base64sha256
  function_name    = "${var.project_name}-extract"
  role             = aws_iam_role.lambda_role.arn
  handler          = "bootstrap"
  runtime          = var.lambda_runtime
  timeout          = 60
  memory_size      = 256

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_security_group]
  }

  environment {
    variables = {
      DB_HOST         = var.db_host
      DB_PORT         = "5432"
      DB_NAME         = var.db_name
      DB_USER         = var.db_user
      DB_PASSWORD     = var.db_password
      ENCRYPTION_KEY = var.encryption_key
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.extract_lambda
  ]
}

# Lambda Query & Decrypt
resource "aws_lambda_function" "query" {
  filename         = data.archive_file.query.output_path
  source_code_hash = data.archive_file.query.output_base64sha256
  function_name    = "${var.project_name}-query"
  role             = aws_iam_role.lambda_role.arn
  handler          = "bootstrap"
  runtime          = var.lambda_runtime
  timeout          = 30
  memory_size      = 256

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_security_group]
  }

  environment {
    variables = {
      DB_HOST         = var.db_host
      DB_PORT         = "5432"
      DB_NAME         = var.db_name
      DB_USER         = var.db_user
      DB_PASSWORD     = var.db_password
      ENCRYPTION_KEY = var.encryption_key
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.query_lambda
  ]
}

data "aws_region" "current" {}
