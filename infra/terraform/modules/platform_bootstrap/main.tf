# =============================================================================
# platform_bootstrap
#
# WHY null_resource instead of kubernetes_manifest?
# kubernetes_manifest validates CRDs against the live API at *plan* time.
# ArgoCD CRDs (AppProject, Application) don't exist until ArgoCD is installed,
# so the plan always fails with "API did not recognize GroupVersionKind".
#
# null_resource + local-exec runs only at *apply* time, after helm_release.argocd
# completes, so the CRDs are guaranteed to exist.
# =============================================================================

# ---------------------------------------------------------------------------
# 1. ArgoCD — HA mode, 2 replicas
# ---------------------------------------------------------------------------
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_version
  namespace        = "argocd"
  create_namespace = true
  wait             = true
  timeout          = 300

  values = [yamlencode({
    server = {
      replicas  = 2
      extraArgs = ["--insecure"]
    }
    repoServer = { replicas = 2 }
    configs    = { params = { "server.insecure" = true } }
    global     = { nodeSelector = { role = "system" } }
  })]
}

# ---------------------------------------------------------------------------
# 2. Wait for ArgoCD CRDs to be registered in the Kubernetes API
#    helm_release with wait=true ensures pods are running, but the API server
#    may still be indexing the newly installed CRDs for a few seconds.
# ---------------------------------------------------------------------------
resource "time_sleep" "wait_for_argocd_crds" {
  create_duration = "30s"
  depends_on      = [helm_release.argocd]
}

