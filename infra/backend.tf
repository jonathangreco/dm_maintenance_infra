terraform {
  backend "s3" {
    bucket       = "maintenance-darkmira-dev-tfstate-387219500605-eu-north-1"
    key          = "infra/terraform.tfstate"
    region       = "eu-north-1"
    encrypt      = true
    use_lockfile = true
  }
}
