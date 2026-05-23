output "extract_lambda_name" {
  value = aws_lambda_function.extract.function_name
}

output "extract_lambda_arn" {
  value = aws_lambda_function.extract.arn
}

output "query_lambda_name" {
  value = aws_lambda_function.query.function_name
}

output "query_lambda_arn" {
  value = aws_lambda_function.query.arn
}
