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

resource "aws_instance" "minecraft" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  subnet_id     = var.subnet_id

  vpc_security_group_ids = [var.security_group_id]
  key_name              = var.key_name

  root_block_device {
    volume_size = var.server_type == "bedrock" ? 10 : 20
    volume_type = "gp3"
  }

  user_data = filebase64(local.script_path)
  user_data_replace_on_change = true

  tags = {
    Name = "minecraft-${var.environment}-${var.server_type}-server"
  } 
}

