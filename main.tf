locals {
  environment = terraform.workspace
}

module "minecraft_environment" {
  source = "./environments/${local.environment}"

  # Pass through variables (these will be overridden by *.auto.tfvars)
  environment                 = local.environment
  key_name                    = var.key_name
  server_type                 = var.server_type
  instance_type               = var.instance_type
  inactivity_shutdown_minutes = var.inactivity_shutdown_minutes
}

