module "constants" {
  source = "./modules/constants"
}

# Configure the AWS Provider
provider "aws" {
  region = "us-west-2"
  default_tags {
    tags = {
      Project   = module.constants.project_name
      ManagedBy = module.constants.managed_by
      Owner     = module.constants.owner
      Version   = module.constants.formatted_version
    }
  }
}