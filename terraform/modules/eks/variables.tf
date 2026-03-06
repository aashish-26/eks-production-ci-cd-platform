variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "vpc_id" {
  description = "VPC id where EKS will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet ids for EKS"
  type        = list(string)
}

variable "tags" {
  description = "Tags for EKS resources"
  type        = map(string)
  default     = {}
}

variable "access_entries" {
  description = "EKS access entries granting IAM principals cluster access"
  type        = any
  default     = {}
}
