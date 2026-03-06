# ============================================================
# Dev Environment — Root Module
#
# This file wires together all the infrastructure modules.
# Everything provisioned here is reproducible via:
#   terraform init && terraform apply
#
# Modules are applied in dependency order (Terraform resolves
# this automatically from the module references):
#   vpc → eks → alb
#          ↓
#         ecr  (independent of eks)
#
# Post-EKS modules (need a running cluster):
#   cluster-autoscaler, monitoring
# ============================================================

locals {
  # Resolve AZs: if the caller supplied azs use those; otherwise
  # auto-detect the first 3 available AZs in the chosen region.
  azs = length(var.azs) > 0 ? var.azs : slice(data.aws_availability_zones.available.names, 0, 3)

  # Single source of truth for the environment tag applied everywhere.
  common_tags = { Environment = "dev" }
}

data "aws_availability_zones" "available" {}

# ============================================================
# Networking
# ============================================================

module "vpc" {
  source = "../../modules/vpc"

  vpc_cidr             = var.vpc_cidr
  azs                  = local.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs

  tags = local.common_tags
}

# ============================================================
# Container Registry
# ============================================================

module "ecr" {
  source = "../../modules/ecr"

  name = var.ecr_repo_name

  tags = local.common_tags
}

# ============================================================
# EKS Cluster
# ============================================================

module "eks" {
  source = "../../modules/eks"

  cluster_name = var.cluster_name
  vpc_id       = module.vpc.vpc_id

  # Worker nodes run in private subnets — no direct internet exposure.
  subnet_ids = module.vpc.private_subnets

  tags = local.common_tags
}

# ============================================================
# AWS Load Balancer Controller (ALB Ingress)
# ============================================================

module "alb" {
  source = "../../modules/alb"

  cluster_name         = module.eks.cluster_name
  namespace            = "kube-system"
  service_account_name = "aws-load-balancer-controller"
  region               = var.aws_region
  vpc_id               = module.eks.vpc_id
}

# ============================================================
# Cluster Autoscaler (Phase 6)
# Scales node groups up/down based on pending pod pressure.
# ============================================================

module "cluster_autoscaler" {
  source = "../../modules/cluster-autoscaler"

  cluster_name         = module.eks.cluster_name
  region               = var.aws_region
  oidc_provider_url    = module.eks.oidc_provider_url
  namespace            = "kube-system"
  service_account_name = "cluster-autoscaler"

  tags = local.common_tags
}

# ============================================================
# Monitoring — Prometheus + Grafana (Phase 7)
#
# Managed directly via Helm — NOT via Terraform.
# The kube-prometheus-stack chart (~8 workloads + CRDs) consistently
# exceeds Terraform's Helm provider timeout during upgrades, and the
# provider requires downloading the chart index even during plan.
#
# Deploy / upgrade manually:
#   helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
#   helm repo update
#   helm upgrade --install kube-prometheus-stack \
#     prometheus-community/kube-prometheus-stack \
#     --namespace monitoring --create-namespace \
#     --version 61.0.0
# ============================================================

# ============================================================
# GitHub Actions OIDC (Phase 5 prerequisite)
#
# Creates an IAM OIDC Identity Provider for GitHub plus an IAM
# role the CI runner assumes via short-lived OIDC tokens.
# No static credentials ever leave this account.
# ============================================================

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  # Thumbprint of GitHub's OIDC intermediate cert (stable, verified by AWS docs)
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_policy_document" "github_actions_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    # aud must be sts.amazonaws.com (GitHub's OIDC default)
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Restrict to pushes to the main branch of your specific repo.
    # Pattern: repo:<owner>/<repo>:ref:refs/heads/main
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "github-actions-eks-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy" "github_actions" {
  name = "github-actions-deploy-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # ECR: authenticate and push/pull container images
        Sid    = "ECRAccess"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = "*"
      },
      {
        # EKS: update kubeconfig so kubectl and helm can authenticate
        Sid      = "EKSDescribe"
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = "*"
      }
    ]
  })
}

# ============================================================
# gp3 StorageClass
#
# gp3 is the current recommended EBS volume type:
#   - 20% cheaper than gp2
#   - Baseline 3000 IOPS / 125 MiB/s (vs gp2's burst model)
#
# Uses ebs.csi.aws.com provisioner (requires aws-ebs-csi-driver addon).
# Set as the cluster default so PVCs without an explicit storageClassName
# (e.g. postgresql StatefulSets) bind automatically.
# ============================================================

resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      # Make this the default StorageClass so PVCs without a storageClassName
      # get gp3 instead of the legacy gp2 in-tree provisioner.
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  volume_binding_mode    = "WaitForFirstConsumer"   # provision volume in same AZ as the pod
  reclaim_policy         = "Delete"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"   # encrypt EBS volumes at rest (no cost)
  }

  depends_on = [module.eks]
}

# Recreate gp2 using the EBS CSI provisioner so existing StatefulSets that
# reference storageClassName: gp2 continue to work after the old in-tree
# gp2 (provisioner: kubernetes.io/aws-ebs) is deleted.
# Run before terraform apply:  kubectl delete storageclass gp2
resource "kubernetes_storage_class_v1" "gp2_csi" {
  metadata {
    name = "gp2"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "false"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  volume_binding_mode    = "WaitForFirstConsumer"
  reclaim_policy         = "Delete"
  allow_volume_expansion = true

  parameters = {
    type      = "gp2"
    encrypted = "true"
  }

  depends_on = [module.eks]
}

output "ecr_repo_url" {
  description = "Full ECR repository URL. Used in CI as the image registry."
  value       = module.ecr.repository_url
}

# Legacy alias kept so the existing state entry is not removed.
# Both outputs resolve to the same value.
output "ecr_repo" {
  description = "Deprecated: use ecr_repo_url."
  value       = module.ecr.repository_url
}

output "eks_cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_name" {
  description = "EKS cluster name. Set this as the EKS_CLUSTER_NAME GitHub secret."
  value       = module.eks.cluster_name
}

output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions. Set this as the AWS_ROLE_TO_ASSUME GitHub secret."
  value       = aws_iam_role.github_actions.arn
}
