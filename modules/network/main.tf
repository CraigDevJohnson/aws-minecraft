terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

module "vpc_tags" {
  source        = "../tags"
  resource_name = "vpc"
}

module "igw_tags" {
  source        = "../tags"
  resource_name = "igw"
}

module "subnet_tags" {
  source        = "../tags"
  resource_name = "subnet-public"
}

module "rt_tags" {
  source        = "../tags"
  resource_name = "rt-public"
}

resource "aws_vpc" "minecraft" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = (module.vpc_tags.tags)

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_internet_gateway" "minecraft" {
  vpc_id = aws_vpc.minecraft.id

  tags = (module.igw_tags.tags)

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.minecraft.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone       = var.availability_zones[0]
  map_public_ip_on_launch = true

  tags = (module.subnet_tags.tags)

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.minecraft.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.minecraft.id
  }

  tags = (module.rt_tags.tags)

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}