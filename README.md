# AWS Minecraft Server

Deploy and maintain a Minecraft server in AWS using OpenTofu. Supports both Bedrock and Java editions with optimized configurations.

## Features

- Multi-environment support (dev/prod)
- Support for both Minecraft Bedrock and Java editions
- Cost-optimized instance types and configurations
- Automatic server installation and configuration
- Security-first approach with proper networking and access controls
- Infrastructure as Code using OpenTofu
- Server Management API via Lambda and API Gateway
- Secure admin controls for server operations
- Cost-optimized API with pay-per-use model
- CORS support for web integration

## Prerequisites

- AWS CLI configured with appropriate credentials
- OpenTofu >= 1.6.0
- SSH key pair for server access
- Admin token for server management

## Quick Start

1. Clone the repository
2. Create the workspaces:
   tofu workspace create prod && tofu workspace create dev

3. Initialize OpenTofu:
   ```bash
   tofu init
   ```

4. Deploy Bedrock server (default):
   ```bash
   tofu apply
   ```

   Or deploy Java server:
   ```bash
   tofu apply -var="server_type=java" -var="instance_type=t3.large"
   ```

### API Setup
1. Deploy the infrastructure:
   ```bash
   tofu workspace select dev
   tofu apply
   ```

2. Note the API endpoint URL from the outputs:
   - lambda_api_url: The API Gateway endpoint
   - server_test_curl: Example curl command for testing

3. Test the API:
   ```bash
   # Check server status
   curl -X POST {lambda_api_url} -H "Content-Type: application/json" -d '{"action":"status"}'
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

### API Layer
- Lambda function for server management
- API Gateway with CORS support
- IAM roles with least privilege access
- Environment-specific configurations
- CloudWatch logging and monitoring

### Security
- Isolated VPC environment
- Restricted security group access
- SSH key authentication
- Admin token authentication for stop operations
- CORS restrictions for API endpoints
- CloudWatch logs for API access

## Configuration

The server can be customized through terraform.tfvars or command line variables:

| Variable | Description | Default | Options |
|----------|-------------|---------|----------|
| server_type | Type of Minecraft server | "bedrock" | "bedrock", "java" |
| instance_type | EC2 instance size | "t3.small" | Any valid EC2 type |
| environment | Deployment environment | "dev" | "dev", "prod" |
| admin_stop_token | Admin token for server control | Required | Any secure string |

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

## API Documentation
See [API Documentation](docs/api.md) for detailed information about the server management API endpoints and usage examples.

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