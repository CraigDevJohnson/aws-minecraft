output "security_group_id" {
  description = "ID of the Minecraft server security group"
  value       = aws_security_group.minecraft.id
}