module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.34" # שימוש בגרסה עדכנית של EKS [cite: 16]

  # אבטחת רשת: גישה לקלסטר רק מתוך ה-VPC או דרך Endpoint ציבורי מוגבל
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = var.cluster_endpoint_public_access

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnets 

  
  enable_irsa = true

  # API_AND_CONFIG_MAP is the safe migration path from the legacy CONFIG_MAP
  # mode — it enables Access Entries without breaking existing aws-auth setups.
  authentication_mode = "API_AND_CONFIG_MAP"

  
  eks_managed_node_groups = {
    system = {
      name           = "${var.env}-system-nodes"
      instance_types = var.system_node_group.instance_types 
      
      min_size     = var.system_node_group.desired_size
      max_size     = var.system_node_group.desired_size + 1
      desired_size = var.system_node_group.desired_size

      labels = {
        role = "system"
      }
    }

    application = {
      name           = "${var.env}-app-nodes"
      instance_types = var.app_node_group.instance_types 
      
      min_size     = var.app_node_group.min_size
      max_size     = var.app_node_group.max_size 
      desired_size = var.app_node_group.min_size

      labels = {
        role = "application"
      }

      taints = [
        {
          key    = "workload"
          value  = "application"
          effect = "NO_SCHEDULE"
        }
      ]
    }
  }

  tags = merge(var.tags, {
    Environment = var.env
  })
}

# ---------------------------------------------------------------------------
# Explicit EKS Access Entry for the IAM identity running Terraform.
#
# WHY: terraform-aws-modules/eks v20+ no longer writes aws-auth ConfigMap
# entries automatically.  Without an explicit access entry, the kubernetes
# and helm providers get "Unauthorized" even though the cluster is ACTIVE.
#
# aws_caller_identity resolves at plan time using the AWS provider credentials
# (IAM), which always works regardless of Kubernetes API availability.
# ---------------------------------------------------------------------------
data "aws_caller_identity" "current" {}

resource "aws_eks_access_entry" "terraform_runner" {
  cluster_name  = module.eks.cluster_name
  principal_arn = data.aws_caller_identity.current.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "terraform_runner_admin" {
  cluster_name  = module.eks.cluster_name
  principal_arn = data.aws_caller_identity.current.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.terraform_runner]
}