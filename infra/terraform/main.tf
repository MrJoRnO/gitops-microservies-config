# =============================================================================
# Root module — wires all child modules together.
# Environment is selected via var.env (dev | staging | prod).
# All env-specific values come from locals.tf.
# =============================================================================

# -----------------------------------------------------------------------------
# 1. VPC
# -----------------------------------------------------------------------------
module "vpc" {
  source = "./modules/vpc"

  vpc_name        = "${local.cluster_name}-vpc"
  vpc_cidr        = local.cfg.vpc_cidr
  azs             = local.cfg.azs
  private_subnets = local.cfg.private_subnets
  public_subnets  = local.cfg.public_subnets

  cluster_name       = local.cluster_name
  single_nat_gateway = local.cfg.single_nat_gw

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# 2. EKS cluster
# -----------------------------------------------------------------------------
module "eks" {
  source = "./modules/eks"

  env          = var.env
  cluster_name = local.cluster_name
  vpc_id       = module.vpc.vpc_id
  private_subnets = module.vpc.private_subnets

  cluster_endpoint_public_access = local.cfg.cluster_endpoint_public_access

  system_node_group = local.cfg.system_node_group
  app_node_group    = local.cfg.app_node_group

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# 3. IAM — IRSA roles for in-cluster controllers
#    Depends on EKS OIDC provider being created first.
# -----------------------------------------------------------------------------
module "iam" {
  source = "./modules/iam"

  env              = var.env
  cluster_oidc_arn = module.eks.cluster_oidc_arn
  cluster_oidc_url = module.eks.cluster_oidc_url

  github_org                  = var.github_org
  github_app_repo             = var.github_app_repo
  create_github_oidc_provider = var.env == "dev" ? true : false
}

# -----------------------------------------------------------------------------
# 4. ECR repositories
#    One call per image — keeps the module simple and each repo independently
#    manageable (lifecycle policy, permissions, etc.).
# -----------------------------------------------------------------------------
module "ecr_app" {
  source = "./modules/ecr"

  repository_name = "platform/saas-api-gateway"
  tags            = local.common_tags
}

module "ecr_troubleshooter" {
  source = "./modules/ecr"

  repository_name = "platform/ai-troubleshooter"
  tags            = local.common_tags
}

# -----------------------------------------------------------------------------
# 5. Secrets Manager
#    Creates the DB secret stub + the Anthropic API key secret stub.
#    Secret VALUES are never stored in Terraform — they are injected manually
#    or via a secrets rotation pipeline after apply.
# -----------------------------------------------------------------------------
module "secrets" {
  source = "./modules/secrets_manager"

  secret_name = local.cfg.db_secret_name
  db_details  = ""   # placeholder — fill in via aws secretsmanager put-secret-value
  tags        = local.common_tags
}

# -----------------------------------------------------------------------------
# 6. API server readiness gate
#
# Even after EKS reports the cluster as ACTIVE, the Kubernetes API server
# needs ~30 s before it accepts connections from external clients.
# Without this wait, the kubernetes/helm providers hit the server too early
# and get connection-refused or TLS handshake errors.
# -----------------------------------------------------------------------------
resource "time_sleep" "wait_for_cluster" {
  # 60 s covers two delays:
  #   ~20 s  API server startup after cluster ACTIVE
  #   ~30 s  EKS Access Entry propagation after aws_eks_access_policy_association
  # module.eks includes the access entry resources, so this gate is sufficient.
  create_duration = "60s"
  depends_on      = [module.eks]
}

# -----------------------------------------------------------------------------
# 7. Platform Bootstrap
#    Installs ArgoCD (via Helm) and creates ArgoCD Application CRDs for all
#    platform controllers.  Terraform output values (VPC ID, IRSA role ARNs,
#    cluster name) are injected automatically — no manual YAML editing needed.
# -----------------------------------------------------------------------------
module "platform_bootstrap" {
  source = "./modules/platform_bootstrap"

  env        = var.env
  aws_region = var.aws_region

  # Derived values — wired directly from other module outputs
  cluster_name                = local.cluster_name
  vpc_id                      = module.vpc.vpc_id
  alb_controller_role_arn     = module.iam.alb_controller_role_arn
  external_secrets_role_arn   = module.iam.external_secrets_role_arn
  cluster_autoscaler_role_arn = module.iam.cluster_autoscaler_role_arn

  depends_on = [time_sleep.wait_for_cluster, module.iam]
}
