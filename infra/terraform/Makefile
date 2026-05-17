ENV        ?= dev
TFVARS     := $(ENV).tfvars
STATE_KEY  := $(ENV)/terraform.tfstate
BACKEND    := -backend-config="key=$(STATE_KEY)"

.PHONY: init plan apply apply-infra apply-platform destroy fmt validate help

help:
	@echo "Usage: make <target> [ENV=dev|staging|prod]"
	@echo ""
	@echo "Targets:"
	@echo "  init             terraform init with correct backend key"
	@echo "  plan             terraform plan"
	@echo "  apply            two-stage apply (infra → platform)"
	@echo "  apply-infra      stage 1 only — EKS + IAM + VPC (creates access entry)"
	@echo "  apply-platform   stage 2 only — ArgoCD + controllers (requires stage 1 done)"
	@echo "  destroy          destroy all resources"
	@echo "  fmt              format all .tf files"
	@echo "  validate         validate terraform configuration"

# ─── Init ────────────────────────────────────────────────────────────────────

init:
	terraform init -reconfigure $(BACKEND)

# ─── Plan ────────────────────────────────────────────────────────────────────

plan: init
	terraform plan -var-file=$(TFVARS)

# ─── Two-stage apply (default) ───────────────────────────────────────────────
#
# WHY two stages?
# Terraform initialises the kubernetes/helm providers using the cluster endpoint
# from state.  If the IAM access entry doesn't exist yet, the providers get
# 401 Unauthorized — even with depends_on.  This is a known Terraform
# limitation: provider init runs before resource ordering takes effect.
#
# Stage 1 creates the EKS cluster + access entry via the AWS provider (no K8s).
# Stage 2 runs with a cluster that already has a valid access entry — all good.

apply: apply-infra apply-platform
	@echo ""
	@echo "✓ Full apply complete for ENV=$(ENV)"

apply-infra: init
	@echo ">>> Stage 1: Infrastructure (VPC, EKS, IAM, ECR, Secrets)"
	@echo "    This creates the EKS cluster and the Terraform runner's access entry."
	terraform apply -var-file=$(TFVARS) \
		-target=module.vpc \
		-target=module.eks \
		-target=module.iam \
		-target=module.ecr_app \
		-target=module.ecr_troubleshooter \
		-target=module.secrets \
		-target=time_sleep.wait_for_cluster
	@echo ""
	@echo "✓ Stage 1 complete — EKS cluster ready, access entry created."

apply-platform: init
	@echo ">>> Stage 2: Platform bootstrap (ArgoCD + controllers)"
	@echo "    kubernetes/helm providers now authenticate against the existing cluster."
	terraform apply -var-file=$(TFVARS)
	@echo ""
	@echo "✓ Stage 2 complete — ArgoCD and all controllers deployed."

# ─── Destroy ─────────────────────────────────────────────────────────────────

destroy: init
	terraform destroy -var-file=$(TFVARS)

# ─── Quality ─────────────────────────────────────────────────────────────────

fmt:
	terraform fmt -recursive .

validate: init
	terraform validate
