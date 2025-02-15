locals {
  backup_vault_name = "minecraft-${var.environment}-backup-vault"
}

# Create a backup vault for Minecraft world data
resource "aws_backup_vault" "minecraft" {
  name = "minecraft-${var.environment}-backup-vault"
  force_destroy = true
  
  tags = {
    Environment = var.environment
    Project     = "minecraft"
  }
}

# Set up backup plan with daily and weekly backups
resource "aws_backup_plan" "minecraft" {
  name = "minecraft-${var.environment}-backup-plan"

  rule {
    rule_name         = "daily_backup"
    target_vault_name = aws_backup_vault.minecraft.name
    schedule          = "cron(0 2 * * ? *)"  # Daily at 2 AM UTC

    lifecycle {
      delete_after = var.backup_retention_days
    }
  }

  rule {
    rule_name         = "weekly_backup"
    target_vault_name = aws_backup_vault.minecraft.name
    schedule          = "cron(0 3 ? * SUN *)"  # Weekly on Sunday at 3 AM UTC

    lifecycle {
      delete_after = var.weekly_backup_retention_days
    }
  }

  tags = {
    Environment = var.environment
    Project     = "minecraft"
  }
}

# Create IAM role for AWS Backup
resource "aws_iam_role" "backup" {
  name = "minecraft-${var.environment}-backup-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Environment = var.environment
    Project     = "minecraft"
  }
}

# Attach AWS Backup service role policy
resource "aws_iam_role_policy_attachment" "backup" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
  role       = aws_iam_role.backup.name
}

# Create backup selection to specify what to backup
resource "aws_backup_selection" "minecraft" {
  name         = "minecraft-${var.environment}-backup-selection"
  plan_id      = aws_backup_plan.minecraft.id
  iam_role_arn = aws_iam_role.backup.arn

  resources = [
    var.ebs_volume_arn
  ]
}