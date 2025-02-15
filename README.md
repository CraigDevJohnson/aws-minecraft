# AWS Minecraft Server

Deploy and maintain a Minecraft server in AWS using Terraform. Supports both Bedrock and Java editions with optimized configurations.

## Features

- Multi-environment support (dev/prod)
- Support for both Minecraft Bedrock and Java editions
- Cost-optimized instance types and configurations
- Automatic server installation and configuration
- Security-first approach with proper networking and access controls
- Infrastructure as Code using Terraform

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.5.0
- SSH key pair for server access

## Quick Start

1. Clone the repository
2. Navigate to the environment directory:
   ```bash
   cd environments/dev
   ```

3. Initialize Terraform:
   ```bash
   terraform init
   ```

4. Deploy Bedrock server (default):
   ```bash
   terraform apply
   ```

   Or deploy Java server:
   ```bash
   terraform apply -var="server_type=java" -var="instance_type=t3.large"
   ```

## Architecture

### Network
- VPC with public subnet
- Security groups for Minecraft ports
- Internet Gateway for public access

### Compute
- EC2 instances with optimized configurations:
  - Bedrock: t3.small (default)
  - Java: t3.large (recommended)
- EBS volumes for server data
- Automated server installation and configuration

### Security
- Isolated VPC environment
- Restricted security group access
- SSH key authentication

## Configuration

The server can be customized through terraform.tfvars or command line variables:

| Variable | Description | Default | Options |
|----------|-------------|---------|----------|
| server_type | Type of Minecraft server | "bedrock" | "bedrock", "java" |
| instance_type | EC2 instance size | "t3.small" | Any valid EC2 type |
| environment | Deployment environment | "dev" | "dev", "prod" |

## Maintenance

### Backups
- World data is stored on EBS volumes
- Regular snapshots recommended (TODO)
- Backup rotation policy (TODO)

### Monitoring
- CloudWatch metrics (TODO)
- Server logs in /var/log/minecraft/
- Instance health checks (TODO)

## Security

- All sensitive files are gitignored
- SSH keys must be managed separately
- Security groups limit access to required ports:
  - Bedrock: UDP 19132/19133
  - Java: TCP 25565
  - SSH: TCP 22

## Cost Management

- Uses cost-effective instance types
- Automatic shutdown when inactive (TODO)
- Resource tagging for cost allocation

## Contributing

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a new Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For issues and feature requests, please create an issue in the repository.