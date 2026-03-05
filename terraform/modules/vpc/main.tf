# ============================================================
# VPC Module
#
# Provisions a multi-AZ network with:
#   Public subnets   — ALB and NAT Gateway live here
#   Private subnets  — EKS worker nodes (no direct inbound internet)
#   NAT Gateway      — private nodes reach internet via NAT
#                      (pull ECR images, OS patches, etc.)
#
# Subnet discovery tags required by AWS Load Balancer Controller:
#   kubernetes.io/role/elb = 1          (public, internet-facing ALB)
#   kubernetes.io/role/internal-elb = 1 (private, internal ALB)
# ============================================================

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true   # required for EKS API server endpoint
  enable_dns_hostnames = true   # required for EKS API server endpoint

  tags = merge(var.tags, { Name = "eks-vpc" })
}

# --------------------------------
# Internet Gateway
# Provides inbound/outbound internet access for public subnets.
# --------------------------------

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "eks-igw" })
}

# --------------------------------
# Build subnet maps keyed by AZ name.
# Using AZ as the key is more stable than numeric indices and gives
# Terraform a predictable change plan when adding or removing AZs.
# --------------------------------

locals {
  # Map: az-name -> { cidr, az }
  public_subnet_map = {
    for i, az in var.azs : az => {
      cidr = var.public_subnet_cidrs[i]
    }
  }
  private_subnet_map = {
    for i, az in var.azs : az => {
      cidr = var.private_subnet_cidrs[i]
    }
  }
}

# --------------------------------
# Public Subnets
# --------------------------------

resource "aws_subnet" "public" {
  for_each = local.public_subnet_map

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.key
  map_public_ip_on_launch = true   # instances get a public IP for NAT/ALB

  tags = merge(var.tags, {
    Name                     = "eks-public-${each.key}"
    "kubernetes.io/role/elb" = "1"
  })
}

# --------------------------------
# Private Subnets
# --------------------------------

resource "aws_subnet" "private" {
  for_each = local.private_subnet_map

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.cidr
  availability_zone = each.key

  tags = merge(var.tags, {
    Name                              = "eks-private-${each.key}"
    "kubernetes.io/role/internal-elb" = "1"
  })
}

# --------------------------------
# NAT Gateway
# Single NAT GW in one public subnet — cost-effective for dev.
# Note: single NAT = potential single point of failure for node egress.
# For HA production, deploy one NAT GW per AZ.
# --------------------------------

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = merge(var.tags, { Name = "eks-nat-eip" })
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = values(aws_subnet.public)[0].id
  tags          = merge(var.tags, { Name = "eks-nat-gw" })

  depends_on = [aws_internet_gateway.this]
}

# --------------------------------
# Route Tables
# --------------------------------

# Public: all internet traffic via IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = merge(var.tags, { Name = "eks-public-rt" })
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# Private: all internet traffic via NAT GW
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }
  tags = merge(var.tags, { Name = "eks-private-rt" })
}

resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}
