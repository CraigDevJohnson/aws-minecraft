#  main Outputs
# Server management outputs
output "server_type" {
  description = "Type of Minecraft server deployed"
  value       = module.minecraft_environment.server_type
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = module.minecraft_environment.lambda_function_name
}

output "api_url" {
  description = "URL of the API Gateway v2 endpoint"
  value       = module.minecraft_environment.api_url
}

# Server connection information
output "minecraft_connect_info" {
  description = "Connection information for the Minecraft server"
  value       = module.minecraft_environment.minecraft_connect_info
}

output "ssh_command" {
  description = "Command to SSH into the server"
  value       = module.minecraft_environment.ssh_command
}
