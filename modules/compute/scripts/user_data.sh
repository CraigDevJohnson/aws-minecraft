#!/bin/bash
set -e

echo "[$(date)] Starting Minecraft server setup..."

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

# Install server
echo "[$(date)] Running server installation script..."
cat > /tmp/install.sh <<EOSCRIPT
${install_script}
EOSCRIPT

chmod +x /tmp/install.sh
/tmp/install.sh

# Move world data if needed
if [ -d "/opt/minecraft/worlds" ] && [ ! -L "/opt/minecraft/worlds" ]; then
    mv /opt/minecraft/worlds/* /mnt/minecraft_data/worlds/
    rm -rf /opt/minecraft/worlds
    ln -sf /mnt/minecraft_data/worlds /opt/minecraft/worlds
fi

# Backup script
cat > /opt/minecraft/backup.sh <<EOSCRIPT
#!/bin/bash
BACKUP_DIR="/mnt/minecraft_data/backups"
WORLDS_DIR="/mnt/minecraft_data/worlds"
DATE=\$(date +%Y%m%d_%H%M%S)

tar -czf "\$BACKUP_DIR/world_backup_\$DATE.tar.gz" -C "\$WORLDS_DIR" .
ls -t "\$BACKUP_DIR"/world_backup_*.tar.gz | tail -n +6 | xargs -r rm
EOSCRIPT

chmod +x /opt/minecraft/backup.sh

# Setup backup cron
echo "0 0 * * * ubuntu /opt/minecraft/backup.sh" > /etc/cron.d/minecraft-backup

# Create systemd service
echo "[$(date)] Creating systemd service..."
cat > /etc/systemd/system/minecraft.service <<EOF
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
cat > /opt/minecraft/run_server.sh <<EOSCRIPT
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

# Install test scripts
for script in test_server.sh test_backup.sh validate_all.sh; do
    if [ -f "/tmp/$script" ]; then
        echo "[$(date)] Installing $script..."
        cp "/tmp/$script" "/opt/minecraft/test/"
        chmod +x "/opt/minecraft/test/$script"
    else
        echo "[$(date)] Warning: $script not found in /tmp"
    fi
done

# Set permissions
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