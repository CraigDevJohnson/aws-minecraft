# Output configuration file for the Lambda module
# This file defines the output values that will be exposed from the Lambda module.
output "api_url" {
  description = "API Gateway URL"
  value       = aws_apigatewayv2_stage.minecraft.invoke_url
}

output "function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.minecraft_manager.function_name
}

output "api_gateway_arn" {
  description = "ARN of the HTTP API Gateway"
  value       = aws_apigatewayv2_api.minecraft_api.execution_arn
}

output "api_endpoint" {
  value = aws_apigatewayv2_api.minecraft_api.api_endpoint
}

output "jwt_issuer" {
  value = "https://${var.domain_name}"
}