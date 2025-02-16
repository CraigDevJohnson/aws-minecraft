#!/bin/bash
set -e

# Enable debug logging
exec 1> >(tee -a /var/log/cloud-init-output.log)
exec 2>&1
set -x

# Add error handling function
handle_error() {
    local exit_code=$?
    echo "[$(date)] Error on line $1: Exit code $exit_code"
    exit $exit_code
}

# Set up error handling
trap 'handle_error $LINENO' ERR

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

# Create mount point and minecraft directories
mkdir -p /opt/minecraft
mkdir -p /mnt/minecraft_data

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

# Format if needed
if ! blkid $EBS_DEVICE; then
    echo "[$(date)] Formatting EBS volume..."
    mkfs -t ext4 $EBS_DEVICE
fi

# Add fstab entry
echo "$EBS_DEVICE /mnt/minecraft_data ext4 defaults,nofail 0 2" >> /etc/fstab

# Mount volume
echo "[$(date)] Mounting EBS volume..."
mount /mnt/minecraft_data || {
    echo "[$(date)] Mount failed, waiting 30s and trying again..."
    sleep 30
    mount /mnt/minecraft_data
}

# Prepare data directory
if [ ! -d "/mnt/minecraft_data/worlds" ]; then
    mkdir -p /mnt/minecraft_data/worlds
    mkdir -p /mnt/minecraft_data/backups
    chown -R ubuntu:ubuntu /mnt/minecraft_data
fi

# Create symbolic links
ln -sf /mnt/minecraft_data/worlds /opt/minecraft/worlds
ln -sf /mnt/minecraft_data/backups /opt/minecraft/backups

# Download server installation script from S3
echo "[$(date)] Downloading installation script from S3..."
aws s3 cp "s3://${bucket_name}/${install_key}" /tmp/install.sh
chmod +x /tmp/install.sh

echo "[$(date)] Running server installation script..."
/tmp/install.sh "${server_type}"

# Move world data if needed
if [ -d "/opt/minecraft/worlds" ] && [ ! -L "/opt/minecraft/worlds" ]; then
    mv /opt/minecraft/worlds/* /mnt/minecraft_data/worlds/
    rm -rf /opt/minecraft/worlds
    ln -sf /mnt/minecraft_data/worlds /opt/minecraft/worlds
fi

# Backup script
cat > /opt/minecraft/backup.sh <<'EOSCRIPT'
#!/bin/bash
BACKUP_DIR="/mnt/minecraft_data/backups"
WORLDS_DIR="/mnt/minecraft_data/worlds"
DATE=$(date +%Y%m%d_%H%M%S)

tar -czf "$BACKUP_DIR/world_backup_$DATE.tar.gz" -C "$WORLDS_DIR" .
ls -t "$BACKUP_DIR"/world_backup_*.tar.gz | tail -n +6 | xargs -r rm
EOSCRIPT

chmod +x /opt/minecraft/backup.sh

# Setup backup cron
echo "0 0 * * * ubuntu /opt/minecraft/backup.sh" > /etc/cron.d/minecraft-backup

# Create systemd service
echo "[$(date)] Creating systemd service..."
cat > /etc/systemd/system/minecraft.service <<'EOF'
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

# Server startup script
cat > /opt/minecraft/run_server.sh <<'EOSCRIPT'
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

# Setup test environment
echo "[$(date)] Setting up test scripts..."
mkdir -p /opt/minecraft/test

# Add IMDSv2 token handling function
get_imds_token() {
    TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$TOKEN" ]; then
        echo "$TOKEN"
        return 0
    fi
    return 1
}

# Update the download_script function
download_script() {
    local script_name="$1"
    local dest_path="$2"
    local max_retries=5
    local retry_count=0
    local wait_time=5

    echo "[$(date)] Downloading $script_name..."
    while [ $retry_count -lt $max_retries ]; do
        # Get IMDSv2 token
        TOKEN=$(get_imds_token)
        if [ $? -ne 0 ]; then
            echo "[$(date)] Failed to get IMDSv2 token, waiting..."
            sleep $wait_time
            wait_time=$((wait_time * 2))
            retry_count=$((retry_count + 1))
            continue
        fi

        # Check instance profile
        ROLE=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/iam/security-credentials/)
        if [ -z "$ROLE" ]; then
            echo "[$(date)] IAM role not available, waiting..."
            sleep $wait_time
            wait_time=$((wait_time * 2))
            retry_count=$((retry_count + 1))
            continue
        fi

        # Get credentials
        CREDENTIALS=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE)
        if [ $? -eq 0 ] && echo "$CREDENTIALS" | jq -e .AccessKeyId >/dev/null 2>&1; then
            # Configure AWS CLI with temporary credentials
            export AWS_ACCESS_KEY_ID=$(echo "$CREDENTIALS" | jq -r .AccessKeyId)
            export AWS_SECRET_ACCESS_KEY=$(echo "$CREDENTIALS" | jq -r .SecretAccessKey)
            export AWS_SESSION_TOKEN=$(echo "$CREDENTIALS" | jq -r .Token)

            # Attempt to download and process the script
            if aws s3 cp "s3://${bucket_name}/$script_name" - 2>/dev/null | base64 -d > "$dest_path"; then
                if [ -f "$dest_path" ] && [ -s "$dest_path" ]; then
                    chmod +x "$dest_path"
                    sed -i 's/\r$//' "$dest_path"
                    echo "[$(date)] Successfully downloaded and verified $script_name"
                    return 0
                fi
            fi
        fi

        echo "[$(date)] Retry $retry_count/$max_retries for $script_name"
        sleep $wait_time
        wait_time=$((wait_time * 2))
        retry_count=$((retry_count + 1))
    done

    echo "[$(date)] Failed to download $script_name after $max_retries attempts"
    return 1
}

# Parse script keys from JSON
eval "$(echo '${script_keys_map}' | jq -r 'to_entries[] | "script_" + (.key | gsub("[.]"; "_")) + "=" + .value')"

# Download all required scripts
failed_downloads=0
for script_var in $(echo '${script_keys_map}' | jq -r 'keys[]'); do
    script_name=$(echo '${script_keys_map}' | jq -r --arg key "$script_var" '.[$key]')
    dest_path="/opt/minecraft/test/$script_name"
    if ! download_script "$script_name" "$dest_path"; then
        failed_downloads=$((failed_downloads + 1))
    fi
done

# Set correct permissions
chown -R ubuntu:ubuntu /opt/minecraft/test
chmod -R 755 /opt/minecraft/test

# Setup logging
mkdir -p /var/log/minecraft/test
chown -R ubuntu:ubuntu /var/log/minecraft

# Run validation suite
echo "[$(date)] Running validation suite..."
if sudo -u ubuntu /opt/minecraft/test/validate_all.sh; then
    echo "[$(date)] Initial validation succeeded"
else
    echo "[$(date)] Initial validation failed, retrying after 30s..."
    sleep 30
    if sudo -u ubuntu /opt/minecraft/test/validate_all.sh; then
        echo "[$(date)] Retry validation succeeded"
    else
        echo "[$(date)] Validation failed after retry. Check logs for details"
        exit 1
    fi
fi

echo "[$(date)] Server setup completed successfully"