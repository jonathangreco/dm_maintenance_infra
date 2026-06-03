data "archive_file" "night_scheduler_lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/night-scheduler/index.py"
  output_path = "${path.module}/.terraform/night-scheduler.zip"
}

resource "aws_iam_role" "night_scheduler_lambda" {
  count = var.night_shutdown_enabled ? 1 : 0

  name = "${local.name_prefix}-night-scheduler-lambda-role"

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

  tags = {
    Name = "${local.name_prefix}-night-scheduler-lambda-role"
  }
}

resource "aws_iam_role_policy" "night_scheduler_lambda" {
  count = var.night_shutdown_enabled ? 1 : 0

  name = "${local.name_prefix}-night-scheduler-lambda-policy"
  role = aws_iam_role.night_scheduler_lambda[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.night_scheduler[0].arn}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:StartInstances",
          "ec2:StopInstances"
        ]
        Resource = aws_instance.app.arn
      },
      {
        Effect   = "Allow"
        Action   = "ec2:DescribeInstances"
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances",
          "rds:StartDBInstance",
          "rds:StopDBInstance"
        ]
        Resource = aws_db_instance.main.arn
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:SendCommand"
        ]
        Resource = [
          aws_instance.app.arn,
          "arn:aws:ssm:${var.aws_region}:*:document/AWS-RunShellScript"
        ]
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "night_scheduler" {
  count = var.night_shutdown_enabled ? 1 : 0

  name              = "/aws/lambda/${local.name_prefix}-night-scheduler"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = {
    Name = "${local.name_prefix}-night-scheduler-logs"
  }
}

resource "aws_lambda_function" "night_scheduler" {
  count = var.night_shutdown_enabled ? 1 : 0

  function_name    = "${local.name_prefix}-night-scheduler"
  role             = aws_iam_role.night_scheduler_lambda[0].arn
  handler          = "index.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.night_scheduler_lambda.output_path
  source_code_hash = data.archive_file.night_scheduler_lambda.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      APP_INSTANCE_ID = aws_instance.app.id
      DB_IDENTIFIER   = aws_db_instance.main.identifier
    }
  }

  tags = {
    Name = "${local.name_prefix}-night-scheduler"
  }
}

resource "aws_lambda_permission" "night_scheduler" {
  for_each = local.night_scheduler_schedules

  statement_id  = "AllowScheduler${replace(title(each.key), "-", "")}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.night_scheduler[0].function_name
  principal     = "scheduler.amazonaws.com"
  source_arn    = aws_scheduler_schedule.night_scheduler[each.key].arn
}

resource "aws_iam_role" "night_scheduler_eventbridge" {
  count = var.night_shutdown_enabled ? 1 : 0

  name = "${local.name_prefix}-night-scheduler-eventbridge-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "scheduler.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${local.name_prefix}-night-scheduler-eventbridge-role"
  }
}

resource "aws_iam_role_policy" "night_scheduler_eventbridge" {
  count = var.night_shutdown_enabled ? 1 : 0

  name = "${local.name_prefix}-night-scheduler-eventbridge-policy"
  role = aws_iam_role.night_scheduler_eventbridge[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = aws_lambda_function.night_scheduler[0].arn
      }
    ]
  })
}

locals {
  night_scheduler_schedules = var.night_shutdown_enabled ? {
    stop = {
      description = "Stop EC2 and RDS at night"
      expression  = var.night_shutdown_stop_schedule
      input       = jsonencode({ action = "stop" })
    }
    start-rds = {
      description = "Start RDS before the app EC2"
      expression  = var.night_shutdown_start_rds_schedule
      input       = jsonencode({ action = "start-rds" })
    }
    start-ec2 = {
      description = "Start the app EC2 after RDS"
      expression  = var.night_shutdown_start_ec2_schedule
      input       = jsonencode({ action = "start-ec2" })
    }
    refresh-app = {
      description = "Pull latest images and restart the app after EC2 startup"
      expression  = var.night_shutdown_refresh_app_schedule
      input       = jsonencode({ action = "refresh-app" })
    }
  } : {}
}

resource "aws_scheduler_schedule" "night_scheduler" {
  for_each = local.night_scheduler_schedules

  name                         = "${local.name_prefix}-night-${each.key}"
  description                  = each.value.description
  schedule_expression          = each.value.expression
  schedule_expression_timezone = var.night_shutdown_timezone
  state                        = "ENABLED"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.night_scheduler[0].arn
    role_arn = aws_iam_role.night_scheduler_eventbridge[0].arn
    input    = each.value.input

    retry_policy {
      maximum_event_age_in_seconds = 3600
      maximum_retry_attempts       = 2
    }
  }
}
