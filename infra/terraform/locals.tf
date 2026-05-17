# All per-environment differences live here.
# The environment is chosen by passing -var="env=dev|staging|prod" (or via a
# tfvars file).  Everything else is derived automatically from local.cfg.

locals {
  # -------------------------------------------------------------------------
  # Per-environment configuration map
  # -------------------------------------------------------------------------
  env_config = {
    dev = {
      # Networking
      vpc_cidr        = "10.0.0.0/16"
      azs             = ["${var.aws_region}a", "${var.aws_region}b"]
      private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
      public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]
      single_nat_gw   = true   # single NAT saves cost in dev

      # EKS
      cluster_endpoint_public_access = true   # no VPN needed in dev
      system_node_group = {
        instance_types = ["t3.medium"]
        desired_size   = 2
      }
      app_node_group = {
        instance_types = ["t3.large"]
        min_size       = 1
        max_size       = 2
      }

      # Secrets Manager
      db_secret_name = "dev/platform/db"
    }

    staging = {
      # Networking
      vpc_cidr        = "10.1.0.0/16"
      azs             = ["${var.aws_region}a", "${var.aws_region}b"]
      private_subnets = ["10.1.1.0/24", "10.1.2.0/24"]
      public_subnets  = ["10.1.101.0/24", "10.1.102.0/24"]
      single_nat_gw   = true

      # EKS
      cluster_endpoint_public_access = true
      system_node_group = {
        instance_types = ["t3.medium"]
        desired_size   = 2
      }
      app_node_group = {
        instance_types = ["t3.large"]
        min_size       = 2
        max_size       = 4
      }

      # Secrets Manager
      db_secret_name = "staging/platform/db"
    }

    prod = {
      # Networking — 3 AZs + one NAT GW per AZ for full HA
      vpc_cidr        = "10.2.0.0/16"
      azs             = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
      private_subnets = ["10.2.1.0/24", "10.2.2.0/24", "10.2.3.0/24"]
      public_subnets  = ["10.2.101.0/24", "10.2.102.0/24", "10.2.103.0/24"]
      single_nat_gw   = false  # one NAT per AZ — survives an AZ failure

      # EKS — API server private only in prod; access via bastion/VPN
      cluster_endpoint_public_access = false
      system_node_group = {
        instance_types = ["t3.medium"]
        desired_size   = 2
      }
      app_node_group = {
        instance_types = ["t3.large"]
        min_size       = 2
        max_size       = 4
      }

      # Secrets Manager
      db_secret_name = "prod/platform/db"
    }
  }

  # -------------------------------------------------------------------------
  # Shortcuts — use these everywhere else instead of local.env_config[var.env]
  # -------------------------------------------------------------------------
  cfg          = local.env_config[var.env]
  cluster_name = "platform-${var.env}"

  common_tags = {
    Environment = var.env
    Project     = "cloud-native-platform"
    ManagedBy   = "terraform"
  }
}
