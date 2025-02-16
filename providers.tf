# Configure the AWS Provider
provider "aws" {
  region = "us-west-2"
  default_tags {
    tags = {
      Environment = terraform.workspace
      Project     = "minecraft"
      ManagedBy   = "terraform"
    }
  }
}