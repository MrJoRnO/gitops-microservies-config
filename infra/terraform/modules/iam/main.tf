data "aws_iam_policy_document" "eso_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(var.cluster_oidc_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:external-secrets:external-secrets-sa"]
    }

    principals {
      identifiers = [var.cluster_oidc_arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "external_secrets" {
  name               = "${var.env}-eks-external-secrets-role"
  assume_role_policy = data.aws_iam_policy_document.eso_assume_role.json
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_iam_policy" "external_secrets" {
  name        = "${var.env}-eks-external-secrets-policy"
  description = "Allow ESO to read secrets from AWS Secrets Manager — scoped to env path"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        # Scoped to this environment's secret prefix + the ai-troubleshooter secret.
        Resource = [
          "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${var.env}/*",
          "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:ai-troubleshooter/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "external_secrets" {
  role       = aws_iam_role.external_secrets.name
  policy_arn = aws_iam_policy.external_secrets.arn
}


# --- תפקיד עבור AWS Load Balancer Controller ---
data "aws_iam_policy_document" "alb_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(var.cluster_oidc_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    principals {
      identifiers = [var.cluster_oidc_arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "alb_controller" {
  name               = "${var.env}-eks-alb-controller-role"
  assume_role_policy = data.aws_iam_policy_document.alb_assume_role.json
}

resource "aws_iam_policy" "alb_controller" {
  name        = "${var.env}-eks-alb-controller-policy"
  description = "Full official policy for AWS Load Balancer Controller v2.x"

  # Policy JSON lives in a separate file to keep this module readable.
  # Source: github.com/kubernetes-sigs/aws-load-balancer-controller (adapted)
  policy = file("${path.module}/policies/aws-load-balancer-controller.json")
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}



data "aws_iam_policy_document" "autoscaler_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(var.cluster_oidc_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:cluster-autoscaler"]
    }

    principals {
      identifiers = [var.cluster_oidc_arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "cluster_autoscaler" {
  name               = "${var.env}-eks-cluster-autoscaler-role"
  assume_role_policy = data.aws_iam_policy_document.autoscaler_assume_role.json
}

resource "aws_iam_policy" "cluster_autoscaler" {
  name        = "${var.env}-eks-cluster-autoscaler-policy"
  description = "Allow Cluster Autoscaler to scale EC2 Node Groups"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Describe actions require Resource: * (AWS does not support resource-level for these)
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeTags",
          "ec2:DescribeLaunchTemplateVersions"
        ]
        Resource = "*"
      },
      {
        # Mutating actions scoped to ASGs belonging to this cluster only
        Effect = "Allow"
        Action = [
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "autoscaling:ResourceTag/kubernetes.io/cluster/platform-${var.env}" = "owned"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_autoscaler" {
  role       = aws_iam_role.cluster_autoscaler.name
  policy_arn = aws_iam_policy.cluster_autoscaler.arn
}