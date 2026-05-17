variable "env" {
  description = "Target environment (dev/staging/prod)"
  type        = string
}

variable "cluster_oidc_arn" {
  description = "The ARN of the OIDC Provider from EKS module"
  type        = string
}

variable "cluster_oidc_url" {
  description = "The URL of the OIDC Provider from EKS module"
  type        = string
}


