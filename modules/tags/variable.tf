variable "additional_tags" {
  description = "Additional resource-specific tags"
  type        = map(string)
  default     = {}
}

variable "resource_name" {
  description = "Resource name suffix for standardized naming (e.g., 'vpc', 'subnet-public')"
  type        = string
  default     = null
}