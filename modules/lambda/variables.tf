# Variables for AWS Lambda module configuration.
# This file contains input variables that parameterize the Lambda function deployment,
# allowing customization of the function's configuration, permissions, and runtime settings.
variable "minecraft_instance_id" {
  description = "Unique identifier for the Minecraft server instance"
  type        = string

  validation {
    condition     = length(var.minecraft_instance_id) > 0
    error_message = "minecraft_instance_id cannot be empty"
  }
}

variable "cors_origin" {
  description = "Allowed CORS origin (your Amplify app URL)"
  type        = string
}

variable "lambda_function_name" {
  description = "Name of the Lambda function"
  type        = string
}

variable "jwt_token" {
  description = "Static JWT token for API authentication"
  type        = string
  sensitive   = true
}

variable "domain_name" {
  description = "Domain name for JWT issuer"
  type        = string
}