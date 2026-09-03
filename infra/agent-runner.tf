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

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "agent_runner_execution" {
  count = var.enable_agent_runner ? 1 : 0

  name               = "${local.name_prefix}-agent-runner-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "agent_runner_execution" {
  count = var.enable_agent_runner ? 1 : 0

  role       = aws_iam_role.agent_runner_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Lecture du seul secret injecte dans la tache : la cle du modele. Aucun autre
# parametre n'est accessible, et aucun jeton GitHub n'entre dans la tache — le
# depot lui parvient par un snapshot S3 depose par le worker.
#
# Le second bloc autorise le tirage des images privees. Il ne s'agit pas d'un
# secret consomme par le conteneur : ECS le lit *avant* le pull, avec le role
# d'execution. Un identifiant de registre et un acces au code source sont deux
# choses distinctes, portees par deux mecanismes distincts.
resource "aws_iam_role_policy" "agent_runner_execution_secrets" {
  count = var.enable_agent_runner ? 1 : 0

  name = "${local.name_prefix}-agent-runner-secrets"
  role = aws_iam_role.agent_runner_execution[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Effect = "Allow"
          Action = ["ssm:GetParameters"]
          Resource = [
            "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/${local.name_prefix}/agent-runner/*"
          ]
        },
      ],
      var.agent_runner_private_images ? [
        {
          Effect = "Allow"
          Action = ["secretsmanager:GetSecretValue"]
          Resource = [
            aws_secretsmanager_secret.agent_runner_registry[0].arn
          ]
        },
      ] : [],
    )
  })
}

# ECS n'accepte que Secrets Manager pour `repositoryCredentials` : SSM n'est pas
# une source valide ici. Le contenu attendu est {"username":..,"password":..}.
resource "aws_secretsmanager_secret" "agent_runner_registry" {
  count = var.enable_agent_runner && var.agent_runner_private_images ? 1 : 0

  name                    = "${local.name_prefix}/agent-runner/registry"
  description             = "Identifiants de tirage des images privees des runs (GHCR)."
  recovery_window_in_days = 0
  tags                    = local.common_tags
}

resource "aws_secretsmanager_secret_version" "agent_runner_registry" {
  count = var.enable_agent_runner && var.agent_runner_private_images ? 1 : 0

  secret_id     = aws_secretsmanager_secret.agent_runner_registry[0].id
  secret_string = jsonencode({ username = "a-renseigner", password = "a-renseigner" })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_iam_role" "agent_runner_task" {
  count = var.enable_agent_runner ? 1 : 0

  name               = "${local.name_prefix}-agent-runner-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
  tags               = local.common_tags
}

# Lecture et ecriture sous `runs/`. Le conteneur init y lit ses entrees —
# snapshot du worktree, prompt, schema de sortie, deposes par le worker avant
# le lancement — et export y ecrit ses produits.
#
# LIMITE ASSUMEE : la portee est `runs/*`, pas le prefixe du run courant. IAM
# n'offre aucune cle de condition permettant de restreindre une tache ECS a un
# prefixe calcule au lancement, et un role par run serait disproportionne. Une
# tache qui devinerait la cle d'un autre run pourrait lire ou ecraser ses
# artefacts. La cle aleatoire (`run-` + 6 octets) rend la devinette
# impraticable mais ne constitue PAS une isolation IAM : ne pas ecrire
# ailleurs que la tache est confinee a son propre prefixe.
# `s3:DeleteObject` n'est deliberement pas accorde : une tache ne peut pas
# supprimer d'artefacts, seulement en ecrire.
resource "aws_iam_role_policy" "agent_runner_task_artifacts" {
  count = var.enable_agent_runner ? 1 : 0

  name = "${local.name_prefix}-agent-runner-artifacts"
  role = aws_iam_role.agent_runner_task[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:GetObject"]
      Resource = ["${aws_s3_bucket.agent_artifacts[0].arn}/runs/*"]
    }]
  })
}

data "archive_file" "agent_runner_sweeper" {
  type        = "zip"
  source_file = "${path.module}/lambda/agent-runner-sweeper/index.py"
  output_path = "${path.module}/.terraform/agent-runner-sweeper.zip"
}

