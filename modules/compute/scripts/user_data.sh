#!/bin/bash
set -e

echo "[$(date)] Starting Minecraft server setup..."

# Create mount point and minecraft directories
mkdir -p /opt/minecraft
mkdir -p /mnt/minecraft_data

# Function to find the EBS device
find_ebs_device() {
    # Check traditional xvdf device
    if [ -e /dev/xvdf ]; then
        echo "/dev/xvdf"
        return 0
    fi
    
    # Check NVMe device (common in newer instance types)
    if [ -e /dev/nvme1n1 ]; then
        echo "/dev/nvme1n1"
        return 0
    fi
    
    return 1
}

# Wait for EBS volume to be attached
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

# Format the EBS volume if it's not already formatted
if ! blkid $EBS_DEVICE; then
    echo "[$(date)] Formatting EBS volume..."
    mkfs -t ext4 $EBS_DEVICE
fi

# Add fstab entry for automatic mounting on reboot
echo "$EBS_DEVICE /mnt/minecraft_data ext4 defaults,nofail 0 2" >> /etc/fstab

# Mount the volume
echo "[$(date)] Mounting EBS volume..."
mount /mnt/minecraft_data || {
    echo "[$(date)] Mount failed, waiting 30s and trying again..."
    sleep 30
    mount /mnt/minecraft_data
}

# If this is first time setup, prepare the data directory
if [ ! -d "/mnt/minecraft_data/worlds" ]; then
    mkdir -p /mnt/minecraft_data/worlds
    mkdir -p /mnt/minecraft_data/backups
    chown -R ubuntu:ubuntu /mnt/minecraft_data
fi

# Create symbolic link for world data
ln -sf /mnt/minecraft_data/worlds /opt/minecraft/worlds
ln -sf /mnt/minecraft_data/backups /opt/minecraft/backups

# Write install script to file and execute it
echo "[$(date)] Running server installation script..."
cat > /tmp/install.sh <<'EOSCRIPT'
${install_script}
EOSCRIPT

chmod +x /tmp/install.sh
/tmp/install.sh

# Move any generated world data to persistent storage
if [ -d "/opt/minecraft/worlds" ] && [ ! -L "/opt/minecraft/worlds" ]; then
    mv /opt/minecraft/worlds/* /mnt/minecraft_data/worlds/
    rm -rf /opt/minecraft/worlds
    ln -sf /mnt/minecraft_data/worlds /opt/minecraft/worlds
fi

# Set up backup script
cat > /opt/minecraft/backup.sh <<'EOF'
#!/bin/bash
BACKUP_DIR="/mnt/minecraft_data/backups"
WORLDS_DIR="/mnt/minecraft_data/worlds"
DATE=$(date +%Y%m%d_%H%M%S)

# Create backup
tar -czf "$BACKUP_DIR/world_backup_$DATE.tar.gz" -C "$WORLDS_DIR" .

# Keep only last 5 backups
ls -t "$BACKUP_DIR"/world_backup_*.tar.gz | tail -n +6 | xargs -r rm
EOF

chmod +x /opt/minecraft/backup.sh

# Set up daily backup cron job
echo "0 0 * * * ubuntu /opt/minecraft/backup.sh" > /etc/cron.d/minecraft-backup

# Create systemd service file
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

# Create server startup script
cat > /opt/minecraft/run_server.sh <<'EOF'
#!/bin/bash
cd /opt/minecraft

# Wait for network and EBS volume
while ! ping -c 1 -W 1 8.8.8.8; do
    echo "Waiting for network..."
    sleep 1
done

while ! mountpoint -q /mnt/minecraft_data; do
    echo "Waiting for data volume..."
    sleep 1
done

# Start the appropriate server
if [ -f "bedrock_server" ]; then
    ./bedrock_server
elif [ -f "server.jar" ]; then
    exec java -Xms512M -Xmx1024M -XX:+UseG1GC -jar server.jar nogui
fi
EOF

chmod +x /opt/minecraft/run_server.sh

# Create test directories and set up test scripts
echo "[$(date)] Setting up test scripts..."
mkdir -p /opt/minecraft/test

# Write test_server.sh
cat > /opt/minecraft/test/test_server.sh <<'EOTESTSERVER'
${file("${path.module}/scripts/test_server.sh")}
EOTESTSERVER

# Write test_backup.sh
cat > /opt/minecraft/test/test_backup.sh <<'EOTESTBACKUP'
${file("${path.module}/scripts/test_backup.sh")}
EOTESTBACKUP

# Write validate_all.sh
cat > /opt/minecraft/test/validate_all.sh <<'EOTESTVALIDATE'
${file("${path.module}/scripts/validate_all.sh")}
EOTESTVALIDATE

chmod +x /opt/minecraft/test/*.sh
chown -R ubuntu:ubuntu /opt/minecraft/test

# Ensure proper permissions for all directories
dirs_to_check=("/opt/minecraft" "/mnt/minecraft_data" "/var/log/minecraft" "/opt/minecraft/test")
for dir in "${dirs_to_check[@]}"; do
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
    fi
    chown -R ubuntu:ubuntu "$dir"
    chmod -R 755 "$dir"
done

# Enable and start the service
echo "[$(date)] Starting Minecraft service..."
systemctl daemon-reload
systemctl enable minecraft
systemctl start minecraft

# Wait for service to fully initialize
echo "[$(date)] Waiting for server initialization..."
sleep 60

# Run server validation tests
echo "[$(date)] Running server validation tests..."
/opt/minecraft/test/test_server.sh
SERVER_STATUS=$?

# Run backup validation tests
echo "[$(date)] Running backup validation tests..."
mkdir -p /var/log/minecraft/test
/opt/minecraft/test/test_backup.sh > /var/log/minecraft/test/backup_validation.log 2>&1
BACKUP_STATUS=$?

# Write final status
echo "{\"server_status\": $SERVER_STATUS, \"backup_status\": $BACKUP_STATUS}" > /var/log/minecraft/test/validation_status.json

# Overall status combines both server and backup validation
if [ $SERVER_STATUS -eq 0 ] && [ $BACKUP_STATUS -eq 0 ]; then
    echo "[$(date)] All validation tests completed successfully"
    exit 0
else
    echo "[$(date)] One or more validation tests failed. Check /var/log/minecraft/test/validation_status.json for details"
    exit 1
fi

# After starting the service, run full validation with error handling
echo "[$(date)] Running full validation suite..."
if ! sudo -u ubuntu /opt/minecraft/test/validate_all.sh; then
    echo "[$(date)] Initial validation failed, retrying after 30s..."
    sleep 30
    sudo -u ubuntu /opt/minecraft/test/validate_all.sh
fi

# Check validation results with more detailed error reporting
if [ -f "/var/log/minecraft/full_validation_success" ]; then
    echo "[$(date)] All validation tests completed successfully"
    exit 0
else
    echo "[$(date)] Validation failed. Detailed error report:"
    echo "----------------------------------------"
    if [ -f "/var/log/minecraft/validation_status.json" ]; then
        cat /var/log/minecraft/validation_status.json
    fi
    if [ -f "/var/log/minecraft/validation.log" ]; then
        tail -n 50 /var/log/minecraft/validation.log
    fi
    echo "----------------------------------------"
    exit 1
fi