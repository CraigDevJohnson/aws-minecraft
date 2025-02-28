terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Get current region
data "aws_region" "current" {}

data "aws_ami" "ubuntu" {
  most_recent = true             # Always fetch the latest available AMI
  owners      = ["099720109477"] // Canonical's AWS account ID

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  # Map of files to be imported
  import_files = {
    for key, file in local.files :
    key => {
      name     = file.name
      filename = file.filename
      path     = file.path
      version  = file.version
      etag     = filemd5(file.path)
      content  = base64encode(replace(file(file.path), "\r\n", "\n"))
      type     = file.type
    }
  }

  server_config = {
    server_type              = var.server_type
    bucket_name              = aws_s3_bucket.file_imports.id
    install_java_script      = local.import_files["install_java"].name
    install_bedrock_script   = local.import_files["install_bedrock"].name
    run_server_script        = local.import_files["run_server"].name
    world_backup_script      = local.import_files["world_backup"].name
    validate_script          = local.import_files["validate_all"].name
    test_server_script       = local.import_files["test_server"].name
    test_world_backup_script = local.import_files["test_world_backup"].name
    java_properties          = local.import_files["java_properties"].name
    bedrock_properties       = local.import_files["bedrock_properties"].name
    imds_endpoint            = "169.254.169.254"
    imds_token_ttl           = "21600"
    inactivity_minutes       = var.inactivity_shutdown_minutes
  }
  # Map of AMIs based on OS
  instance_ami = {
    ubuntu       = data.aws_ami.ubuntu.id
    amazon_linux = data.aws_ami.amazon_linux.id
  }

  # Create base64 encoded config
  config_json = base64encode(jsonencode(local.server_config))
  # User data to be passed to the instance
  minimal_user_data = <<-EOF
#!/bin/bash
# Write configuration to file
echo '${local.config_json}' | base64 -d > /tmp/server_config.json

# Download and run setup script
aws s3 cp s3://${aws_s3_bucket.file_imports.id}/user_data.sh /tmp/minecraft_setup.sh
chmod +x /tmp/minecraft_setup.sh
/tmp/minecraft_setup.sh /tmp/server_config.json
EOF
}

module "tags" {
  source = "../tags"

  additional_tags = {
    ServerType = var.server_type
    Name       = "minecraft-${terraform.workspace}-${var.server_type}-server"
  }
}

module "instance_tags" {
  source        = "../tags"
  resource_name = "${var.server_type}-server"
  additional_tags = {
    ServerType = var.server_type
  }
}

module "ebs_tags" {
  source        = "../tags"
  resource_name = "${var.server_type}-data"
}

module "role_tags" {
  source        = "../tags"
  resource_name = "server-role"
}

module "bucket_tags" {
  source        = "../tags"
  resource_name = "file-imports"
}

# Create S3 bucket for file imports with minimal configuration
resource "aws_s3_bucket" "file_imports" {
  bucket_prefix = "minecraft-${terraform.workspace}-file-imports-"
  force_destroy = true

  lifecycle {
    prevent_destroy = false # Prevent accidental deletion of file imports bucket
  }

  tags = (module.bucket_tags.tags)
}

# Ensure the bucket is private
resource "aws_s3_bucket_public_access_block" "file_imports" {
  bucket = aws_s3_bucket.file_imports.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Configure bucket versioning
resource "aws_s3_bucket_versioning" "file_imports" {
  bucket = aws_s3_bucket.file_imports.id
  versioning_configuration {
    status = "Disabled" # Changed from "Suspended" to "Disabled"
  }
}

# Add bucket lifecycle rule to clean up old versions
resource "aws_s3_bucket_lifecycle_configuration" "file_imports" {
  bucket = aws_s3_bucket.file_imports.id

  rule {
    id     = "cleanup_old_versions"
    status = "Enabled"

    expiration {
      # if prod environment, delete old versions after 30 days, otherwise delete after 1 day
      days = terraform.workspace == "prod" ? 30 : 1 # Set retention based on environment
    }

    noncurrent_version_expiration {
      noncurrent_days = terraform.workspace == "prod" ? 30 : 1
    }
  }
}

# Upload file_imports to S3 with proper encoding and metadata
resource "aws_s3_object" "file_imports" {
  for_each = local.import_files

  bucket         = aws_s3_bucket.file_imports.id
  key            = each.key
  content_base64 = each.value.content
  content_type   = each.value.type
  etag           = each.value.etag
  force_destroy  = true

  metadata = {
    "version"                   = each.value.version
    "content-transfer-encoding" = "base64"
    "permissions"               = "0755"
    "original-filename"         = each.key
  }
  tags = merge(
    module.tags.tags,
    {
      FileVersion = each.value.version
    }
  )

  lifecycle {
    ignore_changes = [
      etag,
      content_base64,
      tags_all
    ]
  }
}

# Add explicit bucket policy
resource "aws_s3_bucket_policy" "file_imports" {
  bucket = aws_s3_bucket.file_imports.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEC2Access"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.minecraft_server.arn
        }
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.file_imports.arn,
          "${aws_s3_bucket.file_imports.arn}/*"
        ]
      }
    ]
  })
}

