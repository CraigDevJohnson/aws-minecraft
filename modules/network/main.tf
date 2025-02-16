resource "aws_vpc" "minecraft" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "minecraft-${var.environment}-vpc"
  }
}

resource "aws_internet_gateway" "minecraft" {
  vpc_id = aws_vpc.minecraft.id

  tags = {
    Name = "minecraft-${var.environment}-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.minecraft.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone       = var.availability_zones[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "minecraft-${var.environment}-public"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.minecraft.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.minecraft.id
  }

  tags = {
    Name = "minecraft-${var.environment}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}