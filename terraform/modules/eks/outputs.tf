# Upstream cluster endpoint (used by the Kubernetes and Helm providers
# in the root environment to authenticate kubectl/helm commands).
output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

# Pass vpc_id through so callers do not need to pass it separately
# to every downstream module (e.g. the ALB module).
output "vpc_id" {
  description = "VPC ID the cluster was deployed into"
  value       = var.vpc_id
}

# OIDC issuer URL — used by IRSA modules (ALB controller, Cluster Autoscaler)
# to build IAM trust policies scoped to specific service accounts.
output "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider (needed to create IRSA roles)"
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider_url" {
  description = "URL of the EKS OIDC provider (without https://)"
  value       = module.eks.oidc_provider
}

output "node_security_group_id" {
  description = "Security group ID attached to the managed node group instances"
  value       = module.eks.node_security_group_id
}
