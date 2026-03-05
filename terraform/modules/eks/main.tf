# ============================================================
# EKS Module
# Uses the well-maintained terraform-aws-modules/eks module.
# Provisions the EKS control plane, managed node group, and
# automatically enables the OIDC issuer needed for IRSA
# (IAM Roles for Service Accounts).
# ============================================================

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.30"   # LTS version — do not downgrade

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  # Public access is required to run kubectl from local machine / CI runner.
  # Private access keeps pod-to-API-server traffic inside the VPC.
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.medium"]
      min_size       = 1
      max_size        = 5     # raised from 3 to allow Cluster Autoscaler headroom
      desired_size   = 2

      # These labels allow the Cluster Autoscaler to discover and manage
      # this node group via the auto-discovery tag strategy.
      labels = {
        "eks-node-group" = "default"
      }

      # Cluster Autoscaler uses these tags to discover Auto Scaling Groups.
      tags = merge(var.tags, {
        "k8s.io/cluster-autoscaler/enabled"              = "true"
        "k8s.io/cluster-autoscaler/${var.cluster_name}"  = "owned"
      })
    }
  }

  tags = var.tags
}
