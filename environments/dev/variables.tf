variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "key_name" {
  description = "Name of the SSH key pair"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"  # Default for Bedrock, override with -var for Java
}

variable "server_type" {
  description = "Type of Minecraft server to deploy (bedrock or java)"
  type        = string
  default     = "bedrock"  # Default to Bedrock, override with -var for Java

  validation {
    condition     = contains(["bedrock", "java"], var.server_type)
    error_message = "server_type must be either 'bedrock' or 'java'"
  }
}