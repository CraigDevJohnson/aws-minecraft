variable "subnet_id" {
  description = "ID of the subnet to launch the instance in"
  type        = string
}

variable "security_group_id" {
  description = "ID of the security group for the instance"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "instance_os" {
  description = "Operating system for the instance (e.g., ubuntu, amazon_linux)"
  type        = string
  default     = "amazon_linux"

  validation {
    condition     = contains(["ubuntu", "amazon_linux"], var.instance_os)
    error_message = "instance_os must be either 'ubuntu' or 'amazon_linux'"
  }
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

variable "world_data_volume_size" {
  description = "Size of the EBS volume for world data (in GB)"
  type        = number
  default     = 50
}

variable "world_data_volume_type" {
  description = "Type of EBS volume for world data"
  type        = string
  default     = "gp3"
}

variable "world_data_volume_iops" {
  description = "IOPS for the EBS volume (only for gp3)"
  type        = number
  default     = 3000
}

variable "availability_zone" {
  description = "Availability zone to launch the instance and create the EBS volume in"
  type        = string
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

variable "user_data" {
  description = "User data script for EC2 instance initialization"
  type        = string
  default     = null

  validation {
    condition     = var.user_data == null ? true : length(var.user_data) <= 16384
    error_message = "User data must not exceed 16384 bytes (16KB AWS limit)"
  }
}

