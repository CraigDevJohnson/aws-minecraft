output "minecraft_server_ip" {
  description = "Public IP of the Minecraft server"
  value       = module.compute.public_ip
}

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
  value       = "ssh -i C:/dev/keys/${var.key_name}.pem ubuntu@${module.compute.public_ip}"
}

# Backup configuration outputs
output "backup_vault_name" {
  description = "Name of the AWS Backup vault"
  value       = module.storage.backup_vault_name
}

output "backup_vault_arn" {
  description = "ARN of the AWS Backup vault"
  value       = module.storage.backup_vault_arn
}

output "backup_plan_id" {
  description = "ID of the AWS Backup plan"
  value       = module.storage.backup_plan_id
}

output "backup_selection_arn" {
  description = "ARN of the backup selection"
  value       = module.storage.backup_selection_arn
}

output "backup_role_arn" {
  description = "ARN of the IAM role used for backups"
  value       = module.storage.backup_role_arn
}

output "backup_testing_command" {
  description = "Command to run backup validation tests"
  value       = module.storage.backup_testing_command
}