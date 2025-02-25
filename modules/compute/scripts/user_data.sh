#!/bin/bash
set -e

CONFIG_FILE="$1"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file not found"
    exit 1
fi

# Load configuration
eval "$(jq -r 'to_entries | .[] | "export " + .key + "=\"" + (.value|tostring) + "\""' "$CONFIG_FILE")"

# Constants for OpenTofu template variables
IMDS_ENDPOINT="${imds_endpoint}"
IMDS_TOKEN_TTL="${imds_token_ttl}"
BUCKET_NAME="${bucket_name}"
INSTALL_JAVA_SCRIPT="${install_java_script}"
INSTALL_BEDROCK_SCRIPT="${install_bedrock_script}"
RUN_SERVER_SCRIPT="${run_server_script}"
WORLD_BACKUP_SCRIPT="${world_backup_script}"
VALIDATE_SCRIPT="${validate_script}"
TEST_SERVER_SCRIPT="${test_server_script}"
TEST_WORLD_BACKUP_SCRIPT="${test_world_backup_script}"
BEDROCK_PROPERTIES="${bedrock_properties}"
JAVA_PROPERTIES="${java_properties}"
SERVER_TYPE="${server_type}"
CLOUD_INIT_OUTPUT_LOG="/var/log/cloud-init-output.log"
DNF_PACKAGES=""
APT_PACKAGES="jq curl"
SNAP_AWSCLI="aws-cli"


# Enable debug output
DEBUG=true
# exec 1> >(tee -a /var/log/cloud-init-output.log)
# exec 2>&1
set -x

# logging functions
log_message() {
    local level="$1"
    local message="$2"
    echo "[$(date)] [$level] $message" | tee -a "$CLOUD_INIT_OUTPUT_LOG"
}

debug_message() {
    if [ "$DEBUG" = true ]; then
        log_message "DEBUG" "$1"
    fi
}

# Script start
log_message "INFO" "Starting Minecraft server setup..."

# Determine distro
LINUX_DISTRO=$(grep -oP '^NAME=\K.+' /etc/os-release | tr -d '"')
if [ "$LINUX_DISTRO" == "Amazon Linux" ]; then
    log_message "INFO" "Detected Amazon Linux"
elif [ "$LINUX_DISTRO" == "Ubuntu" ]; then
    log_message "INFO" "Detected Ubuntu"
else
    log_message "ERROR" "Unsupported Linux distribution: $LINUX_DISTRO"
    exit 1
fi

# Resolve packages required for the detected Linux distribution
if [ "$LINUX_DISTRO" == "Amazon Linux" ]; then
    log_message "INFO" "Amazon Linux detected, installing required packages..."
    # Update package lists
    dnf update -y
    dnf upgrade -y

    if ! command -v java &> /dev/null; then
        log_message "INFO" "Java not installed, adding to package list..."
        DNF_PACKAGES+=" java-21-amazon-corretto-headless"
    fi
    # Add jq to package list if not present
    if ! command -v jq &> /dev/null; then
        log_message "INFO" "jq not installed, adding to package list..."
        DNF_PACKAGES+=" jq"
    fi
    # Add curl to package list if not present
    if ! command -v curl &> /dev/null; then
        log_message "INFO" "curl not installed, adding to package list..."
        DNF_PACKAGES+=" curl"
    fi
    # Add wget to package list if not present
    if ! command -v wget &> /dev/null; then
        log_message "INFO" "wget not installed, adding to package list..."
        DNF_PACKAGES+=" wget"
    fi
    # Add AWS CLI to package list if not present (required for getting tags)
    if ! command -v aws &> /dev/null; then
        log_message "INFO" "aws-cli not installed, adding to package list..."
        DNF_PACKAGES+=" aws-cli"
    fi
    if ! command -v crond &> /dev/null; then
        log_message "INFO" "cronie not installed, adding to package list..."
        DNF_PACKAGES+=" cronie"
    fi

    # Install required packages and verify installation
    if [[ "$DNF_PACKAGES" =~ [^[:space:]] ]]; then
        log_message "INFO" "Installing required dnf packages ($DNF_PACKAGES)..."
        dnf install -y $DNF_PACKAGES
        systemctl enable crond && systemctl start crond >/dev/null 2>&1
    else
        debug_message "No DNF packages to install"
    fi
    JAVA_VERSION=$(java -version 2>&1)
    JQ_VERSION=$(jq --version)
    CURL_VERSION=$(curl --version | head -n 1)
    WGET_VERSION=$(wget --version | head -n 1)
    AWS_CLI_VERSION=$(aws --version 2>&1)
    CRON_VERSION=$(crond -V 2>&1)
    if [ -n "$JAVA_VERSION" ] && [ -n "$JQ_VERSION" ] && [ -n "$CURL_VERSION" ] && [ -n "$WGET_VERSION" ] && [ -n "$AWS_CLI_VERSION" ] && [ -n "$CRON_VERSION" ]; then
        log_message "INFO" "Verified all required packages are present"
        debug_message "Java version: $JAVA_VERSION"
        debug_message "JQ version: $JQ_VERSION"
        debug_message "Curl version: $CURL_VERSION"
        debug_message "Wget version: $WGET_VERSION"
        debug_message "AWS CLI version: $AWS_CLI_VERSION"
        debug_message "Cron version: $CRON_VERSION"
    else
        log_message "ERROR" "Failed to verify required packages"
        exit 1
    fi