resource "aws_lambda_function" "agent_runner_sweeper" {
  count = var.enable_agent_runner ? 1 : 0

  function_name    = "${local.name_prefix}-agent-runner-sweeper"
  role             = aws_iam_role.agent_runner_sweeper[0].arn
  handler          = "index.handler"
  runtime          = "python3.12"
  timeout          = 60
  filename         = data.archive_file.agent_runner_sweeper.output_path
  source_code_hash = data.archive_file.agent_runner_sweeper.output_base64sha256

  environment {
    variables = {
      CLUSTER_ARN      = aws_ecs_cluster.agent_runner[0].arn
      MAX_TASK_MINUTES = tostring(var.agent_runner_max_task_minutes)
    }
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_event_rule" "agent_runner_sweeper" {
  count = var.enable_agent_runner ? 1 : 0

  name                = "${local.name_prefix}-agent-runner-sweeper"
  schedule_expression = "rate(1 hour)"
  tags                = local.common_tags
}

resource "aws_cloudwatch_event_target" "agent_runner_sweeper" {
  count = var.enable_agent_runner ? 1 : 0

  rule      = aws_cloudwatch_event_rule.agent_runner_sweeper[0].name
  target_id = "lambda"
  arn       = aws_lambda_function.agent_runner_sweeper[0].arn
}

resource "aws_lambda_permission" "agent_runner_sweeper" {
  count = var.enable_agent_runner ? 1 : 0

  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.agent_runner_sweeper[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.agent_runner_sweeper[0].arn
}

# Modele : `aws_iam_role.night_scheduler_lambda`. Journal declare
# explicitement, pour que sa retention soit maitrisee comme celle des autres
# fonctions plutot que laissee a la creation implicite par Lambda.
resource "aws_iam_role" "agent_runner_sweeper" {
  count = var.enable_agent_runner ? 1 : 0

  name = "${local.name_prefix}-agent-runner-sweeper-role"

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

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-agent-runner-sweeper-role"
  })
}

resource "aws_cloudwatch_log_group" "agent_runner_sweeper" {
  count = var.enable_agent_runner ? 1 : 0

  name              = "/aws/lambda/${local.name_prefix}-agent-runner-sweeper"
  retention_in_days = var.agent_runner_log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-agent-runner-sweeper-logs"
  })
}

resource "aws_iam_role_policy" "agent_runner_sweeper_logs" {
  count = var.enable_agent_runner ? 1 : 0

  name = "${local.name_prefix}-agent-runner-sweeper-logs"
  role = aws_iam_role.agent_runner_sweeper[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.agent_runner_sweeper[0].arn}:*"
    }]
  })
}
resource "aws_iam_role_policy" "agent_runner_sweeper" {
  count = var.enable_agent_runner ? 1 : 0

  name = "${local.name_prefix}-agent-runner-sweeper"
  role = aws_iam_role.agent_runner_sweeper[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # `ListTasks` n'a pas de ressource au sens IAM : la restreindre a un ARN
      # la refuse purement et simplement. La portee se joue par la condition de
      # cluster — et c'est le smoke test, pas `terraform validate`, qui dira si
      # la cle est effectivement supportee pour cette action. Si elle ne l'est
      # pas, l'appel echoue en AccessDenied et la condition doit tomber : le
      # sweeper ne listerait alors que ce que `list_tasks(cluster=...)` lui
      # renvoie, ce qui reste borne par l'appel lui-meme.
      {
        Effect   = "Allow"
        Action   = ["ecs:ListTasks"]
        Resource = ["*"]
        Condition = {
          ArnEquals = {
            "ecs:cluster" = aws_ecs_cluster.agent_runner[0].arn
          }
        }
      },
      # `DescribeTasks` et `StopTask` portent sur des taches : la ressource est
      # une tache du cluster de runs, et rien d'autre. L'identifiant de tache
      # etant aleatoire, le caractere generique final est inevitable — le
      # segment de cluster, lui, ne l'est pas. Sans lui, cette Lambda pourrait
      # arreter n'importe quelle tache ECS du compte, y compris applicative.
      # La condition de cluster double la contrainte plutot que de s'y
      # substituer : les deux tiennent.
      {
        Effect = "Allow"
        Action = ["ecs:DescribeTasks", "ecs:StopTask"]
        Resource = [
          "${replace(aws_ecs_cluster.agent_runner[0].arn, ":cluster/", ":task/")}/*",
        ]
        Condition = {
          ArnEquals = {
            "ecs:cluster" = aws_ecs_cluster.agent_runner[0].arn
          }
        }
      },
    ]
  })
}

resource "aws_ssm_parameter" "agent_runner_openai_key" {
  count = var.enable_agent_runner ? 1 : 0

  name  = "/${local.name_prefix}/agent-runner/openai-api-key"
  type  = "SecureString"
  value = "a-renseigner-hors-terraform"

  lifecycle {
    ignore_changes = [value]
  }

  tags = local.common_tags
}
