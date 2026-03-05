provider "aws" {
  region = var.aws_region
}

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
}

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