variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "server_type" {
  description = "Type of Minecraft server to deploy (bedrock or java)"
  type        = string
  default     = "bedrock"
}