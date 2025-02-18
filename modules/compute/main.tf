data "aws_ami" "ubuntu" {
  most_recent = true
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

locals {
  script_path = var.server_type == "bedrock" ? "${path.module}/scripts/install_bedrock.sh" : "${path.module}/scripts/install_java.sh"

  # Add hash suffix to script names for versioning
  script_names = {
    "install.sh"      = "install-${md5(file(local.script_path))}.sh"
    "test_server.sh"  = "test_server-${md5(file("${path.module}/scripts/test_server.sh"))}.sh"
    "validate_all.sh" = "validate_all-${md5(file("${path.module}/scripts/validate_all.sh"))}.sh"
    "test_backup.sh"  = "test_backup-${md5(file("${path.module}/scripts/../../storage/scripts/test_backup.sh"))}.sh"
  }

  # Function to convert Windows line endings to Unix
  script_content = { for k, v in {
    "install.sh"      = file(local.script_path)
    "test_server.sh"  = file("${path.module}/scripts/test_server.sh")
    "validate_all.sh" = file("${path.module}/scripts/validate_all.sh")
    "test_backup.sh"  = file("${path.module}/scripts/../../storage/scripts/test_backup.sh")
  } : k => base64encode(replace(v, "\r\n", "\n")) }
}

# Create S3 bucket for scripts with minimal configuration
resource "aws_s3_bucket" "scripts" {
  bucket_prefix = "minecraft-${var.environment}-scripts-"
  force_destroy = true
}

# Ensure the bucket is private
resource "aws_s3_bucket_public_access_block" "scripts" {
  bucket = aws_s3_bucket.scripts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Configure bucket versioning
resource "aws_s3_bucket_versioning" "scripts" {
  bucket = aws_s3_bucket.scripts.id
  versioning_configuration {
    status = "Disabled" # Changed from "Suspended" to "Disabled"
  }
}

# Add bucket lifecycle rule to clean up old versions
resource "aws_s3_bucket_lifecycle_configuration" "scripts" {
  bucket = aws_s3_bucket.scripts.id

  rule {
    id     = "cleanup_old_versions"
    status = "Enabled"

    expiration {
      days = 1 # Short retention for dev environment
    }

    noncurrent_version_expiration {
      noncurrent_days = 1
    }
  }
}

# Upload scripts to S3 with proper encoding and metadata
resource "aws_s3_object" "test_scripts" {
  for_each = local.script_content

  bucket         = aws_s3_bucket.scripts.id
  key            = local.script_names[each.key] # Use versioned filename
  content_base64 = each.value
  content_type   = "text/x-shellscript"
  etag           = md5(each.value)
  force_destroy  = true

  # Add server-side encryption
  server_side_encryption = "AES256"

  # Ensure proper content encoding and permissions
  metadata = {
    "content-transfer-encoding" = "base64"
    "permissions"               = "0755" # Ensure scripts are executable
    "original-filename"         = each.key
  }
}

# Add explicit bucket policy
resource "aws_s3_bucket_policy" "scripts" {
  bucket = aws_s3_bucket.scripts.id

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
          aws_s3_bucket.scripts.arn,
          "${aws_s3_bucket.scripts.arn}/*"
        ]
      }
    ]
  })
}

# Add ownership controls
resource "aws_s3_bucket_ownership_controls" "scripts" {
  bucket = aws_s3_bucket.scripts.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# Create IAM role for EC2 to access S3
resource "aws_iam_role" "minecraft_server" {
  name = "minecraft-${var.environment}-server-role"

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
}

# Allow EC2 to access script bucket and AWS Backup
resource "aws_iam_role_policy" "minecraft_server" {
  name = "minecraft-${var.environment}-server-policy"
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
        "Resource" : "arn:aws:s3:::minecraft-*-scripts-*"
      },
      {
        "Action" : [
          "backup:StartBackupJob",
          "backup:DescribeBackupVault",
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
          "iam:GetRole"
        ],
        "Effect" : "Allow",
        "Resource" : "arn:aws:iam::*:role/minecraft-*-backup-role"
      }
    ]
  })
}

# Create instance profile
resource "aws_iam_instance_profile" "minecraft_server" {
  name = "minecraft-${var.environment}-server-profile"
  role = aws_iam_role.minecraft_server.name
}

# Create a persistent EBS volume for world data
resource "aws_ebs_volume" "minecraft_data" {
  availability_zone = var.availability_zone
  size              = var.world_data_volume_size
  type              = var.world_data_volume_type
  iops              = var.world_data_volume_type == "gp3" ? var.world_data_volume_iops : null

  tags = {
    Name = "minecraft-${var.environment}-${var.server_type}-data"
  }
  // WILL ADD IN PROD BUT NOT DEV
  # lifecycle {
  #   prevent_destroy = true  # Prevent accidental deletion of world data
  # }
}

resource "aws_instance" "minecraft" {
  ami               = data.aws_ami.ubuntu.id
  instance_type     = var.instance_type
  subnet_id         = var.subnet_id
  availability_zone = var.availability_zone // Ensure instance is in same AZ as the EBS volume

  vpc_security_group_ids = [var.security_group_id]
  key_name               = var.key_name
  iam_instance_profile   = aws_iam_instance_profile.minecraft_server.name

  root_block_device {
    volume_size = var.server_type == "bedrock" ? 10 : 20
    volume_type = "gp3"
  }

  user_data = templatefile(
    "${path.module}/scripts/user_data.sh",
    {
      server_type        = var.server_type
      bucket_name        = aws_s3_bucket.scripts.id
      install_key        = local.script_names["install.sh"]
      test_server_script = local.script_names["test_server.sh"]
      validate_script    = local.script_names["validate_all.sh"]
      backup_script      = local.script_names["test_backup.sh"]
      imds_endpoint      = "169.254.169.254"
      imds_token_ttl     = "21600"
    }
  )

  user_data_replace_on_change = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  tags = {
    Name        = "minecraft-${var.environment}-${var.server_type}-server"
    Environment = var.environment
    ServerType  = var.server_type
    Managed     = "terraform"
    CreatedAt   = timestamp()
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

