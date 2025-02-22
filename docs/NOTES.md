aws-minecraft
├── environments
│   ├── dev
│   │   ├── main.tf # later
│   │   ├── variables.tf # later
│   │   ├── outputs.tf # later
│   │   └── terraform.tfvars # later
│   └── prod
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── terraform.tfvars
├── modules
│   ├── compute
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── network
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── security
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── .gitignore
├── README.md
├── versions.tf
└── backend.tf

## Project Overview

This project aims to deploy a Minecraft server on AWS using Terraform. The infrastructure is designed to be cost-effective, performant, secure, and operationally excellent. The project is structured to support both Bedrock and Java editions of Minecraft.

## Project Structure

- **environments/**: Contains environment-specific configurations for `dev` and `prod`.
- **modules/**: Contains reusable Terraform modules for `compute`, `network`, and `security`.
- **backend.tf**: Configures the Terraform backend.
- **providers.tf**: Configures the Terraform providers.
- **versions.tf**: Specifies the required Terraform version and provider versions.

## Key Components

- **Network Layer**: Sets up VPC, subnets, and security groups.
- **Compute Layer**: Configures EC2 instances for the Minecraft server.
- **Security Layer**: Manages security groups and IAM roles.

## Deployment Instructions

1. Initialize Terraform: `terraform init`
2. Plan the deployment: `terraform plan`
3. Apply the deployment: `terraform apply`

## Notes

- Ensure that the `terraform.tfvars` file is properly configured with the necessary variables.
- The project uses local backend for initial testing. Update `backend.tf` to use S3 backend for production.
- The `compute` module includes installation scripts for both Bedrock and Java editions of Minecraft.
- Security groups are configured to allow Minecraft server ports and SSH access.
- EC2 instances are tagged for cost management and resource identification.

## Future Enhancements

- Implement auto-scaling for the EC2 instances.
- Set up S3 bucket for backups and implement a backup rotation policy.
- Configure CloudWatch alarms and logging for monitoring and maintenance.
- Implement IAM roles and policies for enhanced security.
- Set up CI/CD pipeline using GitHub Actions for automated testing and deployment.

## Current Implementation Status

### Completed Components
- Basic project structure with modular design
- Environment separation (dev/prod)
- Network configuration with VPC setup
- Basic security group implementation
- EC2 instance configuration for Minecraft server
- EBS volume setup for world data
- Basic server installation scripts
- Resource tagging strategy
- AWS Backup configuration with daily and weekly backups
- Enhanced user_data script with proper volume mounting
- Systemd service configuration with logging
- Lambda function implementation for server start/stop control
- API Gateway setup with CORS support
- Basic IAM roles and policies for Lambda
- SSM Parameter Store integration for token management
- Enhanced token validation and error handling
- Comprehensive CloudWatch logging for Lambda
- Real-time token validation logging and debugging

### In Progress
- Production security enhancements
  - CORS origin restrictions
  - Rate limiting implementation
  - Request validation
  - API key requirements
- Server state management optimization
- API versioning and deprecation strategy
- Additional API endpoints development
- Frontend integration with Vue.js

### Next Steps
1. Implement secret rotation mechanism
2. Set up production-grade CORS restrictions
3. Add rate limiting to API endpoints
4. Implement request validation
5. Configure API key requirements
6. Add server metrics endpoint
7. Implement backup management endpoint
8. Add server logs endpoint
9. Create server.properties management endpoint
10. Develop allowlist management endpoint

### Recent Changes
- Successfully tested Lambda API authentication
- Implemented comprehensive token validation logging
- Added detailed error handling for API requests
- Enhanced CloudWatch logging configuration
- Fixed API Gateway stage reference issue
- Verified token-based authorization flow
- Successfully tested server start/stop operations
- Added thorough validation logging for debugging
- Implemented SSM Parameter Store for token storage
- Enhanced error messages for better troubleshooting

## Current Testing Status

### Server Testing
- Enhanced validation scripts implemented
- Auto-start and restart functionality tested
- World data persistence verification added
- Network port testing improved for both server types
- Multi-stage validation with retries implemented

### Backup Configuration
- AWS Backup vault and plan verified
- IAM roles and permissions validated
- Backup selection tested successfully
- Restoration process validated
- Added versioning tests for local backups

### Lambda Function Testing Completed
- ✓ Lambda function deployment verification
- ✓ API Gateway endpoint accessibility
- ✓ Basic CORS configuration testing
- ✓ Admin token authentication validation
- ✓ Error handling scenarios
- ✓ Server state management operations
- ✓ CloudWatch logs verification

### Next Testing Phase
1. Load testing under stress conditions
2. Production CORS configuration validation
3. Rate limiting effectiveness
4. Request validation scenarios
5. API key authentication testing
6. Secret rotation procedures
7. Integration testing with frontend components