output "backup_vault_arn" {
  description = "ARN of the backup vault"
  value       = aws_backup_vault.minecraft.arn
}

output "backup_plan_id" {
  description = "ID of the backup plan"
  value       = aws_backup_plan.minecraft.id
}

output "backup_role_arn" {
  description = "ARN of the IAM role used for backups"
  value       = aws_iam_role.backup.arn
}