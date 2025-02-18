#!/bin/bash
set -e

# Constants for terraform template variables - single $
IMDS_ENDPOINT="${imds_endpoint}"
IMDS_TOKEN_TTL="${imds_token_ttl}"
BUCKET_NAME="${bucket_name}"
INSTALL_SCRIPT="${install_key}"
TEST_SERVER_SCRIPT="${test_server_script}"
VALIDATE_SCRIPT="${validate_script}"
BACKUP_SCRIPT="${backup_script}"
SERVER_TYPE="${server_type}"
CLOUD_INIT_OUTPUT_LOG="/var/log/cloud-init-output.log"
APT_PACKAGES="jq curl"
SNAP_AWSCLI= "awscli"


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
    log_message "INFO" "Installed $APT_PACKAGES packages successfully: $JQ_VERSION, $CURL_VERSION"
else
    log_message "ERROR" "Failed to install required packages"
    exit 1
fi

# Install AWS CLI v2
log_message "INFO" "Installing AWS CLI..."
snap install $SNAP_AWSCLI --classic
$AWSCLI_VERSION=$(aws --version)
if [ -n "$AWSCLI_VERSION" ]; then
    log_message "INFO" "AWS CLI installed successfully: $AWSCLI_VERSION"
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
        log_message "INFO" "Found EBS device: $FOUND_DEVICE"
        echo "$FOUND_DEVICE"
        return 0
    fi
    log _message "ERROR" "EBS device not found"
    return 1
}
############## KEEP UPDATING FROM HERE ##############
# Wait for EBS volume
echo "[$(date)] Waiting for EBS volume to be attached..."
EBS_DEVICE=""
for i in {1..30}; do
    if EBS_DEVICE=$(find_ebs_device); then
        echo "[$(date)] Found EBS volume at $EBS_DEVICE"
        break
    fi
    echo "[$(date)] Still waiting for EBS volume... (attempt $i/30)"
    sleep 5
done

if [ -z "$EBS_DEVICE" ]; then
    echo "[$(date)] Failed to find EBS volume after timeout"
    exit 1
fi

# Create mount point
mkdir -p /mnt/minecraft_data

# Format if needed (only if not already formatted)
if ! blkid "$EBS_DEVICE" >/dev/null 2>&1; then
    echo "[$(date)] Formatting EBS volume at $EBS_DEVICE..."
    mkfs.ext4 "$EBS_DEVICE"
fi

# Add fstab entry (remove old entry first if exists)
sed -i "\|^$EBS_DEVICE|d" /etc/fstab
echo "$EBS_DEVICE /mnt/minecraft_data ext4 defaults,nofail 0 2" >> /etc/fstab

# Mount volume with retries
echo "[$(date)] Mounting EBS volume..."
mount_attempts=0
max_mount_attempts=3

while [ "$mount_attempts" -lt "$max_mount_attempts" ]; do
    if mount /mnt/minecraft_data; then
        echo "[$(date)] Successfully mounted $EBS_DEVICE to /mnt/minecraft_data"
        break
    else
        mount_attempts=$((mount_attempts + 1))
        if [ "$mount_attempts" -eq "$max_mount_attempts" ]; then
            echo "[$(date)] Failed to mount volume after $max_mount_attempts attempts"
            exit 1
        fi
        echo "[$(date)] Mount attempt $mount_attempts failed, waiting 10s before retry..."
        sleep 10
    fi
done

# Verify mount and set permissions
if mountpoint -q /mnt/minecraft_data; then
    echo "[$(date)] Setting up permissions for mounted volume..."
    chown -R ubuntu:ubuntu /mnt/minecraft_data
    chmod 755 /mnt/minecraft_data
else
    echo "[$(date)] Mount verification failed"
    exit 1
fi

# Create directories with proper permissions
echo "[$(date)] Creating required directories..."
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
echo "[$(date)] Setting directory permissions..."
chown -R ubuntu:ubuntu /opt/minecraft /mnt/minecraft_data /var/log/minecraft
chmod 755 /opt/minecraft /mnt/minecraft_data /var/log/minecraft

# Create symbolic links
echo "[$(date)] Creating symbolic links..."
ln -sf /mnt/minecraft_data/worlds /opt/minecraft/worlds
ln -sf /mnt/minecraft_data/backups /opt/minecraft/backups

# Get IMDSv2 token for metadata access - use double $$ for bash variables that shouldn't be interpolated by terraform
TOKEN=$(curl -X PUT "http://$IMDS_ENDPOINT/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: $IMDS_TOKEN_TTL" --retry 3)

# Get region from instance metadata
REGION=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" "http://$IMDS_ENDPOINT/latest/meta-data/placement/region")

# Configure AWS CLI region
aws configure set region "$REGION"

# Download and setup scripts
echo "[$(date)] Downloading scripts from S3..."

# Create test directory
mkdir -p /opt/minecraft/test
chown -R ubuntu:ubuntu /opt/minecraft/test
chmod 755 /opt/minecraft/test

# Download install script
aws s3 cp "s3://$BUCKET_NAME/$INSTALL_SCRIPT" /tmp/install.sh
chmod +x /tmp/install.sh

