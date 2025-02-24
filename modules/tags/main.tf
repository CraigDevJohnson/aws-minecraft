module "constants" {
  source = "../constants"
}

locals {
  # Base tags that should be applied to all resources
  base_tags = {
    Version     = module.constants.formatted_version
    Environment = terraform.workspace
  }

  # Standard name tag format
  name_tag = var.resource_name != null ? {
    Name = "minecraft-${terraform.workspace}-${var.resource_name}"
  } : {}

  # Resource-specific tags merged in order of precedence:
  # 1. Base tags
  # 2. Name tag (if resource_name provided)
  # 3. Additional resource-specific tags
  merged_tags = merge(
    local.base_tags,
    local.name_tag,
    var.additional_tags
  )
}