fi

# Resolve Ubuntu required packages
if [ "$LINUX_DISTRO" == "Ubuntu" ]; then
    log_message "INFO" "Ubuntu detected, installing required packages..."
    # Install required packages and verify installation
    apt-get update
    apt-get upgrade -y

    # Add jq to package list if not present
    if ! command -v jq &> /dev/null; then
        log_message "INFO" "jq not installed, adding to package list..."
        APT_PACKAGES+=" jq"
    fi
    # Add curl to package list if not present
    if ! command -v curl &> /dev/null; then
        log_message "INFO" "curl not installed, adding to package list..."
        APT_PACKAGES+=" curl"
    fi
    if ! command -v cron &> /dev/null; then
        log_message "INFO" "cron not installed, adding to package list..."
        APT_PACKAGES+=" cron"
    fi

    log_message "INFO" "Installing required apt packages ($APT_PACKAGES)..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y $APT_PACKAGES
    systemctl enable crond && systemctl start crond >/dev/null 2>&1

    CURL_VERSION=$(curl --version | head -n 1)
    JQ_VERSION=$(jq --version)
    CRON_VERSION=$(cron -V 2>&1)
    if [ -n "$CURL_VERSION" ] && [ -n "$JQ_VERSION" ] && [ -n "$CRON_VERSION" ]; then
        log_message "INFO" "Installed $APT_PACKAGES packages successfully"
        debug_message "JQ version: $JQ_VERSION"
        debug_message "Curl version: $CURL_VERSION"
        debug_message "Cron version: $CRON_VERSION"
    else
        log_message "ERROR" "Failed to install required packages"
        exit 1
    fi

    # Install AWS CLI v2
    log_message "INFO" "Installing AWS CLI via snap..."
    snap install $SNAP_AWSCLI --classic >/dev/null 2>&1
    AWSCLI_VERSION=$(aws --version)
    if [ -n "$AWSCLI_VERSION" ]; then
        log_message "INFO" "AWS CLI installed successfully"
        debug_message "AWS CLI version: $AWSCLI_VERSION"
    else
        log_message "ERROR" "Failed to install AWS CLI"
        exit 1
    fi
fi
log_message "INFO" "All required packages installed successfully"

# Function to find the EBS device
find_ebs_device() {
    if [ -e /dev/xvdf ]; then
        FOUND_DEVICE="/dev/xvdf"
    fi
    
    if [ -e /dev/nvme1n1 ]; then
        FOUND_DEVICE="/dev/nvme1n1"
    fi
    if [ -n "$FOUND_DEVICE" ]; then
        log_message "INFO" "Found EBS device"
        debug_message "EBS device: $FOUND_DEVICE"
        return 0
    fi
    log_message "ERROR" "EBS device not found"
    return 1
}

# Wait for EBS volume
log_message "INFO" "Waiting for EBS volume to be attached..."
find_ebs_device
for i in {1..30}; do
    EBS_DEVICE=$FOUND_DEVICE
    if [ -n "$EBS_DEVICE" ]; then
        log_message "INFO" "Found EBS volume"
        debug_message "EBS device: $EBS_DEVICE"
        break
    fi
    log_message "INFO" "Still waiting for EBS volume... (attempt $i/30)"
    sleep 5
    find_ebs_device
