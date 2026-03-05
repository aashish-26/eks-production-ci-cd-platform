locals {
  azs         = length(var.azs) > 0 ? var.azs : slice(data.aws_availability_zones.available.names, 0, 3)
  common_tags = { Environment = "dev" }
}

data "aws_availability_zones" "available" {}

module "vpc" {
  source = "../../modules/vpc"

  vpc_cidr            = var.vpc_cidr
  azs                 = local.azs
  public_subnet_cidrs = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs

  tags = local.common_tags
}

module "ecr" {
  source = "../../modules/ecr"

  name = var.ecr_repo_name

  tags = local.common_tags
}

module "eks" {
  source = "../../modules/eks"

  cluster_name = var.cluster_name
  vpc_id       = module.vpc.vpc_id

  # Only private subnets for worker nodes
  subnet_ids = module.vpc.private_subnets

  tags = local.common_tags
}

output "ecr_repo" {
  value = module.ecr.repository_url
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

module "alb" {
  source = "../../modules/alb"

  cluster_name         = module.eks.cluster_name
  namespace            = "kube-system"
  service_account_name = "aws-load-balancer-controller"
  region               = var.aws_region
  vpc_id               = module.eks.vpc_id
}