# Download test scripts
echo "[$(date)] Downloading test server script..."
aws s3 cp "s3://$BUCKET_NAME/$TEST_SERVER_SCRIPT" /opt/minecraft/test/test_server.sh
chmod +x /opt/minecraft/test/test_server.sh

echo "[$(date)] Downloading validation script..."
aws s3 cp "s3://$BUCKET_NAME/$VALIDATE_SCRIPT" /opt/minecraft/test/validate_all.sh
chmod +x /opt/minecraft/test/validate_all.sh

echo "[$(date)] Downloading backup test script..."
aws s3 cp "s3://$BUCKET_NAME/$BACKUP_SCRIPT" /opt/minecraft/test/test_backup.sh
chmod +x /opt/minecraft/test/test_backup.sh

# Setup logging directory
mkdir -p /var/log/minecraft/test
chown -R ubuntu:ubuntu /var/log/minecraft

# Run server installation
echo "[$(date)] Running server installation script..."
/tmp/install.sh "$SERVER_TYPE"

# Move world data if needed
if [ -d "/opt/minecraft/worlds" ] && [ ! -L "/opt/minecraft/worlds" ]; then
    mv /opt/minecraft/worlds/* /mnt/minecraft_data/worlds/
    rm -rf /opt/minecraft/worlds
    ln -sf /mnt/minecraft_data/worlds /opt/minecraft/worlds
fi

# Create backup script
cat > /opt/minecraft/backup.sh << 'EOF'
#!/bin/bash
set -e

BACKUP_DIR="/mnt/minecraft_data/backups"
WORLDS_DIR="/mnt/minecraft_data/worlds"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p "$BACKUP_DIR"

if ! tar -czf "$BACKUP_DIR/world_backup_$DATE.tar.gz" -C "$WORLDS_DIR" .; then
    echo "[$(date)] [ERROR] Backup failed" | tee -a /var/log/minecraft/backup.log
    exit 1
fi

ls -t "$BACKUP_DIR"/world_backup_*.tar.gz | tail -n +6 | xargs -r rm

echo "[$(date)] [INFO] Backup completed successfully" | tee -a /var/log/minecraft/backup.log
exit 0
EOF

chmod +x /opt/minecraft/backup.sh

# Setup backup cron
echo "0 0 * * * ubuntu /opt/minecraft/backup.sh" > /etc/cron.d/minecraft-backup

# Create systemd service
echo "[$(date)] Creating systemd service..."
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

# Create server startup script
cat > /opt/minecraft/run_server.sh << 'EOF'
#!/bin/bash
cd /opt/minecraft

while ! ping -c 1 -W 1 8.8.8.8; do
    echo "Waiting for network..."
    sleep 1
done

while ! mountpoint -q /mnt/minecraft_data; do
    echo "Waiting for data volume..."
    sleep 1
done

if [ -f "bedrock_server" ]; then
    ./bedrock_server
elif [ -f "server.jar" ]; then
    exec java -Xms512M -Xmx1024M -XX:+UseG1GC -jar server.jar nogui
fi
EOF

chmod +x /opt/minecraft/run_server.sh

# Create wait-for-service function before validation
wait_for_service() {
    echo "[$(date)] Waiting for Minecraft server to be fully operational..."
    local max_attempts=30
    local attempt=1
    local wait_time=10

    while [ $attempt -le $max_attempts ]; do
        if systemctl is-active minecraft.service >/dev/null 2>&1; then
            # Check server log for startup completion
            if grep -q "Server started." /var/log/minecraft/server.log 2>/dev/null; then
                echo "[$(date)] Server is fully operational"
                return 0
            fi
        fi
        echo "[$(date)] Waiting for server to start (attempt $attempt of $max_attempts)..."
        sleep $wait_time
        ((attempt++))
    done

    echo "[$(date)] Timeout waiting for server to become operational"
    return 1
}

# Run validation suite with proper waiting
echo "[$(date)] Waiting for server to be ready before validation..."
if wait_for_service; then
    echo "[$(date)] Running validation suite..."
    # Pass the environment from instance tags
    INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" "http://$IMDS_ENDPOINT/latest/meta-data/instance-id")
    ENVIRONMENT=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$INSTANCE_ID" "Name=key,Values=Environment" --query "Tags[0].Value" --output text)
    
    export MINECRAFT_ENVIRONMENT="$${ENVIRONMENT:-dev}"
    if sudo -u ubuntu /opt/minecraft/test/validate_all.sh "$IMDS_ENDPOINT" "$IMDS_TOKEN_TTL"; then
        echo "[$(date)] Initial validation succeeded"
    else
        echo "[$(date)] Initial validation failed, retrying after 30s..."
        sleep 30
        if sudo -u ubuntu /opt/minecraft/test/validate_all.sh "$IMDS_ENDPOINT" "$IMDS_TOKEN_TTL"; then
            echo "[$(date)] Retry validation succeeded"
        else
            echo "[$(date)] Validation failed after retry. Check logs for details"
            exit 1
        fi
    fi
else
    echo "[$(date)] Server failed to become operational"
    exit 1
fi

echo "[$(date)] Server setup completed successfully"