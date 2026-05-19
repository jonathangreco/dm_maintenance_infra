output "terraform_state_bucket_name" {
  description = "Nom du bucket S3 utilisé pour stocker le state Terraform."
  value       = aws_s3_bucket.terraform_state.bucket
}

output "terraform_state_bucket_region" {
  description = "Région du bucket S3 de state Terraform."
  value       = var.aws_region
}

output "infra_backend_configuration" {
  description = "Configuration backend S3 à reporter dans infra/backend.tf."
  value       = <<EOT
terraform {
  backend "s3" {
    bucket       = "${aws_s3_bucket.terraform_state.bucket}"
    key          = "infra/terraform.tfstate"
    region       = "${var.aws_region}"
    encrypt      = true
    use_lockfile = true
  }
}
EOT
}

output "github_actions_role_arn" {
  description = "ARN du role IAM assume par GitHub Actions via OIDC."
  value       = aws_iam_role.github_actions_terraform.arn
}

output "github_actions_oidc_provider_arn" {
  description = "ARN du provider OIDC GitHub Actions."
  value       = aws_iam_openid_connect_provider.github_actions.arn
}
