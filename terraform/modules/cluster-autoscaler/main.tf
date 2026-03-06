# ============================================================
# Cluster Autoscaler Module
#
# Installs the Kubernetes Cluster Autoscaler via Helm.
# Uses IRSA (IAM Roles for Service Accounts) so the pod has
# permission to resize EC2 Auto Scaling Groups without needing
# node-level credentials.
#
# How it works:
#   1. IAM role is created with a trust policy scoped to the
#      Cluster Autoscaler Kubernetes service account.
#   2. IAM policy grants access to EC2 Auto Scaling APIs.
#   3. Kubernetes SA is annotated with the role ARN.
#   4. Helm installs the autoscaler chart; it discovers node
#      groups by looking for the "k8s.io/cluster-autoscaler/"
#      tag set on the EKS managed node group.
# ============================================================

terraform {
  required_providers {
    aws        = { source = "hashicorp/aws" }
    kubernetes = { source = "hashicorp/kubernetes" }
    helm       = { source = "hashicorp/helm" }
  }
}

data "aws_caller_identity" "current" {}

# --------------------------------
# IRSA Trust Policy
# --------------------------------

locals {
  # Strip "https://" from the OIDC URL per AWS IAM requirements
  oidc_host = replace(var.oidc_provider_url, "https://", "")
  sa_ref    = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
}

data "aws_iam_policy_document" "ca_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.oidc_host}"]
    }

    # Lock the role to only the exact service account in the exact namespace.
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = [local.sa_ref]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# --------------------------------
# IAM Role
# --------------------------------

resource "aws_iam_role" "cluster_autoscaler" {
  name               = "ClusterAutoscalerRole-${var.cluster_name}"
  assume_role_policy = data.aws_iam_policy_document.ca_assume.json

  tags = var.tags
}

# --------------------------------
# IAM Policy (least privilege)
# --------------------------------

resource "aws_iam_role_policy" "cluster_autoscaler" {
  name = "ClusterAutoscalerPolicy"
  role = aws_iam_role.cluster_autoscaler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        # Read-only: discover ASGs and their current state
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeScalingActivities",
        "autoscaling:DescribeTags",
        # Write: scale node groups up and down
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup",
        # EC2 metadata needed when evaluating spot/on-demand availability
        "ec2:DescribeImages",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeLaunchTemplateVersions",
        "ec2:GetInstanceTypesFromInstanceRequirements",
        # EKS: read node group size limits
        "eks:DescribeNodegroup"
      ]
      Resource = "*"
    }]
  })
}

# --------------------------------
# Kubernetes Service Account (IRSA binding)
# --------------------------------

resource "kubernetes_service_account_v1" "cluster_autoscaler" {
  metadata {
    name      = var.service_account_name
    namespace = var.namespace

    # This annotation is what binds the K8s SA to the IAM role.
    # The IRSA webhook on EKS intercepts pod creation and injects
    # the AWS_ROLE_ARN + token volume into the pod spec.
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.cluster_autoscaler.arn
    }
  }
}

# --------------------------------
# Helm Release
# --------------------------------

resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = var.namespace
  version    = "9.37.0"

  # All chart values are expressed as a single HCL object so Terraform can
  # track type-safe booleans and maps without the deprecated `set {}` blocks.
  values = [
    yamlencode({
      # Auto-discovery: find ASGs tagged k8s.io/cluster-autoscaler/<cluster>=owned
      autoDiscovery = {
        clusterName = var.cluster_name
      }

      awsRegion = var.region

      rbac = {
        serviceAccount = {
          # We create the SA via Terraform (IRSA annotation); don't let Helm create a second one.
          create = false
          name   = var.service_account_name
        }
      }

      extraArgs = {
        # Poll every 10 s for pending pods / under-utilised nodes
        scan-interval = "10s"
      }
    })
  ]

  depends_on = [kubernetes_service_account_v1.cluster_autoscaler]
}
