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
