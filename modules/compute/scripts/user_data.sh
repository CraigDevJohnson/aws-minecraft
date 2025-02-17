#!/bin/bash
set -e

# Constants
IMDS_ENDPOINT="${imds_endpoint}"
IMDS_TOKEN_TTL="${imds_token_ttl}"
BUCKET_NAME="${bucket_name}"
INSTALL_SCRIPT="${install_key}"
TEST_SERVER_SCRIPT="${test_server_script}"
VALIDATE_SCRIPT="${validate_script}"
BACKUP_SCRIPT="${backup_script}"
SERVER_TYPE="${server_type}"

# Enable debug logging
exec 1> >(tee -a /var/log/cloud-init-output.log)
exec 2>&1
set -x

# Script start
echo "[$(date)] Starting Minecraft server setup..."

# Install required packages
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y jq unzip curl

# Install AWS CLI v2
echo "[$(date)] Installing AWS CLI..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

# Function to find the EBS device
find_ebs_device() {
    if [ -e /dev/xvdf ]; then
        echo "/dev/xvdf"
        return 0
    fi
    
    if [ -e /dev/nvme1n1 ]; then
        echo "/dev/nvme1n1"
        return 0
    fi
    
    return 1
}

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

while [ $${mount_attempts} -lt $${max_mount_attempts} ]; do
    if mount /mnt/minecraft_data; then
        echo "[$(date)] Successfully mounted $${EBS_DEVICE} to /mnt/minecraft_data"
        break
    else
        mount_attempts=$((mount_attempts + 1))
        if [ $${mount_attempts} -eq $${max_mount_attempts} ]; then
            echo "[$(date)] Failed to mount volume after $${max_mount_attempts} attempts"
            exit 1
        fi
        echo "[$(date)] Mount attempt $${mount_attempts} failed, waiting 10s before retry..."
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

# Prepare data directory
if [ ! -d "/mnt/minecraft_data/worlds" ]; then
    mkdir -p /mnt/minecraft_data/worlds
    mkdir -p /mnt/minecraft_data/backups
    chown -R ubuntu:ubuntu /mnt/minecraft_data
fi

# Create directory structure with error checking
create_directories() {
    local base_dirs="/opt/minecraft /opt/minecraft/test /mnt/minecraft_data/worlds /mnt/minecraft_data/backups"
    
    for dir in $base_dirs; do
        if ! mkdir -p "$dir"; then
            echo "[$(date)] Failed to create directory: $dir" >&2
            return 1
        fi
    done
    
    # Set permissions
    if ! chown -R ubuntu:ubuntu /opt/minecraft /mnt/minecraft_data; then
        echo "[$(date)] Failed to set directory ownership" >&2
        return 1
    fi
    
    if ! chmod 755 /opt/minecraft /mnt/minecraft_data; then
        echo "[$(date)] Failed to set directory permissions" >&2
        return 1
    fi
    
    return 0
}

# Create symbolic links with error checking
create_symlinks() {
    local src_dest="
        /mnt/minecraft_data/worlds:/opt/minecraft/worlds
        /mnt/minecraft_data/backups:/opt/minecraft/backups
    "
    
    echo "$src_dest" | while IFS=: read -r src dest; do
        # Skip empty lines
        [ -z "$src" ] && continue
        
        # Trim whitespace
        src=$(echo "$src" | xargs)
        dest=$(echo "$dest" | xargs)
        
        if ! ln -sf "$src" "$dest"; then
            echo "[$(date)] Failed to create symlink: $src -> $dest" >&2
            return 1
        fi
    done
    
    return 0
}

echo "[$(date)] Creating symbolic links..."
if ! create_symlinks; then
    echo "[$(date)] Failed to create symbolic links"
    exit 1
fi

# Get IMDSv2 token for metadata access
TOKEN=$$(curl -X PUT "http://$${IMDS_ENDPOINT}/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: $${IMDS_TOKEN_TTL}" --retry 3)

# Get region from instance metadata
REGION=$$(curl -H "X-aws-ec2-metadata-token: $${TOKEN}" "http://$${IMDS_ENDPOINT}/latest/meta-data/placement/region")

# Configure AWS CLI region
aws configure set region "$${REGION}"

# Download and setup scripts
echo "[$(date)] Downloading scripts from S3..."

# Create test directory
mkdir -p /opt/minecraft/test
chown -R ubuntu:ubuntu /opt/minecraft/test
chmod 755 /opt/minecraft/test

# Download install script
aws s3 cp "s3://$${BUCKET_NAME}/$${INSTALL_SCRIPT}" /tmp/install.sh
chmod +x /tmp/install.sh

# Download test scripts
echo "[$(date)] Downloading test server script..."
aws s3 cp "s3://$${BUCKET_NAME}/$${TEST_SERVER_SCRIPT}" /opt/minecraft/test/test_server.sh
chmod +x /opt/minecraft/test/test_server.sh

echo "[$(date)] Downloading validation script..."
aws s3 cp "s3://$${BUCKET_NAME}/$${VALIDATE_SCRIPT}" /opt/minecraft/test/validate_all.sh
chmod +x /opt/minecraft/test/validate_all.sh

echo "[$(date)] Downloading backup test script..."
aws s3 cp "s3://$${BUCKET_NAME}/$${BACKUP_SCRIPT}" /opt/minecraft/test/test_backup.sh
chmod +x /opt/minecraft/test/test_backup.sh

# Setup logging directory
mkdir -p /var/log/minecraft/test
chown -R ubuntu:ubuntu /var/log/minecraft

# Run server installation
echo "[$(date)] Running server installation script..."
/tmp/install.sh "$${SERVER_TYPE}"

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

# Define backup locations
BACKUP_DIR="/mnt/minecraft_data/backups"
WORLDS_DIR="/mnt/minecraft_data/worlds"
DATE=$(date +%Y%m%d_%H%M%S)

# Ensure backup directory exists
mkdir -p "BACKUP_DIR"

# Create backup with error handling
if ! tar -czf "BACKUP_DIR/world_backup_DATE.tar.gz" -C "WORLDS_DIR" .; then
    echo "[$(date)] Backup failed" | tee -a /var/log/minecraft/backup.log
    exit 1
fi

# Cleanup old backups (keep last 5)
ls -t "BACKUP_DIR"/world_backup_*.tar.gz | tail -n +6 | xargs -r rm

echo "[$(date)] Backup completed successfully" | tee -a /var/log/minecraft/backup.log
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
cat > /opt/minecraft/run_server.sh << EOSCRIPT
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
EOSCRIPT

chmod +x /opt/minecraft/run_server.sh

# Run validation suite
echo "[$(date)] Running validation suite..."
if sudo -u ubuntu /opt/minecraft/test/validate_all.sh "$${IMDS_ENDPOINT}" "$${IMDS_TOKEN_TTL}"; then
    echo "[$(date)] Initial validation succeeded"
else
    echo "[$(date)] Initial validation failed, retrying after 30s..."
    sleep 30
    if sudo -u ubuntu /opt/minecraft/test/validate_all.sh "$${IMDS_ENDPOINT}" "$${IMDS_TOKEN_TTL}"; then
        echo "[$(date)] Retry validation succeeded"
    else
        echo "[$(date)] Validation failed after retry. Check logs for details"
        exit 1
    fi
fi

echo "[$(date)] Server setup completed successfully"