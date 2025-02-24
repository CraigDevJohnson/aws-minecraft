variable "ebs_volume_arn" {
  description = "ARN of the EBS volume to backup"
  type        = string
}

variable "backup_retention_days" {
  description = "Number of days to retain daily backups"
  type        = number
  default     = 14
}

variable "weekly_backup_retention_days" {
  description = "Number of days to retain weekly backups"
  type        = number
  default     = 60
}