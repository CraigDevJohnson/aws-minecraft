output "backup_vault_arn" {
  description = "ARN of the backup vault"
  value       = aws_backup_vault.minecraft.arn
}

output "backup_vault_name" {
  description = "Name of the AWS Backup vault"
  value       = aws_backup_vault.minecraft.name
}

output "backup_plan_id" {
  description = "ID of the AWS Backup plan"
  value       = aws_backup_plan.minecraft.id
}

output "backup_role_arn" {
  description = "ARN of the IAM role used for backups"
  value       = aws_iam_role.backup.arn
}

output "backup_selection_name" {
  description = "Name of the backup selection"
  value       = try(aws_backup_selection.minecraft.name, "")
}

output "backup_selection_arn" {
  description = "ARN of the AWS Backup selection"
  value       = try(aws_backup_selection.minecraft.id, "")
}

output "backup_testing_command" {
  description = "Command to run backup testing"
  value       = var.ebs_volume_arn != "" ? "bash test_backup.sh ${aws_backup_vault.minecraft.name} ${aws_backup_plan.minecraft.id} ${aws_backup_selection.minecraft.id} ${var.ebs_volume_arn}" : ""
}