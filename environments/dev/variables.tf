variable "environment" {
  description = "Environment name"
  type        = string
}

variable "key_name" {
  description = "Name of the SSH key pair"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"
}

variable "server_type" {
  description = "Type of Minecraft server to deploy (bedrock or java)"
  type        = string
  default     = "bedrock"

  validation {
    condition     = contains(["bedrock", "java"], var.server_type)
    error_message = "server_type must be either 'bedrock' or 'java'"
  }
}

variable "inactivity_shutdown_minutes" {
  description = "Number of minutes of inactivity before shutting down the server (0 to disable)"
  type        = number
  default     = 30

  validation {
    condition     = var.inactivity_shutdown_minutes >= 0
    error_message = "inactivity_shutdown_minutes must be a non-negative number"
  }
}