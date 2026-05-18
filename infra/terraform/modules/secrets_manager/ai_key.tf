# Placeholder secret for the Anthropic API key consumed by the AI Troubleshooter.
#
# The secret VALUE is never stored in Terraform state — it is populated manually
# (or via a CI secret rotation pipeline) after the infrastructure is applied:
#
#   aws secretsmanager put-secret-value \
#     --secret-id ai-troubleshooter/anthropic-api-key \
#     --secret-string '{"api_key":"sk-ant-..."}'
#
# The External Secrets Operator (ESO) then syncs the value into the cluster
# using the path configured in apps/ai-troubleshooter/external-secret.yaml.

resource "aws_secretsmanager_secret" "anthropic_api_key" {
  name                    = "ai-troubleshooter/anthropic-api-key/v1"
  description             = "Anthropic API key for the AI Troubleshooter pod-failure analyzer"
  recovery_window_in_days = 7

  tags = var.tags
}

output "anthropic_api_key_secret_arn" {
  description = "ARN of the Anthropic API key secret — pass this to the ESO IAM policy if you want to scope it down."
  value       = aws_secretsmanager_secret.anthropic_api_key.arn
}
