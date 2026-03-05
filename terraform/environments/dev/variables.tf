# ============================================================
# Dev Environment Variables
# All defaults are set for the ap-south-1 (Mumbai) region.
# Override in terraform.tfvars (gitignored — copy from .example).
# ============================================================

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "state_bucket" {
  description = "S3 bucket holding the Terraform state file (created by bootstrap-state.sh)"
  type        = string
}

variable "lock_table" {
  description = "DynamoDB table name used for state locking (created by bootstrap-state.sh)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Explicit list of AZs. Leave empty to auto-detect the first 3 in the region."
  type        = list(string)
  default     = []
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ). Hosts the NAT Gateway and ALB."
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ). Hosts EKS worker nodes."
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "eks-dev-cluster"
}

variable "ecr_repo_name" {
  description = "ECR repository name for the application image"
  type        = string
  default     = "eks-app"
}

variable "github_repo" {
  description = "GitHub repository in owner/repo format (e.g. my-org/my-repo). Scopes the OIDC trust policy to your repo only."
  type        = string
}

variable "grafana_admin_password" {
  description = "Grafana admin password. Pass via -var or terraform.tfvars. Never hardcode."
  type        = string
  sensitive   = true
}
