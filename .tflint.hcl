plugin "terraform" {
    enabled = true
    version = "0.10.0"
    source  = "github.com/terraform-linters/tflint-ruleset-terraform"
}

plugin "aws" {
    enabled = true
    version = "0.37.0"
    source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

rule "terraform_required_providers" {
  enabled = false
}

rule "terraform_required_version" {
  enabled = false
}