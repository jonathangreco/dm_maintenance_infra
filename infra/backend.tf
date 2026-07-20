terraform {
  backend "s3" {
    bucket       = "darkmira-maintenance-dev-tfstate-764214841153-eu-north-1"
    key          = "infra/terraform.tfstate"
    region       = "eu-north-1"
    encrypt      = true
    use_lockfile = true
  }
}
