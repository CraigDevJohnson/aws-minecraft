data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical's AWS account ID

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
  availability_zone = var.availability_zone  # Ensure instance is in same AZ as the EBS volume

  vpc_security_group_ids = [var.security_group_id]
  key_name              = var.key_name

  root_block_device {
    volume_size = var.server_type == "bedrock" ? 10 : 20
    volume_type = "gp3"
  }

  user_data = base64encode(templatefile("${path.module}/scripts/user_data.sh", {
    install_script = file(local.script_path),
    server_type    = var.server_type
  }))
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

  # Stop instance before detaching, important for data consistency
  force_detach = false
}