# ---------------------------------------------------------------------------
# 3. AppProject + ArgoCD Applications (via kubectl)
#
# All cluster-specific values (vpc_id, role ARNs, cluster_name) are set as
# shell variables from Terraform interpolations, then referenced inside the
# YAML heredocs — giving us automatic injection with no manual editing.
# ---------------------------------------------------------------------------
resource "null_resource" "argocd_platform_apps" {
  # Re-run whenever any injected value changes
  triggers = {
    cluster_name                = var.cluster_name
    vpc_id                      = var.vpc_id
    alb_controller_role_arn     = var.alb_controller_role_arn
    external_secrets_role_arn   = var.external_secrets_role_arn
    cluster_autoscaler_role_arn = var.cluster_autoscaler_role_arn
    argocd_version              = var.argocd_version
    config_repo_url             = var.config_repo_url
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-eu", "-c"]
    command     = <<-SCRIPT
      # ── Auth ────────────────────────────────────────────────────────────────
      aws eks update-kubeconfig \
        --name    "${var.cluster_name}" \
        --region  "${var.aws_region}" \
        --alias   "${var.cluster_name}"

      CTX="${var.cluster_name}"

      # ── Wait for ArgoCD CRDs ────────────────────────────────────────────────
      echo "Waiting for ArgoCD CRDs..."
      kubectl wait --context "$CTX" \
        --for=condition=established \
        --timeout=120s \
        crd/appprojects.argoproj.io \
        crd/applications.argoproj.io

      # ── Inject values from Terraform outputs ────────────────────────────────
      CLUSTER_NAME="${var.cluster_name}"
      AWS_REGION="${var.aws_region}"
      VPC_ID="${var.vpc_id}"
      ALB_ROLE_ARN="${var.alb_controller_role_arn}"
      ESO_ROLE_ARN="${var.external_secrets_role_arn}"
      CA_ROLE_ARN="${var.cluster_autoscaler_role_arn}"
      ALB_CHART_VERSION="${var.alb_controller_chart_version}"
      ESO_CHART_VERSION="${var.eso_chart_version}"
      CA_CHART_VERSION="${var.cluster_autoscaler_chart_version}"

      # ── AppProject ──────────────────────────────────────────────────────────
      echo "Applying AppProject..."
      kubectl apply --context "$CTX" -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: platform-apps
  namespace: argocd
spec:
  description: "Platform controllers — managed by Terraform bootstrap"
  sourceRepos: ["*"]
  destinations:
    - server: https://kubernetes.default.svc
      namespace: kube-system
    - server: https://kubernetes.default.svc
      namespace: argocd
    - server: https://kubernetes.default.svc
      namespace: external-secrets
    - server: https://kubernetes.default.svc
      namespace: dev
    - server: https://kubernetes.default.svc
      namespace: staging
    - server: https://kubernetes.default.svc
      namespace: production
    - server: https://kubernetes.default.svc
      namespace: ai-troubleshooter
    - server: https://kubernetes.default.svc
      namespace: istio-system
  clusterResourceWhitelist:
    - group: "*"
      kind: "*"
  roles:
    - name: read-only
      description: "Developers — view only"
      policies:
        - "p, proj:platform-apps:read-only, applications, get, platform-apps/*, allow"
    - name: deploy
      description: "CI — can sync"
      policies:
        - "p, proj:platform-apps:deploy, applications, sync, platform-apps/*, allow"
EOF

      # ── AWS Load Balancer Controller ─────────────────────────────────────────
      echo "Applying ALB Controller Application..."
      kubectl apply --context "$CTX" -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: aws-load-balancer-controller
  namespace: argocd
  labels:
    app.kubernetes.io/part-of: platform-apps
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: platform-apps
  source:
    repoURL: https://aws.github.io/eks-charts
    chart: aws-load-balancer-controller
    targetRevision: "$ALB_CHART_VERSION"
    helm:
      values: |
        clusterName: $CLUSTER_NAME
        region: $AWS_REGION
        vpcId: $VPC_ID
        replicaCount: 2
        podDisruptionBudget:
          maxUnavailable: 1
        serviceAccount:
          create: true
          name: aws-load-balancer-controller
          annotations:
            eks.amazonaws.com/role-arn: $ALB_ROLE_ARN
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi
        nodeSelector:
          role: system
        logLevel: info
        enableShield: false
        enableWaf: false
        enableWafv2: false
  destination:
    server: https://kubernetes.default.svc
    namespace: kube-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - ServerSideApply=true
EOF

      # ── External Secrets Operator ────────────────────────────────────────────
      echo "Applying External Secrets Operator Application..."
      kubectl apply --context "$CTX" -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: external-secrets-operator
  namespace: argocd
  labels:
    app.kubernetes.io/part-of: platform-apps
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: platform-apps
  source:
    repoURL: https://charts.external-secrets.io
    chart: external-secrets
    targetRevision: "$ESO_CHART_VERSION"
    helm:
      values: |
        installCRDs: true
        serviceAccount:
          create: true
          name: external-secrets-sa
          annotations:
            eks.amazonaws.com/role-arn: $ESO_ROLE_ARN
        nodeSelector:
          role: system
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
  destination:
    server: https://kubernetes.default.svc
    namespace: external-secrets
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
EOF

      # ── Cluster Autoscaler ───────────────────────────────────────────────────
      echo "Applying Cluster Autoscaler Application..."
      kubectl apply --context "$CTX" -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cluster-autoscaler
  namespace: argocd
  labels:
    app.kubernetes.io/part-of: platform-apps
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: platform-apps
  source:
    repoURL: https://kubernetes.github.io/autoscaler
    chart: cluster-autoscaler
    targetRevision: "$CA_CHART_VERSION"
    helm:
      values: |
        autoDiscovery:
          clusterName: $CLUSTER_NAME
        awsRegion: $AWS_REGION
        rbac:
          serviceAccount:
            create: true
            name: cluster-autoscaler
            annotations:
              eks.amazonaws.com/role-arn: $CA_ROLE_ARN
        nodeSelector:
          role: system
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 300m
            memory: 256Mi
  destination:
    server: https://kubernetes.default.svc
    namespace: kube-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - ServerSideApply=true
EOF

      # ── ClusterSecretStore — connects ESO to AWS Secrets Manager ────────────
      echo "Applying ClusterSecretStore..."
      kubectl apply --context "$CTX" -f - <<EOF
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: $AWS_REGION
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
            namespace: external-secrets
EOF

      # ── saas-api-gateway (per environment) ──────────────────────────────────
      ENV="${var.env}"
      CONFIG_REPO_URL="${var.config_repo_url}"

      # Map Terraform env → kustomize overlay path and target namespace
      case "$ENV" in
        dev)     OVERLAY="dev";        TARGET_NS="dev"        ;;
        staging) OVERLAY="staging";    TARGET_NS="staging"    ;;
        prod)    OVERLAY="production"; TARGET_NS="production"  ;;
      esac

      echo "Applying saas-api-gateway Application for $ENV..."
      kubectl apply --context "$CTX" -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: saas-api-gateway-$ENV
  namespace: argocd
  labels:
    app.kubernetes.io/part-of: platform-apps
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: platform-apps
  source:
    repoURL: $CONFIG_REPO_URL
    targetRevision: $ENV
    path: apps/overlays/$OVERLAY
  destination:
    server: https://kubernetes.default.svc
    namespace: $TARGET_NS
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
EOF

      echo "All ArgoCD Applications applied successfully."
    SCRIPT
  }

  depends_on = [time_sleep.wait_for_argocd_crds]
}
