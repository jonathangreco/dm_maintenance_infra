data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_iam_role" "app_ec2" {
  name = "${local.name_prefix}-app-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${local.name_prefix}-app-ec2-role"
  }
}

resource "aws_iam_role_policy_attachment" "app_ec2_ssm" {
  role       = aws_iam_role.app_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "app_ec2_ssm_parameters_read" {
  name = "${local.name_prefix}-app-ec2-ssm-parameters-read"
  role = aws_iam_role.app_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter"
        ]
        Resource = [
          "arn:aws:ssm:${var.aws_region}:*:parameter${var.ghcr_token_ssm_parameter_name}",
          "arn:aws:ssm:${var.aws_region}:*:parameter${var.app_env_ssm_parameter_name}"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "app_ec2_cloudwatch_logs" {
  name = "${local.name_prefix}-app-ec2-cloudwatch-logs"
  role = aws_iam_role.app_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.ec2.arn}:*",
          "${aws_cloudwatch_log_group.docker.arn}:*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "app" {
  name = "${local.name_prefix}-app-instance-profile"
  role = aws_iam_role.app_ec2.name
}

resource "aws_key_pair" "app" {
  count = var.enable_ssh ? 1 : 0

  key_name   = "${local.name_prefix}-app-key"
  public_key = var.ssh_public_key != null ? var.ssh_public_key : file(pathexpand(var.ssh_public_key_path))

  tags = {
    Name = "${local.name_prefix}-app-key"
  }
}

resource "aws_instance" "app" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.app_instance_type
  key_name                    = var.enable_ssh ? aws_key_pair.app[0].key_name : null
  subnet_id                   = var.app_subnet_tier == "public" ? aws_subnet.public["0"].id : aws_subnet.private_app["0"].id
  vpc_security_group_ids      = [aws_security_group.app.id]
  iam_instance_profile        = aws_iam_instance_profile.app.name
  user_data_replace_on_change = true

  user_data = templatefile("${path.module}/user_data_app.sh.tftpl", {
    app_env_ssm_parameter_name    = var.app_env_ssm_parameter_name
    ghcr_login_enabled            = var.ghcr_login_enabled
    ghcr_token_ssm_parameter_name = var.ghcr_token_ssm_parameter_name
    ghcr_username                 = var.ghcr_username
    app_image                     = var.app_container_image
    nginx_image                   = var.app_nginx_image
    nginx_port                    = var.app_port
    aws_region                    = var.aws_region
    ec2_log_group_name            = aws_cloudwatch_log_group.ec2.name
    docker_log_group_name         = aws_cloudwatch_log_group.docker.name
    compose_file                  = templatefile("${path.module}/docker-compose.prod.yml.tftpl", {})
    default_uri                   = "http://${aws_lb.app.dns_name}"
    trusted_proxies               = var.vpc_cidr
    mail_from                     = var.mail_from
    analyzer_cluster              = var.enable_agent_runner ? aws_ecs_cluster.agent_runner[0].name : ""
    analyzer_subnets              = join(",", [for subnet in aws_subnet.public : subnet.id])
    analyzer_security_group       = var.enable_agent_runner ? aws_security_group.agent_runner[0].id : ""
    analyzer_bucket               = var.enable_agent_runner ? aws_s3_bucket.agent_artifacts[0].bucket : ""
    documents_bucket              = aws_s3_bucket.documents.bucket
  })

  tags = {
    Name = "${local.name_prefix}-app-ec2"
  }

  depends_on = [aws_db_instance.main]
}

resource "aws_lb_target_group_attachment" "app" {
  target_group_arn = aws_lb_target_group.app.arn
  target_id        = aws_instance.app.id
  port             = var.app_port
}

resource "aws_iam_role_policy" "app_ec2_agent_runner" {
  count = var.enable_agent_runner ? 1 : 0

  name = "${local.name_prefix}-app-agent-runner"
  role = aws_iam_role.app_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Les definitions de taches sont declarees par Terraform
      # (analyzer-tasks.tf) : l'application ne fait que les lancer.
      {
        Effect = "Allow"
        Action = ["ecs:RunTask"]
        Resource = [
          for family in keys(aws_ecs_task_definition.analyzer) :
          "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:task-definition/${family}:*"
        ]
        Condition = {
          ArnEquals = {
            "ecs:cluster" = aws_ecs_cluster.agent_runner[0].arn
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["ecs:DescribeTasks"]
        Resource = ["${replace(aws_ecs_cluster.agent_runner[0].arn, ":cluster/", ":task/")}/*"]
        Condition = {
          ArnEquals = {
            "ecs:cluster" = aws_ecs_cluster.agent_runner[0].arn
          }
        }
      },
      {
        Effect = "Allow"
        Action = ["iam:PassRole"]
        Resource = [
          aws_iam_role.agent_runner_execution[0].arn,
          aws_iam_role.agent_runner_task[0].arn,
        ]
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ecs-tasks.amazonaws.com"
          }
        }
      },
      # Dossiers d'etape : l'application ecrit la demande, le bundle et les
      # secrets, lit la sortie ; jamais prepare/ (le code du client ne passe
      # pas par l'EC2). Flysystem envoie toujours une ACL
      # (bucket-owner-full-control), d'ou PutObjectAcl ; il ecrit aussi le
      # marqueur de dossier runs/<etape>/.
      {
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:PutObjectAcl", "s3:AbortMultipartUpload"]
        Resource = [
          "${aws_s3_bucket.agent_artifacts[0].arn}/runs/*/input/*",
          "${aws_s3_bucket.agent_artifacts[0].arn}/runs/*/secrets/*",
          "${aws_s3_bucket.agent_artifacts[0].arn}/runs/*/",
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObjectTagging"]
        Resource = ["${aws_s3_bucket.agent_artifacts[0].arn}/runs/*/secrets/*"]
      },
      {
        Effect = "Allow"
        Action = ["s3:GetObject"]
        Resource = [
          "${aws_s3_bucket.agent_artifacts[0].arn}/runs/*/input/*",
          "${aws_s3_bucket.agent_artifacts[0].arn}/runs/*/output/*",
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:DeleteObject"]
        Resource = ["${aws_s3_bucket.agent_artifacts[0].arn}/runs/*/secrets/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.agent_artifacts[0].arn]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:PutObjectAcl", "s3:AbortMultipartUpload", "s3:DeleteObject"]
        Resource = ["${aws_s3_bucket.documents.arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.documents.arn]
      },
    ]
  })
}
