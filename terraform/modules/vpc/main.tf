resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge({ Name = "eks-vpc" }, var.tags)
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "eks-igw" }
}

# -----------------------------
# Public Route Table
# -----------------------------

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = { Name = "eks-public-rt" }
}

# -----------------------------
# Public Subnets
# -----------------------------

resource "aws_subnet" "public" {
  for_each = { for idx, cidr in var.public_subnet_cidrs : cidr => idx }

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.key
  availability_zone       = element(var.azs, each.value)
  map_public_ip_on_launch = true

  tags = merge({
    Name = "eks-public-${each.value}"
  }, var.tags)
}

resource "aws_route_table_association" "public_assoc" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# -----------------------------
# NAT Gateway
# -----------------------------

resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = values(aws_subnet.public)[0].id

  tags = {
    Name = "eks-nat"
  }

  depends_on = [aws_internet_gateway.gw]
}

# -----------------------------
# Private Route Table
# -----------------------------

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "eks-private-rt"
  }
}

# -----------------------------
# Private Subnets
# -----------------------------

resource "aws_subnet" "private" {
  for_each = { for idx, cidr in var.private_subnet_cidrs : cidr => idx }

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.key
  availability_zone = element(var.azs, each.value)

  tags = merge({
    Name = "eks-private-${each.value}"
  }, var.tags)
}

resource "aws_route_table_association" "private_assoc" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}