output "external_secrets_role_arn" {
  description = "IAM Role ARN for External Secrets Operator"
  value       = aws_iam_role.external_secrets.arn
}

output "alb_controller_role_arn" {
  description = "IAM Role ARN for AWS Load Balancer Controller"
  value       = aws_iam_role.alb_controller.arn
}

output "cluster_autoscaler_role_arn" {
  description = "IAM Role ARN for Cluster Autoscaler"
  value       = aws_iam_role.cluster_autoscaler.arn
}
