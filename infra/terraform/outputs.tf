# =============================================================================
# Root outputs — useful for scripts, CI pipelines, and other Terraform roots
# that reference this state via terraform_remote_state.
# =============================================================================

# --- VPC ---
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnets
}

output "public_subnets" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnets
}

# --- EKS ---
output "cluster_name" {
  description = "EKS cluster name"
  value       = local.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded CA certificate for the cluster"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_oidc_arn" {
  description = "OIDC provider ARN — used when creating new IRSA roles"
  value       = module.eks.cluster_oidc_arn
}

output "cluster_oidc_url" {
  description = "OIDC provider URL"
  value       = module.eks.cluster_oidc_url
}

# --- IAM (IRSA role ARNs — needed in Helm values) ---
output "external_secrets_role_arn" {
  description = "IRSA role ARN for External Secrets Operator"
  value       = module.iam.external_secrets_role_arn
}

output "alb_controller_role_arn" {
  description = "IRSA role ARN for AWS Load Balancer Controller"
  value       = module.iam.alb_controller_role_arn
}

output "cluster_autoscaler_role_arn" {
  description = "IRSA role ARN for Cluster Autoscaler"
  value       = module.iam.cluster_autoscaler_role_arn
}

# --- ECR ---
output "ecr_app_url" {
  description = "ECR repository URL for the main application image"
  value       = module.ecr_app.repository_url
}

output "ecr_troubleshooter_url" {
  description = "ECR repository URL for the AI Troubleshooter image"
  value       = module.ecr_troubleshooter.repository_url
}

# --- Secrets Manager ---
output "db_secret_arn" {
  description = "ARN of the DB credentials secret"
  value       = module.secrets.secret_arn
}

output "anthropic_api_key_secret_arn" {
  description = "ARN of the Anthropic API key secret"
  value       = module.secrets.anthropic_api_key_secret_arn
}

# --- GitHub Actions CI ---
output "github_ci_role_arn" {
  description = "Set as AWS_CI_ROLE_ARN secret in the app-repo GitHub repository settings"
  value       = module.iam.github_ci_role_arn
}
