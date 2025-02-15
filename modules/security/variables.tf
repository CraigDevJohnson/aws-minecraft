variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "server_type" {
  description = "Type of Minecraft server to deploy (bedrock or java)"
  type        = string
  default     = "bedrock"
}