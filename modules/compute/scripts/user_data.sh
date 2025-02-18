#!/bin/bash
set -e

# Constants for terraform template variables - single $
IMDS_ENDPOINT="${imds_endpoint}"
IMDS_TOKEN_TTL="${imds_token_ttl}"
BUCKET_NAME="${bucket_name}"
INSTALL_SCRIPT="${install_key}"
RUN_SERVER_SCRIPT="${run_server_script}"
WORLD_BACKUP_SCRIPT="${world_backup_script}"
VALIDATE_SCRIPT="${validate_script}"
TEST_SERVER_SCRIPT="${test_server_script}"
TEST_WORLD_BACKUP_SCRIPT="${test_world_backup_script}"
SERVER_TYPE="${server_type}"
CLOUD_INIT_OUTPUT_LOG="/var/log/cloud-init-output.log"
APT_PACKAGES="jq curl"
SNAP_AWSCLI="aws-cli"


# Enable debug output
DEBUG=true
# exec 1> >(tee -a /var/log/cloud-init-output.log)
# exec 2>&1
# set -x

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

# Install required packages and verify installation
log_message "INFO" "Installing required apt-get packages ($APT_PACKAGES)..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y $APT_PACKAGES
CURL_VERSION=$(curl --version | head -n 1)
JQ_VERSION=$(jq --version)
if [ -n "$CURL_VERSION" ] && [ -n "$JQ_VERSION" ]; then
    log_message "INFO" "Installed $APT_PACKAGES packages successfully"
    debug_message "JQ version: $JQ_VERSION"
    debug_message "Curl version: $CURL_VERSION"
else
    log_message "ERROR" "Failed to install required packages"
    exit 1
fi

# Install AWS CLI v2
log_message "INFO" "Installing AWS CLI..."
snap install $SNAP_AWSCLI --classic >/dev/null 2>&1
AWSCLI_VERSION=$(aws --version)
if [ -n "$AWSCLI_VERSION" ]; then
    log_message "INFO" "AWS CLI installed successfully"
    debug_message "AWS CLI version: $AWSCLI_VERSION"
else
    log_message "ERROR" "Failed to install AWS CLI"
    exit 1
fi

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
    chown -R ubuntu:ubuntu /mnt/minecraft_data
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
chown -R ubuntu:ubuntu /opt/minecraft /mnt/minecraft_data /var/log/minecraft
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

# Download and setup scripts
log_message "INFO" "Downloading scripts from S3..."

# Create test directory
mkdir -p /opt/minecraft/test
chown -R ubuntu:ubuntu /opt/minecraft/test
chmod 755 /opt/minecraft/test

# Download install script
aws s3 cp "s3://$BUCKET_NAME/$INSTALL_SCRIPT" /tmp/install.sh
chmod +x /tmp/install.sh

# Download server run script
aws s3 cp "s3://$BUCKET_NAME/$RUN_SERVER_SCRIPT" /opt/minecraft/run_server.sh
chmod +x /opt/minecraft/run_server.sh

# Download world backup script
aws s3 cp "s3://$BUCKET_NAME/$WORLD_BACKUP_SCRIPT" /opt/minecraft/world_backup.sh
chmod +x /opt/minecraft/world_backup.sh

# Download test scripts
log_message "INFO" "Downloading test server script..."
aws s3 cp "s3://$BUCKET_NAME/$TEST_SERVER_SCRIPT" /opt/minecraft/test/test_server.sh
chmod +x /opt/minecraft/test/test_server.sh

log_message "INFO" "Downloading validation script..."
aws s3 cp "s3://$BUCKET_NAME/$VALIDATE_SCRIPT" /opt/minecraft/test/validate_all.sh
chmod +x /opt/minecraft/test/validate_all.sh

log_message "INFO" "Downloading backup test script..."
aws s3 cp "s3://$BUCKET_NAME/$TEST_WORLD_BACKUP_SCRIPT" /opt/minecraft/test/test_world_backup.sh
chmod +x /opt/minecraft/test/test_world_backup.sh

# Setup logging directory
mkdir -p /var/log/minecraft/test
chown -R ubuntu:ubuntu /var/log/minecraft

# Run server installation
log_message "INFO" "Running server installation script..."
/tmp/install.sh "$SERVER_TYPE"

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
echo "0 0 * * * ubuntu /opt/minecraft/world_backup.sh" > /etc/cron.d/minecraft-world-backup

# Create systemd service
log_message "INFO" "Creating systemd service..."
cat > /etc/systemd/system/minecraft.service << 'EOF'
[Unit]
Description=Minecraft Server
After=network.target

[Service]
User=ubuntu
WorkingDirectory=/opt/minecraft
ExecStart=/opt/minecraft/run_server.sh
Restart=always
RestartSec=10
StandardOutput=append:/var/log/minecraft/server.log
StandardError=append:/var/log/minecraft/server.log

[Install]
WantedBy=multi-user.target
EOF

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
    if sudo -u ubuntu /opt/minecraft/test/validate_all.sh "$IMDS_ENDPOINT" "$IMDS_TOKEN_TTL"; then
        log_message "INFO" "Initial validation succeeded"
    else
        log_message "WARNING" "Initial validation failed, retrying after 30s..."
        sleep 30
        if sudo -u ubuntu /opt/minecraft/test/validate_all.sh "$IMDS_ENDPOINT" "$IMDS_TOKEN_TTL"; then
            log_message "INFO" "Retry validation succeeded"
        else
            log_message "ERROR" "Validation failed after retry. Check logs for details"
            exit 1
        fi
    fi
else
    log_message "ERROR" "Server failed to become operational"
    exit 1
fi

log_message "INFO" "Server setup completed successfully"