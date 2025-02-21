output "minecraft_connect_info" {
  description = "Connection information for the Minecraft server"
  value = var.server_type == "bedrock" ? (
    "Connect to Bedrock server at: ${module.compute.public_ip}:19132 (UDP)"
    ) : (
    "Connect to Java server at: ${module.compute.public_ip}:25565"
  )
}

output "server_type" {
  description = "Type of Minecraft server deployed"
  value       = var.server_type
}

output "ssh_command" {
  description = "Command to SSH into the server"
  value       = "ssh -i ${var.key_name}.pem ubuntu@${module.compute.public_ip}"
}
