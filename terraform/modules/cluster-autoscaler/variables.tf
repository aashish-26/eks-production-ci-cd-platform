variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "region" {
  description = "AWS region the cluster is deployed in"
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC provider URL of the EKS cluster (without https://). Used to scope the IAM trust policy."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace where the Cluster Autoscaler pod runs"
  type        = string
  default     = "kube-system"
}

variable "service_account_name" {
  description = "Kubernetes service account name for the Cluster Autoscaler"
  type        = string
  default     = "cluster-autoscaler"
}

variable "tags" {
  description = "Tags to apply to IAM resources"
  type        = map(string)
  default     = {}
}