done

if [ -z "$EBS_DEVICE" ]; then
    log_message "ERROR" "Failed to find EBS volume after timeout"
    exit 1
fi

# Create mount point
mkdir -p /mnt/minecraft_data

# Format if needed (only if not already formatted)
if ! blkid "$EBS_DEVICE" >/dev/null 2>&1; then
    log_message "INFO" "Formatting EBS volume at $EBS_DEVICE..."
    mkfs.ext4 "$EBS_DEVICE" >/dev/null 2>&1
    log_message "INFO" "EBS volume formatted successfully"
fi

# Add fstab entry (remove old entry first if exists)
sed -i "\|^$EBS_DEVICE|d" /etc/fstab
echo "$EBS_DEVICE /mnt/minecraft_data ext4 defaults,nofail 0 2" >> /etc/fstab

# Mount volume with retries
log_message "INFO" "Mounting EBS volume..."
mount_attempts=0
max_mount_attempts=3
while [ "$mount_attempts" -lt "$max_mount_attempts" ]; do
    if mount /mnt/minecraft_data; then
        log_message "INFO" "Successfully mounted $EBS_DEVICE to /mnt/minecraft_data"
        break
    else
        mount_attempts=$((mount_attempts + 1))
        if [ "$mount_attempts" -eq "$max_mount_attempts" ]; then
            log_message "ERROR" "Failed to mount volume after $max_mount_attempts attempts"
            exit 1
        fi
        log_message "WARNING" "Mount attempt $mount_attempts failed, waiting 10s before retry..."
        sleep 10
    fi
done

# Verify mount and set permissions
if mountpoint -q /mnt/minecraft_data; then
    log_message "INFO" "Setting up permissions for mounted volume..."
    if [ "$LINUX_DISTRO" == "Amazon Linux" ]; then
        chown -R ec2-user:ec2-user /mnt/minecraft_data
    fi
    if [ "$LINUX_DISTRO" == "Ubuntu" ]; then
        chown -R ubuntu:ubuntu /mnt/minecraft_data
    fi
    chmod 755 /mnt/minecraft_data    
else
    log_message "ERROR" "Mount verification failed"
    exit 1
fi

# Create directories with proper permissions
log_message "INFO" "Creating required directories..."
# Create /opt/minecraft directories
mkdir -p /opt/minecraft/test
mkdir -p /opt/minecraft/worlds
mkdir -p /opt/minecraft/backups

# Create /mnt/minecraft_data directories
mkdir -p /mnt/minecraft_data/worlds
mkdir -p /mnt/minecraft_data/backups

# Create log directories
mkdir -p /var/log/minecraft/test

# Set permissions
log_message "INFO" "Setting directory permissions..."
if [ "$LINUX_DISTRO" == "Amazon Linux" ]; then
    chown -R ec2-user:ec2-user /opt/minecraft /mnt/minecraft_data /var/log/minecraft
fi
if [ $LINUX_DISTRO == "Ubuntu" ]; then
    chown -R ubuntu:ubuntu /opt/minecraft /mnt/minecraft_data /var/log/minecraft
fi
chmod 755 /opt/minecraft /mnt/minecraft_data /var/log/minecraft

# Create symbolic links
log_message "INFO" "Creating symbolic links..."
ln -sf /mnt/minecraft_data/worlds /opt/minecraft/worlds
ln -sf /mnt/minecraft_data/backups /opt/minecraft/backups

# Get IMDSv2 token for metadata access
TOKEN=$(curl -X PUT "http://$IMDS_ENDPOINT/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: $IMDS_TOKEN_TTL" --retry 3 --retry-delay 1 --silent --fail)
if [ -n "$TOKEN" ]; then
    log_message "INFO" "IMDSv2 token acquired successfully"
    debug_message "IMDSv2 token: $TOKEN"
else
    log_message "ERROR" "Failed to acquire IMDSv2 token"
    exit 1
fi

# Get region from instance metadata
REGION=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" "http://$IMDS_ENDPOINT/latest/meta-data/placement/region")
if [ -n "$REGION" ]; then
    log_message "INFO" "Instance region: $REGION"
    debug_message "Instance region: $REGION"
