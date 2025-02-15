#!/bin/bash
set -e

# Create mount point and minecraft directories
mkdir -p /opt/minecraft
mkdir -p /mnt/minecraft_data

# Format the EBS volume if it's not already formatted
if ! blkid /dev/xvdf; then
    mkfs -t ext4 /dev/xvdf
fi

# Add fstab entry for automatic mounting on reboot
echo '/dev/xvdf /mnt/minecraft_data ext4 defaults,nofail 0 2' >> /etc/fstab

# Mount the volume
mount /mnt/minecraft_data

# If this is first time setup, prepare the data directory
if [ ! -d "/mnt/minecraft_data/worlds" ]; then
    mkdir -p /mnt/minecraft_data/worlds
    mkdir -p /mnt/minecraft_data/backups
    chown -R ubuntu:ubuntu /mnt/minecraft_data
fi

# Create symbolic link for world data
ln -s /mnt/minecraft_data/worlds /opt/minecraft/worlds
ln -s /mnt/minecraft_data/backups /opt/minecraft/backups

# Run the server installation script
${install_script}

# Move any generated world data to persistent storage
if [ -d "/opt/minecraft/worlds" ] && [ ! -L "/opt/minecraft/worlds" ]; then
    mv /opt/minecraft/worlds/* /mnt/minecraft_data/worlds/
    rm -rf /opt/minecraft/worlds
    ln -s /mnt/minecraft_data/worlds /opt/minecraft/worlds
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

# Ensure proper permissions
chown -R ubuntu:ubuntu /opt/minecraft
chmod -R 755 /opt/minecraft