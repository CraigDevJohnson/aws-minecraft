locals {
  # Infrastructure versioning
  version = {
    major = 0
    minor = 0
    patch = 4
    stage = "alpha" # Options: alpha, beta, rc, stable
  }

  # Formatted version string
  formatted_version = "${local.version.major}.${local.version.minor}.${local.version.patch}-${local.version.stage}"

  # Common constants
  project_name = "minecraft"
  owner        = "Craig Johnson"
  managed_by   = "OpenTofu"
  cors_origin  = "*"
}