else
    log_message "ERROR" "Failed to get instance region"
    exit 1
fi

# Configure AWS CLI region
aws configure set region "$REGION"

# Download and setup files
log_message "INFO" "Downloading files from S3..."

# Create test directory
mkdir -p /opt/minecraft/test
if [ "$LINUX_DISTRO" == "Amazon Linux" ]; then
    chown -R ec2-user:ec2-user /opt/minecraft/test
fi
if [ "$LINUX_DISTRO" == "Ubuntu" ]; then
    chown -R ubuntu:ubuntu /opt/minecraft/test
fi
chmod 755 /opt/minecraft/test

# Download java install script
aws s3 cp "s3://$BUCKET_NAME/$INSTALL_JAVA_SCRIPT" /tmp/install_java.sh
chmod +x /tmp/install_java.sh

# Download bedrock install script
aws s3 cp "s3://$BUCKET_NAME/$INSTALL_BEDROCK_SCRIPT" /tmp/install_bedrock.sh
chmod +x /tmp/install_bedrock.sh

# Download server run script
aws s3 cp "s3://$BUCKET_NAME/$RUN_SERVER_SCRIPT" /opt/minecraft/run_server.sh
chmod +x /opt/minecraft/run_server.sh

# Download world backup script
aws s3 cp "s3://$BUCKET_NAME/$WORLD_BACKUP_SCRIPT" /opt/minecraft/world_backup.sh
chmod +x /opt/minecraft/world_backup.sh

# Download test scripts
debug_message "Downloading test server script..."
aws s3 cp "s3://$BUCKET_NAME/$TEST_SERVER_SCRIPT" /opt/minecraft/test/test_server.sh
chmod +x /opt/minecraft/test/test_server.sh

debug_message "Downloading validation script..."
aws s3 cp "s3://$BUCKET_NAME/$VALIDATE_SCRIPT" /opt/minecraft/test/validate_all.sh
chmod +x /opt/minecraft/test/validate_all.sh

debug_message "Downloading backup test script..."
aws s3 cp "s3://$BUCKET_NAME/$TEST_WORLD_BACKUP_SCRIPT" /opt/minecraft/test/test_world_backup.sh
chmod +x /opt/minecraft/test/test_world_backup.sh

# Download server properties
log_message "INFO" "Downloading server properties..."
aws s3 cp "s3://$BUCKET_NAME/$JAVA_PROPERTIES" /tmp/java.properties
aws s3 cp "s3://$BUCKET_NAME/$BEDROCK_PROPERTIES" /tmp/bedrock.properties


# Setup logging directory
mkdir -p /var/log/minecraft/test
if [ "$LINUX_DISTRO" == "Amazon Linux" ]; then
    chown -R ec2-user:ec2-user /var/log/minecraft
fi
if [ "$LINUX_DISTRO" == "Ubuntu" ]; then
    chown -R ubuntu:ubuntu /var/log/minecraft
fi 

# Run server installation
log_message "INFO" "Running server installation script..."
if [ "$SERVER_TYPE" = "java" ]; then
    /tmp/install_java.sh
elif [ "$SERVER_TYPE" = "bedrock" ]; then
    /tmp/install_bedrock.sh
else
    log_message "ERROR" "Invalid server type: $SERVER_TYPE"
    exit 1
fi
log_message "INFO" "Server installation completed successfully"

