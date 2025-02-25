variable "server_type" {
  description = "Type of Minecraft server to deploy (bedrock or java)"
  type        = string
  default     = "java"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}

variable "instance_os" {
  description = "Operating system for the EC2 instance"
  type        = string
  default     = "amazon_linux"
}

variable "instance_ami" {
  description = "AMI ID for the EC2 instance"
  type        = string
  default     = null
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

variable "lambda_function_name" {
  description = "Name of the Lambda function"
  type        = string
  default     = "minecraft-server-manager"
}

variable "jwt_token" {
  description = "Static JWT token for API authentication"
  type        = string
  sensitive   = true
}

variable "domain_name" {
  description = "Domain name for JWT issuer"
  type        = string
}