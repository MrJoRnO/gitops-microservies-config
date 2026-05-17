# =============================================================================
# GitHub Actions OIDC — lets CI authenticate to AWS without static access keys.
#
# How it works:
#   GitHub mints a short-lived OIDC token per workflow run.
#   AWS STS validates the token against the GitHub OIDC provider and returns
#   temporary credentials scoped to this role.
#
# What to add in GitHub:
#   Settings → Secrets → Actions → New secret:
#     AWS_CI_ROLE_ARN = output.github_ci_role_arn
# =============================================================================

variable "github_org" {
  description = "GitHub organisation or username that owns the app-repo"
  type        = string
}

variable "github_app_repo" {
  description = "Name of the application repository (e.g. 'app-repo')"
  type        = string
  default     = "app-repo"
}

# One OIDC provider per AWS account — use count to avoid duplicates across envs.
# Set create_github_oidc_provider = false if it already exists in your account.
variable "create_github_oidc_provider" {
  description = "Create the GitHub OIDC provider (false if it already exists)"
  type        = bool
  default     = true
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  # Thumbprint for token.actions.githubusercontent.com (GitHub's OIDC provider)
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

locals {
  oidc_provider_arn = (
    var.create_github_oidc_provider
    ? aws_iam_openid_connect_provider.github[0].arn
    : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
  )
}

resource "aws_iam_role" "github_ci" {
  name        = "${var.env}-github-ci-role"
  description = "Assumed by GitHub Actions via OIDC to build and push container images"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = local.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          # Scope to the specific repo and all its branches
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_app_repo}:ref:refs/heads/*"
        }
      }
    }]
  })
}

resource "aws_iam_policy" "github_ci_ecr" {
  name        = "${var.env}-github-ci-ecr-policy"
  description = "Allow CI to authenticate to ECR and push images"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # GetAuthorizationToken is account-level — cannot be scoped to a repo
        Sid    = "ECRAuth"
        Effect = "Allow"
        Action = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        # Push/pull scoped to this environment's repositories only
        Sid    = "ECRPushPull"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeRepositories",
          "ecr:ListImages"
        ]
        Resource = [
          "arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/platform/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_ci_ecr" {
  role       = aws_iam_role.github_ci.name
  policy_arn = aws_iam_policy.github_ci_ecr.arn
}

output "github_ci_role_arn" {
  description = "Set this as AWS_CI_ROLE_ARN secret in the app-repo GitHub settings"
  value       = aws_iam_role.github_ci.arn
}
