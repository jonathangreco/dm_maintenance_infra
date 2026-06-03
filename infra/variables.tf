variable "project_name" {
  description = "Nom court du projet. Utilisé pour nommer les ressources AWS."
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

variable "app_instance_type" {
  description = "Type d'instance EC2 applicative."
  type        = string
  default     = "t3.micro"
}

variable "app_subnet_tier" {
  description = "Tier de subnet pour l'EC2 applicative: public (free-tier friendly) ou private."
  type        = string
  default     = "public"

  validation {
    condition     = contains(["public", "private"], var.app_subnet_tier)
    error_message = "app_subnet_tier doit être 'public' ou 'private'."
  }
}

variable "enable_nat_gateway" {
  description = "Active un NAT Gateway pour les subnets privés app (coût horaire supplémentaire)."
  type        = bool
  default     = false
}

variable "enable_ssh" {
  description = "Active l'acces SSH direct a l'instance EC2 applicative."
  type        = bool
  default     = false
}

variable "ssh_public_key_path" {
  description = "Chemin local vers la cle publique SSH a importer dans AWS."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ssh_public_key" {
  description = "Cle publique SSH a importer dans AWS. Prioritaire sur ssh_public_key_path si renseignee."
  type        = string
  default     = null
}

variable "ssh_allowed_cidr" {
  description = "CIDR autorise a joindre l'EC2 en SSH."
  type        = string
  default     = "0.0.0.0/0"
}

variable "app_port" {
  description = "Port HTTP exposé par l'application sur EC2."
  type        = number
  default     = 8080
}

variable "app_container_image" {
  description = "Image Docker PHP-FPM de l'application Symfony."
  type        = string
  default     = "ghcr.io/jonathangreco/darkmira-maintenance-app:prod"
}

variable "app_nginx_image" {
  description = "Image Docker Nginx servant l'application Symfony."
  type        = string
  default     = "ghcr.io/jonathangreco/darkmira-maintenance-nginx:prod"
}

variable "ghcr_login_enabled" {
  description = "Active le login GHCR avant docker pull."
  type        = bool
  default     = true
}

variable "ghcr_username" {
  description = "Username GitHub utilisé pour se connecter à GHCR."
  type        = string
  default     = "jonathangreco"
}

variable "ghcr_token_ssm_parameter_name" {
  description = "Nom du paramètre SSM SecureString contenant le token GHCR."
  type        = string
  default     = "/darkmira-maintenance/dev/ghcr/token"
}

variable "app_env_ssm_parameter_name" {
  description = "Nom du parametre SSM SecureString contenant le fichier env runtime de l'application."
  type        = string
  default     = "/darkmira-maintenance/dev/app/env"
}

variable "cloudwatch_log_retention_days" {
  description = "Retention en jours des logs CloudWatch applicatifs et EC2."
  type        = number
  default     = 14
}

variable "db_instance_class" {
  description = "Classe d'instance RDS MySQL."
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Taille initiale du stockage RDS (Go)."
  type        = number
  default     = 20
}

variable "night_shutdown_enabled" {
  description = "Active l'arret nocturne automatique de l'EC2 et de RDS."
  type        = bool
  default     = false
}

variable "night_shutdown_timezone" {
  description = "Timezone IANA utilisee par EventBridge Scheduler pour les horaires d'arret/demarrage."
  type        = string
  default     = "Europe/Paris"
}

variable "night_shutdown_stop_schedule" {
  description = "Expression cron EventBridge Scheduler pour arreter EC2 et RDS."
  type        = string
  default     = "cron(0 23 * * ? *)"
}

variable "night_shutdown_start_rds_schedule" {
  description = "Expression cron EventBridge Scheduler pour demarrer RDS avant l'EC2."
  type        = string
  default     = "cron(30 7 * * ? *)"
}

variable "night_shutdown_start_ec2_schedule" {
  description = "Expression cron EventBridge Scheduler pour demarrer l'EC2 apres RDS."
  type        = string
  default     = "cron(45 7 * * ? *)"
}

variable "night_shutdown_refresh_app_schedule" {
  description = "Expression cron EventBridge Scheduler pour repull/restart l'application apres le demarrage EC2."
  type        = string
  default     = "cron(50 7 * * ? *)"
}
