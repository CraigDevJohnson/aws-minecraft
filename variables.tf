variable "key_name" {
  description = "Name of the SSH key pair"
  type        = string
  default     = null # Optional, will be set by environment auto.tfvars
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = null # Optional, will be set by workspace name
}

variable "server_type" {
  description = "Type of Minecraft server to deploy (bedrock or java)"
  type        = string
  default     = "bedrock"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"
}

variable "instance_state" {
  description = "Desired state of the EC2 instance (running or stopped)"
  type        = string
  default     = "running"
}

variable "inactivity_shutdown_minutes" {
  description = "Number of minutes of inactivity before shutting down the server (0 to disable)"
  type        = number
  default     = 30
}