output "instance_id" {
  description = "ID of the Minecraft server instance"
  value       = aws_instance.minecraft.id
}

output "public_ip" {
  description = "Public IP of the Minecraft server"
  value       = aws_instance.minecraft.public_ip
}

output "world_data_volume_arn" {
  description = "ARN of the EBS volume used for world data"
  value       = aws_ebs_volume.minecraft_data.arn
}