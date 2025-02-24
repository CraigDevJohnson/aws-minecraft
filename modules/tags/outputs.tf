output "tags" {
  description = "Resource tags (excluding provider default tags)"
  value       = local.merged_tags
}