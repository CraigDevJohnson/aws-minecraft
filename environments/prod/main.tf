terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

module "network" {
  source = "../../modules/network"

  environment        = var.environment
  vpc_cidr           = "10.0.0.0/16"
  availability_zones = ["us-west-2a"]
}

module "security" {
  source = "../../modules/security"

  environment = var.environment
  vpc_id      = module.network.vpc_id
  server_type = var.server_type
}

module "compute" {
  source = "../../modules/compute"

  environment                 = var.environment
  subnet_id                   = module.network.public_subnet_id
  security_group_id           = module.security.security_group_id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  server_type                 = var.server_type
  availability_zone           = "us-west-2a"
  world_data_volume_size      = 100 # Larger volume for production
  world_data_volume_type      = "gp3"
  world_data_volume_iops      = 3000
  inactivity_shutdown_minutes = var.inactivity_shutdown_minutes
}

module "storage" {
  source = "../../modules/storage"

  environment    = var.environment
  ebs_volume_arn = module.compute.world_data_volume_arn

  depends_on = [module.compute]
}

module "lambda" {
  source = "../../modules/lambda"

  environment           = var.environment
  minecraft_instance_id = module.compute.instance_id
  cors_origin           = "*" # Update this with your actual domain when ready

  depends_on = [module.compute]
}