resource "aws_ecs_cluster" "agent_runner" {
  count = var.enable_agent_runner ? 1 : 0

  name = "${local.name_prefix}-agent-runner"

  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-agent-runner"
  })
}

# Aucune regle d'entree : la tache sort vers l'API du modele, GitHub, le registre
# et S3, mais reste injoignable depuis l'exterieur. Elle est placee dans les
# sous-reseaux publics pour eviter le cout fixe d'une passerelle NAT.
resource "aws_security_group" "agent_runner" {
  count = var.enable_agent_runner ? 1 : 0

  name        = "${local.name_prefix}-agent-runner"
  description = "Security group for ephemeral code agent tasks"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-agent-runner"
  })
}

resource "aws_security_group_rule" "agent_runner_egress" {
  count = var.enable_agent_runner ? 1 : 0

  security_group_id = aws_security_group.agent_runner[0].id
  type              = "egress"
  description       = "Allow all outbound"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_cloudwatch_log_group" "agent_runner" {
  count = var.enable_agent_runner ? 1 : 0

  name              = "/aws/ecs/${local.name_prefix}-agent-runner"
  retention_in_days = var.agent_runner_log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-agent-runner-logs"
  })
}

resource "aws_s3_bucket" "agent_artifacts" {
  count = var.enable_agent_runner ? 1 : 0

  # Un nom de bucket est global a tout AWS : le suffixe de compte suit la
  # convention deja etablie par infra/mysql-backups.tf.
  bucket = "dm-${var.environment}-agent-artifacts-${data.aws_caller_identity.current.account_id}"

  tags = merge(local.common_tags, {
    Name = "dm-${var.environment}-agent-artifacts-${data.aws_caller_identity.current.account_id}"
  })
}

resource "aws_s3_bucket_public_access_block" "agent_artifacts" {
  count = var.enable_agent_runner ? 1 : 0

  bucket                  = aws_s3_bucket.agent_artifacts[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Les artefacts de run sont consommes par le worker dans les minutes qui suivent.
resource "aws_s3_bucket_lifecycle_configuration" "agent_artifacts" {
  count = var.enable_agent_runner ? 1 : 0

  bucket = aws_s3_bucket.agent_artifacts[0].id

  rule {
    id     = "expire-run-artifacts"
    status = "Enabled"

    filter {
      prefix = "runs/"
    }

    expiration {
      days = 7
    }
  }
}
