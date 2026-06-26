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
