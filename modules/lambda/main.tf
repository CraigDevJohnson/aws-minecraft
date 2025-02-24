# OpenTofu configuration for the Minecraft server manager Lambda function and API Gateway
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

module "function_tags" {
  source        = "../tags"
  resource_name = "lambda-manager"
}

module "role_tags" {
  source        = "../tags"
  resource_name = "lambda-role"
}

module "api_tags" {
  source        = "../tags"
  resource_name = "api-gateway"
}

# ZIP the Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/functions/minecraft_server_manager.py"
  output_path = "${path.module}/functions/minecraft_server_manager.zip"
}

# Lambda function for server management
resource "aws_lambda_function" "minecraft_manager" {
  filename      = data.archive_file.lambda_zip.output_path
  function_name = "${var.lambda_function_name}-${terraform.workspace}"
  role          = aws_iam_role.lambda_role.arn
  handler       = "minecraft_server_manager.lambda_handler"
  runtime       = "python3.9"
  timeout       = 30

  environment {
    variables = {
      INSTANCE_ID = var.minecraft_instance_id
      ENVIRONMENT = terraform.workspace
    }
  }

  tags = (module.function_tags.tags)
}

# IAM role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "minecraft-manager-lambda-role-${terraform.workspace}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = (module.role_tags.tags)
}

# IAM policy for managing EC2 instance
resource "aws_iam_role_policy" "lambda_ec2_policy" {
  name = "minecraft-manager-ec2-policy-${terraform.workspace}"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:StartInstances",
          "ec2:StopInstances"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ec2:ResourceTag/Project" : "minecraft"
          }
        }
      }
    ]
  })
}

# Add CloudWatch Logs permissions
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Add Secrets Manager permissions
resource "aws_iam_role_policy" "lambda_secrets" {
  name = "minecraft-manager-secrets-policy-${terraform.workspace}"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          "arn:aws:secretsmanager:*:*:secret:minecraft-${terraform.workspace}-*"
        ]
      }
    ]
  })
}

# Add SSM Parameter Store permissions
resource "aws_iam_role_policy" "lambda_ssm" {
  name = "minecraft-manager-ssm-policy-${terraform.workspace}"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter"
        ]
        Resource = [
          "arn:aws:ssm:*:*:parameter/minecraft/${terraform.workspace}/*"
        ]
      }
    ]
  })
}

# HTTP API Gateway v2
resource "aws_apigatewayv2_api" "minecraft_api" {
  name          = "minecraft-server-api-${terraform.workspace}"
  protocol_type = "HTTP"
  cors_configuration {
    allow_origins = [var.cors_origin]
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["content-type"]
    max_age       = 300
  }

  tags = (module.api_tags.tags)
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id                 = aws_apigatewayv2_api.minecraft_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.minecraft_manager.invoke_arn
  payload_format_version = "2.0"
  integration_method     = "POST"
}

resource "aws_apigatewayv2_route" "minecraft_route" {
  api_id    = aws_apigatewayv2_api.minecraft_api.id
  route_key = "POST /server"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_apigatewayv2_stage" "minecraft" {
  api_id      = aws_apigatewayv2_api.minecraft_api.id
  name        = terraform.workspace
  auto_deploy = true
}

# Lambda permission for API Gateway v2
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.minecraft_manager.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.minecraft_api.execution_arn}/*/*/server"
}