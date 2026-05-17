variable "env" {
  description = "Target environment. Must be one of: dev, staging, prod"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.env)
    error_message = "env must be one of: dev, staging, prod"
  }
}

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-central-1"
}

variable "github_org" {
  description = "GitHub organisation or username that owns the app-repo (used for OIDC trust policy)"
  type        = string
}

variable "github_app_repo" {
  description = "Name of the application repository"
  type        = string
  default     = "gitops-microservies-app"
}
