resource "aws_cloudwatch_log_group" "ec2" {
  name              = "/${var.project_name}/${var.environment}/ec2"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = {
    Name = "${local.name_prefix}-ec2-logs"
  }
}

resource "aws_cloudwatch_log_group" "docker" {
  name              = "/${var.project_name}/${var.environment}/docker"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = {
    Name = "${local.name_prefix}-docker-logs"
  }
}
