# All values come from other modules' outputs — nothing is hardcoded here.
# Terraform wires them automatically; no manual editing after terraform apply.

variable "env" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "vpc_id" {
  type        = string
  description = "VPC ID — passed to ALB controller so it knows where to place load balancers"
}

# IRSA role ARNs — one per controller
variable "alb_controller_role_arn" {
  type        = string
  description = "IRSA role ARN for the AWS Load Balancer Controller"
}

variable "external_secrets_role_arn" {
  type        = string
  description = "IRSA role ARN for the External Secrets Operator"
}

variable "cluster_autoscaler_role_arn" {
  type        = string
  description = "IRSA role ARN for the Cluster Autoscaler"
}

variable "argocd_version" {
  type        = string
  description = "Helm chart version for ArgoCD"
  default     = "7.6.12"
}

variable "alb_controller_chart_version" {
  type        = string
  description = "Helm chart version for AWS Load Balancer Controller"
  default     = "1.8.3"
}

variable "eso_chart_version" {
  type        = string
  description = "Helm chart version for External Secrets Operator"
  default     = "0.10.3"
}

variable "cluster_autoscaler_chart_version" {
  type        = string
  description = "Helm chart version for Cluster Autoscaler"
  default     = "9.37.0"
}
