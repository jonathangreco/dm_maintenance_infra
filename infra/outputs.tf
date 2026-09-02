output "project_name" {
  description = "Nom du projet."
  value       = var.project_name
}

output "environment" {
  description = "Nom de l'environnement."
  value       = var.environment
}

output "aws_region" {
  description = "Région AWS cible."
  value       = var.aws_region
}

output "mysql_backup_bucket_name" {
  description = "Nom du bucket S3 prive contenant les exports SQL MySQL."
  value       = aws_s3_bucket.mysql_backups.bucket
}
output "agent_runner_cluster_arn" {
  description = "ARN du cluster ECS des runs de l'agent."
  value       = var.enable_agent_runner ? aws_ecs_cluster.agent_runner[0].arn : null
}

output "agent_runner_subnet_ids" {
  description = "Sous-reseaux publics utilises par les taches de run."
  value       = var.enable_agent_runner ? [for s in aws_subnet.public : s.id] : []
}

output "agent_runner_security_group_id" {
  description = "Groupe de securite des taches de run."
  value       = var.enable_agent_runner ? aws_security_group.agent_runner[0].id : null
}

output "agent_runner_artifacts_bucket" {
  description = "Bucket des artefacts produits par les runs."
  value       = var.enable_agent_runner ? aws_s3_bucket.agent_artifacts[0].bucket : null
}

output "agent_runner_log_group" {
  description = "Groupe de journaux des taches de run."
  value       = var.enable_agent_runner ? aws_cloudwatch_log_group.agent_runner[0].name : null
}
