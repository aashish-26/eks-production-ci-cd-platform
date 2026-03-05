terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }

    kubernetes = {
      source = "hashicorp/kubernetes"
    }

    helm = {
      source = "hashicorp/helm"
    }
  }
}

# --------------------------------
# AWS Identity
# --------------------------------

data "aws_caller_identity" "current" {}

# --------------------------------
# EKS Cluster Data
# --------------------------------

data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = var.cluster_name
}

# --------------------------------
# OIDC Configuration
# --------------------------------

locals {
  oidc_provider_host = replace(
    data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer,
    "https://",
    ""
  )

  service_account = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
}

# --------------------------------
# IAM Assume Role Policy
# --------------------------------

data "aws_iam_policy_document" "alb_assume_role" {

  statement {

    effect = "Allow"

    actions = [
      "sts:AssumeRoleWithWebIdentity"
    ]

    principals {
      type = "Federated"

      identifiers = [
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.oidc_provider_host}"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_host}:sub"
      values   = [local.service_account]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

  }
}

# --------------------------------
# IAM Role
# --------------------------------

resource "aws_iam_role" "alb_controller" {

  name = "AmazonEKSLoadBalancerControllerRole-${var.cluster_name}"

  assume_role_policy = data.aws_iam_policy_document.alb_assume_role.json
}

# --------------------------------
# IAM Policy
# --------------------------------

resource "aws_iam_policy" "alb_policy" {

  name   = "AWSLoadBalancerControllerIAMPolicy-${var.cluster_name}"
  policy = file("${path.module}/iam-policy.json")
}

resource "aws_iam_role_policy_attachment" "alb_attach" {

  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_policy.arn
}

# --------------------------------
# Kubernetes Service Account (IRSA)
# --------------------------------

resource "kubernetes_service_account_v1" "alb_sa" {

  metadata {

    name      = var.service_account_name
    namespace = var.namespace

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.alb_controller.arn
    }

  }

}

# --------------------------------
# Install AWS Load Balancer Controller
# --------------------------------

resource "helm_release" "alb_controller" {

  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"

  namespace = var.namespace

  values = [
    yamlencode({
      clusterName = var.cluster_name
      region      = var.region
      vpcId       = var.vpc_id

      serviceAccount = {
        create = false
        name   = var.service_account_name
      }
    })
  ]

  depends_on = [
    kubernetes_service_account_v1.alb_sa,
    aws_iam_role_policy_attachment.alb_attach
  ]

}