variable "version_pattern" {
  type        = string
  default     = "^\\d+\\.\\d+\\.\\d+$"
  description = "Regex pattern for semantic versioning"
}

locals {
  files = {
    install_java = {
      name     = "install_java"
      filename = "install_java.sh"
      path     = "${path.module}/scripts/install_java.sh"
      version  = "1.0.0"
      type     = "text/x-shellscript"
    }
    install_bedrock = {
      name     = "install_bedrock"
      filename = "install_bedrock.sh"
      path     = "${path.module}/scripts/install_bedrock.sh"
      version  = "1.0.0"
      type     = "text/x-shellscript"
    }
    run_server = {
      name     = "run_server"
      filename = "run_server.sh"
      path     = "${path.module}/scripts/run_server.sh"
      version  = "1.0.0"
      type     = "text/x-shellscript"
    }
    world_backup = {
      name     = "world_backup"
      filename = "world_backup.sh"
      path     = "${path.module}/../storage/scripts/world_backup.sh"
      version  = "1.0.0"
      type     = "text/x-shellscript"
    }
    validate_all = {
      name     = "validate_all"
      filename = "validate_all.sh"
      path     = "${path.module}/scripts/validate_all.sh"
      version  = "1.0.0"
      type     = "text/x-shellscript"
    }
    test_server = {
      name     = "test_server"
      filename = "test_server.sh"
      path     = "${path.module}/scripts/test_server.sh"
      version  = "1.0.0"
      type     = "text/x-shellscript"
    }
    test_world_backup = {
      name     = "test_world_backup"
      filename = "test_world_backup.sh"
      path     = "${path.module}/../storage/scripts/test_world_backup.sh"
      version  = "1.0.0"
      type     = "text/x-shellscript"
    }
    java_properties = {
      name    = "java_properties"
      filename = "java.properties"
      path     = "${path.module}/configs/java.properties"
      version  = "1.0.0"
      type     = "text/plain"
    }
    bedrock_properties = {
      name     = "bedrock_properties"
      filename = "bedrock.properties"
      path     = "${path.module}/configs/bedrock.properties"
      version  = "1.0.0"
      type     = "text/plain"
    }
  }

  version_validation = {
    for file_key, file_metadata in local.files :
    file_key => regex(var.version_pattern, file_metadata.version) != null
  }
}