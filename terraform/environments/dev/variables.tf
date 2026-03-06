variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "state_bucket" {
  description = "S3 bucket for Terraform state"
  type        = string
}

variable "lock_table" {
  description = "DynamoDB table for state locking"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones. Leave empty to auto-detect the first 3 in the region."
  type        = list(string)
  default     = []
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "eks-dev-cluster"
}

variable "ecr_repo_name" {
  description = "ECR repository name"
  type        = string
  default     = "eks-app"
}

variable "github_repo" {
  description = "GitHub repository in owner/repo format. Scopes the OIDC trust policy."
  type        = string
}
