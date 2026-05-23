resource "aws_db_instance" "postgres" {
  identifier            = "${var.project_name}-postgres"
  allocated_storage     = 20
  db_name               = var.db_name
  engine                = "postgres"
  engine_version        = "18.4"
  instance_class        = "db.t3.micro"
  username              = var.db_user
  password              = var.db_password
  
  db_subnet_group_name   = var.db_subnet_group_id
  vpc_security_group_ids = [var.db_security_group]
  
  multi_az            = false
  publicly_accessible = false
  
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"
  
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.project_name}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  
  tags = {
    Name = "${var.project_name}-postgres"
  }
}

# Initialize database schema
resource "null_resource" "db_initialization" {
  provisioner "local-exec" {
    command = "aws rds describe-db-instances --db-instance-identifier ${aws_db_instance.postgres.identifier} --region ${data.aws_region.current.name} --query 'DBInstances[0].DBInstanceStatus' --output text | grep available"
    interpreter = ["bash", "-c"]
  }

  depends_on = [aws_db_instance.postgres]
}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}
