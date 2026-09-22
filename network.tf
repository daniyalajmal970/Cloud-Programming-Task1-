# ---------------------------------------------------------------------------
# Networking: one VPC, a public and a private subnet in each Availability Zone
# ---------------------------------------------------------------------------

data "aws_availability_zones" "available" {
  #checkov:skip=CKV_AWS_394:Only the first var.az_count zones are used via slice(), so new AZs do not change the result.
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)
}

resource "aws_vpc" "main" {
  #checkov:skip=CKV2_AWS_11:Flow logs are omitted to stay within the free tier for this course project.
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project_name}-vpc" }
}

# Lock down the VPC's default security group (nothing should use it).
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-default-sg-locked" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-igw" }
}

# Public subnets (10.0.1.0/24, 10.0.2.0/24, ...) host only the load balancer.
resource "aws_subnet" "public" {
  count = var.az_count

  vpc_id            = aws_vpc.main.id
  availability_zone = local.azs[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 1)

  tags = { Name = "${var.project_name}-public-${local.azs[count.index]}" }
}

# Private subnets (10.0.11.0/24, 10.0.12.0/24, ...) host the web servers.
# They have no route to the internet at all.
resource "aws_subnet" "private" {
  count = var.az_count

  vpc_id            = aws_vpc.main.id
  availability_zone = local.azs[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 11)

  tags = { Name = "${var.project_name}-private-${local.azs[count.index]}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.project_name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = var.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private route table: only local VPC traffic + the S3 gateway endpoint route.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-private-rt" }
}

resource "aws_route_table_association" "private" {
  count          = var.az_count
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Free S3 gateway endpoint: lets the private instances reach the Amazon Linux
# package repositories (hosted on S3) without a paid NAT gateway.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = { Name = "${var.project_name}-s3-endpoint" }
}

# Optional interface endpoints for SSM Session Manager (shell access without SSH).
resource "aws_vpc_endpoint" "ssm" {
  for_each = var.enable_ssm_endpoints ? toset(["ssm", "ssmmessages", "ec2messages"]) : toset([])

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  tags = { Name = "${var.project_name}-${each.key}-endpoint" }
}
