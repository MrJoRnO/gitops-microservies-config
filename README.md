# cloud-native-platform — Config Repo

GitOps configuration repository for a cloud-native SaaS platform on AWS EKS.  
Managed by ArgoCD. Infrastructure provisioned by Terraform.

---

## Repository Structure

```
config-repo/
├── apps/                          # Kubernetes manifests (deployed by ArgoCD)
│   ├── ai-troubleshooter/         # AI-powered pod failure troubleshooter
│   ├── base/                      # saas-api-gateway base manifests (Kustomize)
│   └── overlays/
│       ├── staging/
│       └── production/
│
├── argocd/
│   └── apps/                      # ArgoCD Application CRDs
│       └── ai-troubleshooter-app.yaml
│
└── infra/
    └── terraform/                 # Infrastructure as Code
        ├── modules/
        │   ├── eks/               # EKS cluster + access entries
        │   ├── vpc/               # VPC, subnets, NAT gateways
        │   ├── iam/               # IRSA roles (ALB, ESO, Autoscaler)
        │   ├── ecr/               # ECR repositories
        │   ├── secrets_manager/   # AWS Secrets Manager stubs
        │   └── platform_bootstrap/# ArgoCD + platform controllers via Helm
        ├── dev.tfvars
        ├── staging.tfvars
        ├── prod.tfvars
        └── Makefile
```

---

## Environments & Branch Strategy

| Branch    | Environment | EKS Cluster          |
|-----------|-------------|----------------------|
| `dev`     | Development | `platform-dev`       |
| `staging` | Staging     | `platform-staging`   |
| `main`    | Production  | `platform-prod`      |

Changes flow: `dev` → PR → `staging` → PR → `main`

ArgoCD Applications track their respective branch — a merge to `staging` triggers an automatic sync to the staging cluster.

---

## Platform Components

| Component | Namespace | Managed By |
|---|---|---|
| ArgoCD | `argocd` | Helm (Terraform bootstrap) |
| AWS Load Balancer Controller | `kube-system` | ArgoCD (Helm chart) |
| External Secrets Operator | `external-secrets` | ArgoCD (Helm chart) |
| Cluster Autoscaler | `kube-system` | ArgoCD (Helm chart) |
| AI Troubleshooter | `ai-troubleshooter` | ArgoCD (this repo) |
| saas-api-gateway | `staging` / `production` | ArgoCD (this repo) |

---

## First-Time Setup

### Prerequisites
- AWS CLI configured with appropriate permissions
- `kubectl`, `terraform >= 1.6`, `helm >= 3`, `make`
- S3 bucket `platform-terraform-state-v1` + DynamoDB `platform-terraform-locks-v1`

### Deploy (two-stage apply)

```bash
cd infra/terraform

# Stage 1 — VPC, EKS cluster, IAM, ECR, Secrets
make apply-infra ENV=dev

# Stage 2 — ArgoCD + platform controllers
make apply-platform ENV=dev
```

Stage 1 creates the cluster and the Terraform runner's access entry.  
Stage 2 runs after the cluster is ready, so the Helm provider can authenticate.

### Verify

```bash
# ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:80

# Check platform apps
kubectl get applications -n argocd
```

---

## AI Troubleshooter

Watches all application namespaces for failing pods. When a pod enters `CrashLoopBackOff`, `OOMKilled`, or another failure state, it:

1. Collects pod logs, events, and status
2. Scrubs sensitive data (passwords, tokens, connection strings) from the logs
3. Calls the Claude API (`claude-sonnet-4-6`) for a diagnosis
4. Stores the result in a ConfigMap next to the failing pod

```bash
# Read a diagnosis
kubectl get configmap -n <namespace> ai-diagnosis-<pod-name> \
  -o jsonpath='{.data.diagnosis\.md}'
```

The Anthropic API key is stored in AWS Secrets Manager (`ai-troubleshooter/anthropic-api-key`) and synced to Kubernetes via External Secrets Operator — no static credentials in the cluster.

---

## Secret Management

Secrets are **never stored in this repository**.

| Secret | AWS Location | Synced Via |
|---|---|---|
| Anthropic API key | `ai-troubleshooter/anthropic-api-key` | ExternalSecret → ESO |
| DB connection string | `<env>/platform/db` | injected manually post-apply |

After `terraform apply`, inject the real DB secret:
```bash
aws secretsmanager put-secret-value \
  --secret-id dev/platform/db \
  --secret-string '{"connection_string":"postgres://..."}'
```

---

## Promoting a Change

```bash
# 1. Develop on dev branch
git checkout dev
# ... make changes ...
git commit -m "feat: ..."
git push origin dev

# 2. Promote to staging
gh pr create --base staging --head dev --title "promote: ..."

# 3. Promote to production
gh pr create --base main --head staging --title "release: ..."
```
