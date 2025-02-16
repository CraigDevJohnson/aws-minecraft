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

### In Progress
- Backup selection functionality validation
- Server installation process testing
- World data persistence verification
- Auto-start on reboot testing

### Next Steps
1. Test backup selection functionality
2. Validate server installation process
3. Test world data persistence
4. Verify auto-start on reboot
5. Implement backup restoration testing

### Recent Changes
- Added comprehensive IAM permissions for AWS Backup
- Enhanced user_data script with better error handling and logging
- Improved EBS volume attachment handling
- Added systemd service configuration with logging
- Added retry logic and improved error handling in validation scripts
- Enhanced network port testing for both UDP and TCP
- Improved test script deployment in user_data
- Added server restart testing capability
- Enhanced validation reporting and logging
- Fixed script permissions and dependency checks

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

## Next Steps
1. Test load handling and performance under stress
2. Implement server plugin management
3. Set up automatic updates
4. Configure backup encryption with KMS
5. Set up backup notifications

## Continuation Prompt
To continue where we left off, use this prompt:

"I'd like to continue working on the Minecraft server deployment. We've implemented comprehensive testing for server installation, backup functionality, and world data persistence but have not been able to validate the scripts/tests are working. Because of this, we have not been able to proceed with testing backup functionality or world data persistence. We need to get the test_server.sh to work first. 

Once we've compelted the above, we need to:
1. Implement load testing scenarios
2. Set up automatic server updates
3. Configure backup encryption
4. Add server plugin management
5. Set up monitoring and alerting

Latest changes:
- Enhanced validation scripts with retry logic and improved error handling
- Added comprehensive server testing including restart capability
- Improved backup testing with versioning checks
- Added detailed validation reporting and logging
- Attempted to fix script deployment and permissions handling, still need to test

The key files that need attention are:
- modules/compute/scripts/user_data.sh (automatic updates)
- modules/storage/main.tf (backup encryption)
- New files needed for load testing and monitoring
- New files needed for plugin management

Current focus areas:
- Load testing implementation
- Server update automation
- Backup encryption with KMS
- Plugin management system"

As far as the current error with the scripts. I can see they are not handling variables right when being imported to the user_data.sh. See the install_bedrock.sh vs the imported script I pulled from the server:
echo "[Sun Feb 16 07:42:41 UTC 2025] Fetching download URL from Minecraft website..."
while [  -lt  ]; do
    # Try to download from the official preview page
    DOWNLOAD_URL=https://www.minecraft.net/bedrockdedicatedserver/bin-linux/bedrock-server-1.21.60.10.zip
    if [ ! -z "" ]; then
        echo "[Sun Feb 16 07:42:42 UTC 2025] Found download URL: "
        if wget -U "Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1; BEDROCK-UPDATER)"  -O bedrock-server.zip; then
            echo "[Sun Feb 16 07:42:42 UTC 2025] Download successful"
            break
        fi
    fi

    # Fallback to direct download from known URL pattern
    FALLBACK_URL="https://www.minecraft.net/bedrockdedicatedserver/bin-linux/bedrock-server-1.21.60.10.zip"
    echo "[Sun Feb 16 07:42:42 UTC 2025] Trying fallback URL: "
    if wget -U "Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1; BEDROCK-UPDATER)"  -O bedrock-server.zip; then
        echo "[Sun Feb 16 07:42:42 UTC 2025] Fallback download successful"
        break
    fi