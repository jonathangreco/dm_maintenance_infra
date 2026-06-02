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
    compose_file                  = templatefile("${path.module}/docker-compose.prod.yml.tftpl", {})
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
