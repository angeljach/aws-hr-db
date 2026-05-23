output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "lambda_security_group_id" {
  value = aws_security_group.lambda.id
}

output "db_security_group_id" {
  value = aws_security_group.rds.id
}

output "db_subnet_group_id" {
  value = aws_db_subnet_group.main.id
}
