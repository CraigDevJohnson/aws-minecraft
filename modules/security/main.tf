locals {
  # Bedrock needs both UDP and TCP ports
  bedrock_ports = var.server_type == "bedrock" ? [
    {
      port     = 19132
      protocol = "udp"
    },
    {
      port     = 19133
      protocol = "udp"
    },
    {
      port     = 19132
      protocol = "tcp"
    }
    ] : [
    {
      port     = 25565
      protocol = "tcp"
    }
  ]
}

resource "aws_security_group" "minecraft" {
  name_prefix = "minecraft-${var.environment}-${var.server_type}-"
  description = "Security group for Minecraft ${var.server_type} server"
  vpc_id      = var.vpc_id

  # Dynamic block for Minecraft server ports
  dynamic "ingress" {
    for_each = local.bedrock_ports
    content {
      from_port   = ingress.value.port
      to_port     = ingress.value.port
      protocol    = ingress.value.protocol
      cidr_blocks = ["0.0.0.0/0"]
      description = "Minecraft ${var.server_type} server port (${ingress.value.protocol})"
    }
  }

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access"
  }

  # Outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "minecraft-${var.environment}-${var.server_type}-sg"
  }
}