output "version" {
  description = "Current infrastructure version information"
  value       = local.version
}

output "formatted_version" {
  description = "Formatted version string"
  value       = local.formatted_version
}

output "project_name" {
  description = "Project name"
  value       = local.project_name
}

output "owner" {
  description = "Project owner"
  value       = local.owner
}

output "managed_by" {
  description = "Infrastructure management tool"
  value       = local.managed_by
}

output "cors_origin" {
  description = "CORS origin for S3 bucket"
  value       = local.cors_origin
}