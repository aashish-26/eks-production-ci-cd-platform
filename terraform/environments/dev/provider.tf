# ============================================================
# Provider Configuration
#
# Three providers are used together:
#   aws        — provisions all AWS resources
#   kubernetes — creates K8s objects (ServiceAccounts, Namespaces)
#   helm       — installs Helm charts into the cluster
#
# The kubernetes and helm providers both need the cluster endpoint
# and credentials, which are sourced from data sources after EKS
# is provisioned. Terraform handles the ordering automatically.
# ============================================================

provider "aws" {
  region = var.aws_region
}

# --------------------------------
# EKS authentication data sources
# --------------------------------

# Fetches the cluster endpoint and CA certificate
data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_name
}

# Fetches a short-lived bearer token (valid ~15 minutes)
data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
}

# --------------------------------
# Shared connection details
# Defined once in locals, referenced by both providers below
# to avoid copy-paste drift.
# --------------------------------
locals {
  k8s_host    = data.aws_eks_cluster.cluster.endpoint
  k8s_token   = data.aws_eks_cluster_auth.cluster.token
  k8s_ca_cert = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
}

provider "kubernetes" {
  host                   = local.k8s_host
  token                  = local.k8s_token
  cluster_ca_certificate = local.k8s_ca_cert
}

provider "helm" {
  kubernetes = {
    host                   = local.k8s_host
    token                  = local.k8s_token
    cluster_ca_certificate = local.k8s_ca_cert
  }
}