# Add ownership controls
resource "aws_s3_bucket_ownership_controls" "file_imports" {
  bucket = aws_s3_bucket.file_imports.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# Create IAM role for EC2 to access S3
resource "aws_iam_role" "minecraft_server" {
  name = "minecraft-${terraform.workspace}-server-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = (module.role_tags.tags)

  lifecycle {
    prevent_destroy = false
  }
}

# Allow EC2 to access file_imports bucket and AWS Backup
resource "aws_iam_role_policy" "minecraft_server" {
  name = "minecraft-${terraform.workspace}-server-policy"
  role = aws_iam_role.minecraft_server.id

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Action" : [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:GetObjectVersion"
        ],
        "Effect" : "Allow",
        "Resource" : "arn:aws:s3:::minecraft-*-file_imports-*"
      },
      {
        "Action" : [
          "ssm:DescribeAssociation",
          "ssm:GetDeployablePatchSnapshotForInstance",
          "ssm:GetDocument",
          "ssm:DescribeDocument",
          "ssm:GetManifest",
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:ListAssociations",
          "ssm:ListInstanceAssociations",
          "ssm:PutInventory",
          "ssm:PutComplianceItems",
          "ssm:PutConfigurePackageResult",
          "ssm:UpdateAssociationStatus",
          "ssm:UpdateInstanceAssociationStatus",
          "ssm:UpdateInstanceInformation",
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ],
        "Effect" : "Allow",
        "Resource" : "*"
      },
      {
        "Action" : [
          "ec2messages:AcknowledgeMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:FailMessage",
          "ec2messages:GetEndpoint",
          "ec2messages:GetMessages",
          "ec2messages:SendReply"
        ],
        "Effect" : "Allow",
        "Resource" : "*"
      },
      {
        "Action" : [
          "backup:StartBackupJob",
          "backup:DescribeBackupVault",
          "backup:CreateBackupVault",
          "backup:DeleteBackupVault",
          "backup:GetBackupVaultAccessPolicy",
          "backup:PutBackupVaultAccessPolicy",
          "backup:DeleteBackupVaultAccessPolicy",
          "backup:GetBackupPlan",
          "backup:GetBackupSelection",
          "backup:ListBackupJobs",
          "backup:ListBackupVaults",
          "backup:ListRecoveryPointsByBackupVault",
          "backup:ListBackupPlans",
          "backup:ListBackupSelections"
        ],
        "Effect" : "Allow",
        "Resource" : "*"
      },
      {
        "Action" : [
          "kms:CreateKey",
          "kms:CreateAlias",
          "kms:DeleteAlias",
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey",
          "kms:ListAliases",
          "kms:ListKeys"
        ],
        "Effect" : "Allow",
        "Resource" : "*"
      },
      {
        "Action" : [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ],
        "Effect" : "Allow",
        "Resource" : "arn:aws:logs:*:*:*"
      },
      {
        "Action" : [
          "ec2:DescribeVolumes",
          "ec2:AttachVolume",
          "ec2:DetachVolume",
          "ec2:DescribeTags"
        ],
        "Effect" : "Allow",
        "Resource" : "*"
      },
      {
        "Action" : [
          "iam:GetRole",
          "iam:PassRole"
        ],
        "Effect" : "Allow",
        "Resource" : "arn:aws:iam::*:role/minecraft-*-backup-role"
      }
    ]
  })
}

# Create instance profile
resource "aws_iam_instance_profile" "minecraft_server" {
  name = "minecraft-${terraform.workspace}-server-profile"
  role = aws_iam_role.minecraft_server.name
}

// Create a persistent EBS volume for world data
resource "aws_ebs_volume" "minecraft_data" {
  availability_zone = var.availability_zone
  size              = var.world_data_volume_size
  type              = var.world_data_volume_type
  iops              = var.world_data_volume_type == "gp3" ? var.world_data_volume_iops : null

  tags = (module.ebs_tags.tags)

  lifecycle {
    prevent_destroy = false # Prevent accidental destruction of world data
  }
}

resource "aws_instance" "minecraft" {
  ami               = local.instance_ami[var.instance_os]
  instance_type     = var.instance_type
  subnet_id         = var.subnet_id
  availability_zone = var.availability_zone

  vpc_security_group_ids = [var.security_group_id]
  key_name               = "minecraft-${terraform.workspace}-key"
  iam_instance_profile   = aws_iam_instance_profile.minecraft_server.name

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }
  user_data = local.minimal_user_data

  tags = (module.instance_tags.tags)

  # Add lifecycle block to prevent unnecessary recreations
  # lifecycle {
  #   ignore_changes = [
  #     user_data,
  #     user_data_base64,
  #   ]
  # }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }
}

# CloudWatch alarm for server inactivity
resource "aws_cloudwatch_metric_alarm" "no_players_shutdown" {
  count               = var.inactivity_shutdown_minutes > 0 ? 1 : 0
  alarm_name          = "minecraft-${terraform.workspace}-no-players"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.inactivity_shutdown_minutes
  metric_name         = "NetworkPacketsIn"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors server inactivity"
  alarm_actions       = ["arn:aws:automate:${data.aws_region.current.name}:ec2:stop"]

  dimensions = {
    InstanceId = aws_instance.minecraft.id
  }
}

# Attach the EBS volume to the instance
resource "aws_volume_attachment" "minecraft_data" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.minecraft_data.id
  instance_id = aws_instance.minecraft.id

  // Stop instance before detaching, important for data consistency
  force_detach = false
}

