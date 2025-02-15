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
  vpc_cidr    = module.network.vpc_cidr
  server_type = var.server_type
}

module "compute" {
  source = "../../modules/compute"

  environment       = var.environment
  subnet_id         = module.network.public_subnet_id
  security_group_id = module.security.security_group_id
  instance_type     = var.instance_type
  key_name          = var.key_name
  server_type       = var.server_type
}