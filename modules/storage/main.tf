terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

module "vault_tags" {
  source        = "../tags"
  resource_name = "backup-vault"
}

module "plan_tags" {
  source        = "../tags"
  resource_name = "backup-plan"
}

module "role_tags" {
  source        = "../tags"
  resource_name = "backup-role"
}

# Create IAM role for AWS Backup with comprehensive permissions
resource "aws_iam_role" "backup" {
  name = "minecraft-${terraform.workspace}-backup-role"

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

  tags = (module.role_tags.tags)
}

# Attach AWS Backup service role policy
resource "aws_iam_role_policy_attachment" "backup_service" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
  role       = aws_iam_role.backup.name
}

# Add comprehensive backup permissions
resource "aws_iam_role_policy" "backup_permissions" {
  name = "minecraft-${terraform.workspace}-backup-permissions"
  role = aws_iam_role.backup.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateSnapshot",
          "ec2:CreateSnapshots",
          "ec2:DeleteSnapshot",
          "ec2:DescribeInstances",
          "ec2:DescribeVolumes",
          "ec2:DescribeSnapshots",
          "ec2:EnableFastSnapshotRestores",
          "ec2:GetEbsEncryptionByDefault",
          "ec2:ModifySnapshotAttribute",
          "ec2:StartInstances",
          "ec2:StopInstances"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "backup:CreateBackupPlan",
          "backup:CreateBackupSelection",
          "backup:CreateBackupVault",
          "backup:DeleteBackupPlan",
          "backup:DeleteBackupSelection",
          "backup:DeleteBackupVault",
          "backup:DescribeBackupJob",
          "backup:DescribeBackupVault",
          "backup:GetBackupPlan",
          "backup:GetBackupSelection",
          "backup:GetBackupVault",
          "backup:ListBackupJobs",
          "backup:ListBackupPlans",
          "backup:ListBackupSelections",
          "backup:ListBackupVaults",
          "backup:PutBackupVaultAccessPolicy",
          "backup:StartBackupJob",
          "backup:StopBackupJob",
          "backup:TagResource",
          "backup:UntagResource",
          "backup-storage:*"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:CreateKey",
          "kms:CreateAlias",
          "kms:DeleteAlias",
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:EnableKey",
          "kms:GenerateDataKey",
          "kms:ListAliases",
          "kms:ListKeys",
          "kms:CreateGrant",
          "kms:RevokeGrant",
          "kms:ListGrants",
          "kms:ReEncrypt*",
          "kms:GenerateDataKeyWithoutPlaintext"
        ]
        Resource = "*"
      }
    ]
  })
}

# Create a backup vault for Minecraft world data
resource "aws_backup_vault" "minecraft" {
  name          = "minecraft-${terraform.workspace}-backup-vault"
  force_destroy = true
  tags          = (module.vault_tags.tags)

  lifecycle {
    prevent_destroy = false
  }
}

# Set up backup plan with daily and weekly backups
resource "aws_backup_plan" "minecraft" {
  name = "minecraft-${terraform.workspace}-backup-plan"
  tags = (module.plan_tags.tags)

  rule {
    rule_name         = "daily_backup"
    target_vault_name = aws_backup_vault.minecraft.name
    schedule          = "cron(0 5 ? * * *)" # Daily at 5 AM UTC

    lifecycle {
      delete_after = var.backup_retention_days
    }

    # Add completion window and start window
    completion_window = "120" # 2 hours
    start_window      = "60"  # 1 hour
  }

  rule {
    rule_name         = "weekly_backup"
    target_vault_name = aws_backup_vault.minecraft.name
    schedule          = "cron(0 5 ? * 1 *)" # Weekly on Sunday at 5 AM UTC

    lifecycle {
      delete_after = var.weekly_backup_retention_days
    }

    completion_window = "180" # 3 hours
    start_window      = "60"  # 1 hour
  }

  lifecycle {
    prevent_destroy = false
  }
}

# Create backup selection with enhanced configuration
resource "aws_backup_selection" "minecraft" {
  name         = "minecraft-${terraform.workspace}-backup-selection"
  plan_id      = aws_backup_plan.minecraft.id
  iam_role_arn = aws_iam_role.backup.arn

  # Select by tags instead of direct resource ARN
  selection_tag {
    type  = "STRINGEQUALS"
    key   = "Environment"
    value = terraform.workspace
  }

  selection_tag {
    type  = "STRINGEQUALS"
    key   = "Project"
    value = "minecraft"
  }
}