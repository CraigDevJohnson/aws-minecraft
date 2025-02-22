#  Outputs for the prod environment
# Server management outputs
output "server_type" {
  description = "Type of Minecraft server deployed"
  value       = var.server_type
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = module.lambda.function_name
}

output "api_url" {
  description = "API Gateway URL"
  value       = module.lambda.api_url
}

# Server connection information
output "minecraft_connect_info" {
  description = "Connection information for the Minecraft server"
  value = var.server_type == "bedrock" ? (
    "Connect to Bedrock server at: ${module.compute.public_ip}:19132 (UDP)"
    ) : (
    "Connect to Java server at: ${module.compute.public_ip}:25565"
  )
}

output "ssh_command" {
  description = "Command to SSH into the server"
  value       = module.compute.public_ip != null ? "ssh -i ${var.key_name}.pem ubuntu@${module.compute.public_ip}" : "Server IP not available yet"
}
