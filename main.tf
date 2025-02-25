# Environment configuration
locals {
  environment = terraform.workspace
}

# Environment-specific module loading
module "minecraft_environment" {
  source = "./environments/${local.environment}"

  # Server configuration
  server_type    = var.server_type
  instance_type  = var.instance_type
  instance_os    = var.instance_os
  instance_state = var.instance_state
  domain_name    = var.domain_name
  jwt_token      = var.jwt_token

  # Management configuration
  inactivity_shutdown_minutes = var.inactivity_shutdown_minutes
  lambda_function_name        = var.lambda_function_name
}