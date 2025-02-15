output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.minecraft.id
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.minecraft.cidr_block
}