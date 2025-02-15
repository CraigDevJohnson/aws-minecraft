terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
  # TODO: Change to S3 backend once tested locally
  # backend "s3" {
  #   bucket = "minecraft-terraform-state"
  #   key    = "terraform.tfstate"
  #   region = "us-west-2"
  # }
}