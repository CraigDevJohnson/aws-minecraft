terraform {
  backend "s3" {
    bucket               = "minecraft-tofu-state"
    key                  = "tofu/minecraft.tfstate"
    region               = "us-west-2"
    dynamodb_table       = "minecraft-tofu-lock-table"
    encrypt              = true
    workspace_key_prefix = "env"
  }
}