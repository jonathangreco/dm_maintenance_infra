# Darkmira Analyseur : une definition de tache par commande, lancee par
# l'EcsAnalyzerRunner de Darkmira Service (RunTask sur la famille
# darkmira-analyzer-<commande>, conteneur principal "analyzer"). Le dossier
# d'etape vit sous s3://<ANALYZER_BUCKET>/runs/<STEP_ID>/ :
# - init le rapatrie dans /step et place l'objet secrets dans /secrets ;
# - analyzer exporte les secrets (NOM=<base64>), efface leur fichier, puis
#   lance la commande ; l'image n'est pas modifiee ;
# - upload renvoie prepare/, work/ et output/ ; il est le seul conteneur
#   essentiel : la tache s'arrete a sa fin ;
# - progress (read seulement) renvoie output/progress.json toutes les 15 s.
# STEP_ID et SECRETS_KEY arrivent par les surcharges de RunTask, sur chaque
# conteneur.

locals {
  analyzer_commands = ["fetch", "install", "index", "plan", "read"]
  analyzer_families = var.enable_agent_runner ? { for command in local.analyzer_commands : "darkmira-analyzer-${command}" => command } : {}
  analyzer_bucket   = var.enable_agent_runner ? aws_s3_bucket.agent_artifacts[0].bucket : ""
  aws_cli_image     = "public.ecr.aws/aws-cli/aws-cli:2.31.0"
  analyzer_uid      = "10001"

  analyzer_init_script = <<-SCRIPT
    set -eu
    aws s3 cp --recursive --only-show-errors --exclude "secrets/*" "s3://${local.analyzer_bucket}/runs/$STEP_ID/" /step/
    if [ -n "$${SECRETS_KEY:-}" ]; then
      aws s3 cp --only-show-errors "s3://${local.analyzer_bucket}/$SECRETS_KEY" /secrets/analyzer.env
    fi
    chown -R ${local.analyzer_uid}:${local.analyzer_uid} /step /secrets
  SCRIPT

  analyzer_entry_script = <<-SCRIPT
    set -eu
    if [ -f /secrets/analyzer.env ]; then
      while IFS= read -r line; do
        name="$${line%%=*}"
        value="$${line#*=}"
        if [ -n "$name" ]; then
          export "$name=$(printf '%s' "$value" | base64 -d)"
        fi
      done < /secrets/analyzer.env
      rm -f /secrets/analyzer.env
    fi
    exec analyzer "$@"
  SCRIPT

  analyzer_upload_script = <<-SCRIPT
    set -eu
    for folder in prepare work output; do
      if [ -d "/step/$folder" ]; then
        aws s3 cp --recursive --only-show-errors "/step/$folder" "s3://${local.analyzer_bucket}/runs/$STEP_ID/$folder/"
      fi
    done
  SCRIPT

  analyzer_progress_script = <<-SCRIPT
    while true; do
      sleep 15
      if [ -f /step/output/progress.json ]; then
        aws s3 cp --only-show-errors /step/output/progress.json "s3://${local.analyzer_bucket}/runs/$STEP_ID/output/progress.json" || true
      fi
    done
  SCRIPT

  analyzer_mounts = [
    { sourceVolume = "step", containerPath = "/step", readOnly = false },
    { sourceVolume = "secrets", containerPath = "/secrets", readOnly = false },
  ]
}

resource "aws_ecs_task_definition" "analyzer" {
  for_each = local.analyzer_families

  family                   = each.key
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.analyzer_task_cpu
  memory                   = var.analyzer_task_memory_mib
  execution_role_arn       = aws_iam_role.agent_runner_execution[0].arn
  task_role_arn            = aws_iam_role.agent_runner_task[0].arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  ephemeral_storage {
    size_in_gib = 21
  }

  volume {
    name = "step"
  }

  volume {
    name = "secrets"
  }

  container_definitions = jsonencode(concat(
    [
      {
        name        = "init"
        image       = local.aws_cli_image
        essential   = false
        entryPoint  = ["/bin/sh", "-c"]
        command     = [local.analyzer_init_script]
        mountPoints = local.analyzer_mounts
        logConfiguration = {
          logDriver = "awslogs"
          options = {
            awslogs-group         = aws_cloudwatch_log_group.agent_runner[0].name
            awslogs-region        = var.aws_region
            awslogs-stream-prefix = each.key
          }
        }
      },
      merge(
        {
          name        = "analyzer"
          image       = var.analyzer_image
          essential   = false
          entryPoint  = ["/bin/sh", "-c", local.analyzer_entry_script, "analyzer"]
          mountPoints = local.analyzer_mounts
          dependsOn   = [{ containerName = "init", condition = "SUCCESS" }]
          logConfiguration = {
            logDriver = "awslogs"
            options = {
              awslogs-group         = aws_cloudwatch_log_group.agent_runner[0].name
              awslogs-region        = var.aws_region
              awslogs-stream-prefix = each.key
            }
          }
        },
        var.agent_runner_private_images ? {
          repositoryCredentials = { credentialsParameter = aws_secretsmanager_secret.agent_runner_registry[0].arn }
        } : {},
      ),
      {
        name        = "upload"
        image       = local.aws_cli_image
        essential   = true
        entryPoint  = ["/bin/sh", "-c"]
        command     = [local.analyzer_upload_script]
        mountPoints = local.analyzer_mounts
        dependsOn   = [{ containerName = "analyzer", condition = "COMPLETE" }]
        logConfiguration = {
          logDriver = "awslogs"
          options = {
            awslogs-group         = aws_cloudwatch_log_group.agent_runner[0].name
            awslogs-region        = var.aws_region
            awslogs-stream-prefix = each.key
          }
        }
      },
    ],
    each.value == "read" ? [
      {
        name        = "progress"
        image       = local.aws_cli_image
        essential   = false
        entryPoint  = ["/bin/sh", "-c"]
        command     = [local.analyzer_progress_script]
        mountPoints = local.analyzer_mounts
        dependsOn   = [{ containerName = "analyzer", condition = "START" }]
        logConfiguration = {
          logDriver = "awslogs"
          options = {
            awslogs-group         = aws_cloudwatch_log_group.agent_runner[0].name
            awslogs-region        = var.aws_region
            awslogs-stream-prefix = each.key
          }
        }
      },
    ] : [],
  ))

  tags = merge(local.common_tags, {
    Name = each.key
  })
}
