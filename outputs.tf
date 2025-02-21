output "minecraft_connect_info" {
  description = "Connection information for the Minecraft server"
  value       = module.minecraft_environment.minecraft_connect_info
}

output "server_type" {
  description = "Type of Minecraft server deployed"
  value       = module.minecraft_environment.server_type
}

output "ssh_command" {
  description = "Command to SSH into the server"
  value       = module.minecraft_environment.ssh_command
}
