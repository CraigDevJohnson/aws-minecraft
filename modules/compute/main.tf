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
  script_content = {
    "install.sh"      = file(local.script_path)
    "test_server.sh"  = file("${path.module}/scripts/test_server.sh")
    "validate_all.sh" = file("${path.module}/scripts/validate_all.sh")
    "test_backup.sh"  = file("${path.module}/scripts/../../storage/scripts/test_backup.sh")
  }
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

# Enable versioning for script history
resource "aws_s3_bucket_versioning" "scripts" {
  bucket = aws_s3_bucket.scripts.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Upload scripts to S3
resource "aws_s3_object" "test_scripts" {
  for_each = local.script_content

  bucket  = aws_s3_bucket.scripts.id
  key     = each.key
  content = each.value
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

# Allow EC2 to access script bucket
resource "aws_iam_role_policy" "minecraft_server" {
  name = "minecraft-${var.environment}-server-policy"
  role = aws_iam_role.minecraft_server.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = [
          "${aws_s3_bucket.scripts.arn}/*"
        ]
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
  size             = var.world_data_volume_size
  type             = var.world_data_volume_type
  iops             = var.world_data_volume_type == "gp3" ? var.world_data_volume_iops : null

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
  availability_zone = var.availability_zone  // Ensure instance is in same AZ as the EBS volume

  vpc_security_group_ids = [var.security_group_id]
  key_name              = var.key_name
  iam_instance_profile = aws_iam_instance_profile.minecraft_server.name

  root_block_device {
    volume_size = var.server_type == "bedrock" ? 10 : 20
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/scripts/user_data.sh", {
    server_type = var.server_type
    bucket_name = aws_s3_bucket.scripts.id
    install_key = "install.sh"
    script_keys = jsonencode({
      "test_server.sh"  = "test_server.sh"
      "validate_all.sh" = "validate_all.sh"
      "test_backup.sh"  = "test_backup.sh"
    })
  })
  user_data_replace_on_change = true

  tags = {
    Name = "minecraft-${var.environment}-${var.server_type}-server"
  }
}

# Attach the EBS volume to the instance
resource "aws_volume_attachment" "minecraft_data" {
  device_name  = "/dev/xvdf"
  volume_id    = aws_ebs_volume.minecraft_data.id
  instance_id  = aws_instance.minecraft.id

  // Stop instance before detaching, important for data consistency
  force_detach = false
}

