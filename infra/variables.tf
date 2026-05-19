variable "project_name" {
  description = "Nom court du projet. Utilisé pour nommer les ressources AWS."
  type        = string
  default     = "maintenance-darkmira"
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
  description = "Nom ou identifiant du propriétaire du projet."
  type        = string
  default     = "jonathan"
}

variable "db_name" {
  description = "Nom de la base de données applicative."
  type        = string
  default     = "app"
}

variable "db_username" {
  description = "Nom d'utilisateur administrateur de la base RDS."
  type        = string
  default     = "app_user"
}

variable "db_password" {
  description = "Mot de passe de la base RDS. Ne jamais commiter cette valeur."
  type        = string
  sensitive   = true
}

variable "vpc_cidr" {
  description = "CIDR principal du VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Liste des CIDR des subnets publics (ALB, NAT)."
  type        = list(string)
  default     = ["10.20.0.0/24", "10.20.1.0/24"]
}

variable "private_app_subnet_cidrs" {
  description = "Liste des CIDR des subnets privés applicatifs (EC2)."
  type        = list(string)
  default     = ["10.20.10.0/24", "10.20.11.0/24"]
}

variable "private_db_subnet_cidrs" {
  description = "Liste des CIDR des subnets privés base de données (RDS)."
  type        = list(string)
  default     = ["10.20.20.0/24", "10.20.21.0/24"]
}
