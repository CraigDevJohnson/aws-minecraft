variable "environment" {
  description = "Environment name (dev/prod)"
  type        = string
}

variable "minecraft_instance_id" {
  description = "ID of the Minecraft EC2 instance to manage"
  type        = string
}

variable "cors_origin" {
  description = "Allowed CORS origin (your Amplify app URL)"
  type        = string
}