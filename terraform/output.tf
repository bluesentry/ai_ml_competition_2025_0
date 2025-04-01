output "account_id" {
  value = local.account_id
}

output "region" {
  value = var.region
}

output "github_actions_oidc_role" {
  value = aws_iam_role.github_actions_ai_ml_role.name
}