# Move world data if needed
log_message "INFO" "Checking for world data in persistent storage..."
if [ -d "/opt/minecraft/worlds" ] && [ ! -L "/opt/minecraft/worlds" ]; then
    log_message "INFO" "Moving world data to persistent storage"
    mv /opt/minecraft/worlds/* /mnt/minecraft_data/worlds/
    rm -rf /opt/minecraft/worlds
    ln -sf /mnt/minecraft_data/worlds /opt/minecraft/worlds
fi
log_message "INFO" "World data already in persistent storage"

# Setup backup cron
# Create cron.d directory if it doesn't exist
if [ ! -d "/etc/cron.d" ]; then
    log_message "INFO" "Creating /etc/cron.d directory..."
    mkdir -p /etc/cron.d
    chmod 755 /etc/cron.d
fi

# Create the cron job file with proper permissions
log_message "INFO" "Creating backup cron job..."
# Create cron job file for Amazon Linux
if [ "$LINUX_DISTRO" == "Amazon Linux" ]; then
    cat << EOF > /etc/cron.d/minecraft-world-backup
# Minecraft world backup - runs daily at midnight
0 0 * * * ec2-user /opt/minecraft/world_backup.sh
EOF
fi
# Create cron job file for Ubuntu
if [ "$LINUX_DISTRO" == "Ubuntu" ]; then
    cat << EOF > /etc/cron.d/minecraft-world-backup
# Minecraft world backup - runs daily at midnight
0 0 * * * ubuntu /opt/minecraft/world_backup.sh
EOF
fi
    chmod 644 /etc/cron.d/minecraft-world-backup
    chown root:root /etc/cron.d/minecraft-world-backup
# Verify cron job file on Amazon Linux
if [ "$LINUX_DISTRO" == "Amazon Linux" ]; then
    # Verify cron service is running
    if ! systemctl is-active crond >/dev/null 2>&1; then
        log_message "WARNING" "Cron service not running, starting it..."
        systemctl start crond
    fi
fi
# Verify cron job file on Ubuntu
if [ "$LINUX_DISTRO" == "Ubuntu" ]; then
    # Verify cron service is running
    if ! systemctl is-active cron >/dev/null 2>&1; then
        log_message "WARNING" "Cron service not running, starting it..."
        systemctl start cron
    fi
fi

# Create wait-for-service function before validation
wait_for_service() {
    log_message "INFO" "Waiting for Minecraft server to be fully operational..."
    local max_attempts=30
    local attempt=1
    local wait_time=10

    while [ $attempt -le $max_attempts ]; do
        if systemctl is-active minecraft.service >/dev/null 2>&1; then
            # Check server log for startup completion
            if grep -q "Server started." /var/log/minecraft/server.log 2>/dev/null; then
                log_message "INFO" "Server is fully operational"
                return 0
            fi
        fi
        log_message "WARNING" "[$(date)] Waiting for server to start (attempt $attempt of $max_attempts)..."
        sleep $wait_time
        ((attempt++))
    done

    log_message "ERROR" "Timeout waiting for server to become operational"
    return 1
}

# Run validation suite with proper waiting
log_message "INFO" "Checking server state before validation..."
if wait_for_service; then
    log_message "INFO" "Running validation suite..."
    # Pass the region
    INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" "http://$IMDS_ENDPOINT/latest/meta-data/instance-id")
    ENVIRONMENT=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$INSTANCE_ID" "Name=key,Values=Environment" --query "Tags[0].Value" --output text)
    
    export MINECRAFT_ENVIRONMENT="$${ENVIRONMENT:-dev}"
    if [ "$LINUX_DISTRO" == "Amazon Linux" ]; then
        sudo -u ec2-user /opt/minecraft/test/validate_all.sh "$IMDS_ENDPOINT" "$IMDS_TOKEN_TTL"
    fi
    if [ "$LINUX_DISTRO" == "Ubuntu" ]; then
        sudo -u ubuntu /opt/minecraft/test/validate_all.sh "$IMDS_ENDPOINT" "$IMDS_TOKEN_TTL"
    fi
    if [ $? -eq 0 ]; then
        log_message "INFO" "Initial validation succeeded"
    else
        log_message "WARNING" "Initial validation failed, retrying after 30s..."
        sleep 30
        if [ "$LINUX_DISTRO" == "Amazon Linux" ]; then
            sudo -u ec2-user /opt/minecraft/test/validate_all.sh "$IMDS_ENDPOINT" "$IMDS_TOKEN_TTL"
        fi
        if [ "$LINUX_DISTRO" == "Ubuntu" ]; then
            sudo -u ubuntu /opt/minecraft/test/validate_all.sh "$IMDS_ENDPOINT" "$IMDS_TOKEN_TTL"
        fi
        if [ $? -eq 0 ]; then
            log_message "INFO" "Retry validation succeeded"
        else
            log_message "ERROR" "Validation failed after retry. Check logs for details"
            exit 1
        fi
    log_message "ERROR" "Server failed to become operational"
    exit 1
    fi
fi

log_message "INFO" "Server setup completed successfully"