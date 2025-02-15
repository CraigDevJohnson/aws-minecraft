output "instance_id" {
  description = "ID of the Minecraft server instance"
  value       = aws_instance.minecraft.id
}

output "public_ip" {
  description = "Public IP of the Minecraft server"
  value       = aws_instance.minecraft.public_ip
}