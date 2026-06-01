variable "project_name" {
  description = "Nom court du projet."
  type        = string
  default     = "darkmira-maintenance"
}

variable "environment" {
  description = "Nom de l'environnement."
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "Région AWS cible."
  type        = string
  default     = "eu-north-1"
}

variable "owner" {
  description = "Propriétaire du projet."
  type        = string
  default     = "jonathan"
}

variable "github_repository" {
  description = "Repository GitHub autorisé à assumer le role OIDC (format OWNER/REPO)."
  type        = string
  default     = "jonathangreco/dm_maintenance_infra"
}

variable "github_branch" {
  description = "Branche GitHub autorisée à assumer le role OIDC."
  type        = string
  default     = "master"
}
