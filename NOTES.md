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

### In Progress
- Auto-scaling configuration
- Backup and recovery system
- Monitoring and alerting setup
- Cost optimization features

### Technical Decisions

#### Infrastructure Choices
- Using EC2 instances instead of ECS/EKS for cost optimization
- Separate VPC for each environment to maintain isolation
- EBS volumes for world data with snapshot backup capability
- Security groups configured for minimal required access
- Java 21 runtime for modern Minecraft Java server support
- Optimized memory settings for both server types:
  - Bedrock: Uses t3.small (cost-effective for lighter requirements)
  - Java: Uses t3.large when specified (better performance for JVM)

#### Cost Optimization Strategy
- Resource tagging implemented for cost allocation
- Planning for spot instances in non-critical environments
- Scheduled scaling for off-peak hours
- EBS volume optimization for game data

#### Security Implementation
- Network isolation through VPC design
- Security groups limiting access to necessary ports:
  - TCP/25565 for Java Edition
  - UDP/19132 for Bedrock Edition
  - TCP/22 for SSH access (restricted to VPN/bastion)
- IAM roles following principle of least privilege

## Environment-Specific Configurations

### Development Environment
- Using t3.small for default Bedrock servers
- Optional t3.large for Java servers (specified via -var)
- Allows direct SSH access for testing
- More permissive security group rules for testing
- Local backend for state management

### Production Environment
- Using optimized instance types (t3.large/r5.large)
- Restricted access through bastion host
- Strict security group rules
- S3 backend with state locking

## Resource Specifications

### Compute Resources
- EC2 instance types:
  - Dev: t3.medium (2 vCPU, 4GB RAM)
  - Prod: t3.large (2 vCPU, 8GB RAM)
- EBS volumes:
  - Root: 20GB gp3
  - Game data: 50GB gp3

### Network Resources
- VPC with /16 CIDR
- Public and private subnets in each AZ
- NAT Gateway for private subnet access
- Security groups for Minecraft and SSH access

## Operational Notes

- Always use terraform plan before applying changes
- Keep terraform.tfvars updated with environment-specific values
- Backup world data before major infrastructure changes
- Monitor CloudWatch metrics for performance issues
- Use tagging for resource tracking and cost allocation

## Contact

For any questions or issues, please contact the project maintainer.

