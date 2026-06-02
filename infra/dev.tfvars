project_name = "darkmira-maintenance"
environment  = "dev"
aws_region   = "eu-north-1"
owner        = "jonathan"

db_name     = "app"
db_username = "app_user"

enable_ssh       = true
ssh_public_key   = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDA8v100dIh72bVCmxW8UuKB6+yU1Af2VzDwbVzNXq+X nataniel.greco@gmail.com"
ssh_allowed_cidr = "90.38.211.210/32"

app_container_image = "ghcr.io/jonathangreco/darkmira-maintenance-app:prod"
app_nginx_image     = "ghcr.io/jonathangreco/darkmira-maintenance-nginx:prod"
ghcr_login_enabled  = true
ghcr_username       = "jonathangreco"

app_env_ssm_parameter_name    = "/darkmira-maintenance/dev/app/env"
ghcr_token_ssm_parameter_name = "/darkmira-maintenance/dev/ghcr/token"
