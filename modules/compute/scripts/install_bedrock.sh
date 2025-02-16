#!/bin/bash
# Ensure script runs with root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" 
    exec sudo "$0" "$@"
fi

# Create log file and directory with proper permissions
mkdir -p /var/log/minecraft
touch /var/log/minecraft/install.log
chown -R ubuntu:ubuntu /var/log/minecraft
chmod -R 755 /var/log/minecraft

# Redirect all output to log file
exec 1> >(tee -a /var/log/minecraft/install.log)
exec 2>&1

set -ex  # Exit on error, print commands

timestamp() {
    date "+%Y-%m-%d %H:%M:%S"
}

echo "[$(timestamp)] Starting Minecraft Bedrock server installation..."

# Update package lists
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
DEBIAN_FRONTEND=noninteractive apt-get install -y unzip curl wget libcurl4 libssl3

# Create minecraft directory
mkdir -p /opt/minecraft
cd /opt/minecraft

# Download Bedrock server with dynamic URL fetching
MAX_RETRIES=3
RETRY_COUNT=0

echo "[$(timestamp)] Fetching download URL from Minecraft website..."
while [ "${RETRY_COUNT}" -lt "${MAX_RETRIES}" ]; do
    # Try to download from the official preview page
    DOWNLOAD_URL=$(curl -H "Accept-Encoding: identity" -H "Accept-Language: en" -s -L -A "Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1; BEDROCK-UPDATER)" https://minecraft.net/en-us/download/server/bedrock/ | grep -o 'https.*/bin-linux/.*.zip' || echo '')
    if [ -n "${DOWNLOAD_URL}" ]; then
        echo "[$(timestamp)] Found download URL: ${DOWNLOAD_URL}"
        if wget -U "Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1; BEDROCK-UPDATER)" "${DOWNLOAD_URL}" -O bedrock-server.zip; then
            echo "[$(timestamp)] Download successful"
            break
        fi
    fi
    
    # Fallback to direct download from known URL pattern
    FALLBACK_URL="https://www.minecraft.net/bedrockdedicatedserver/bin-linux/bedrock-server-1.21.60.10.zip"
    echo "[$(timestamp)] Trying fallback URL: ${FALLBACK_URL}"
    if wget -U "Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1; BEDROCK-UPDATER)" "${FALLBACK_URL}" -O bedrock-server.zip; then
        echo "[$(timestamp)] Fallback download successful"
        break
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "[$(timestamp)] Download attempt ${RETRY_COUNT} failed, retrying in 5 seconds..."
    sleep 5
done

if [ "${RETRY_COUNT}" -eq "${MAX_RETRIES}" ]; then
    echo "[$(timestamp)] Failed to download server after ${MAX_RETRIES} attempts"
    exit 1
fi

# Extract server files
unzip -o bedrock-server.zip
rm bedrock-server.zip

# Set correct permissions
chown -R ubuntu:ubuntu /opt/minecraft
chmod +x bedrock_server

# Create and configure service
cat > /etc/systemd/system/minecraft.service <<'EOF'
[Unit]
Description=Minecraft Bedrock Server
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/minecraft
ExecStart=/opt/minecraft/bedrock_server
Restart=on-failure
RestartSec=5
StandardOutput=append:/var/log/minecraft/server.log
StandardError=append:/var/log/minecraft/server.log
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# Configure server settings
cat > /opt/minecraft/server.properties <<'EOF'
server-name=AWS Minecraft Server
gamemode=survival
difficulty=normal
allow-cheats=false
max-players=10
online-mode=true
white-list=false
server-port=19132
server-portv6=19133
view-distance=32
tick-distance=4
player-idle-timeout=30
max-threads=8
default-player-permission-level=member
texturepack-required=false
content-log-file-enabled=true
compression-threshold=1
server-authoritative-movement=server-auth
player-movement-score-threshold=20
player-movement-action-direction-threshold=0.85
EOF

# Configure system limits
cat >> /etc/sysctl.conf <<'EOF'
fs.file-max = 65535
EOF

cat >> /etc/security/limits.conf <<'EOF'
ubuntu soft nofile 65535
ubuntu hard nofile 65535
EOF

sysctl -p

# Start service
systemctl daemon-reload
systemctl enable minecraft
systemctl start minecraft

echo "[$(timestamp)] Installation completed successfully"