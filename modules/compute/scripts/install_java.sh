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

echo "[$(date)] Starting Minecraft Java server installation..."

# Update package lists
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# Add Java 21 repository and install
add-apt-repository -y ppa:linuxuprising/java
apt-get update
echo debconf shared/accepted-oracle-license-v1-3 select true | debconf-set-selections
DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-21-jre-headless curl wget

# Create minecraft directory
mkdir -p /opt/minecraft
cd /opt/minecraft

# Download Java server with retry logic
MAX_RETRIES=3
RETRY_COUNT=0
DOWNLOAD_URL="https://piston-data.mojang.com/v1/objects/4707d00eb834b446575d89a61a11b5d548d8c001/server.jar"

echo "[$(date)] Downloading Minecraft Java server..."
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if wget --no-verbose -O server.jar "$DOWNLOAD_URL"; then
        echo "[$(date)] Download successful"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "[$(date)] Download attempt $RETRY_COUNT failed, retrying in 5 seconds..."
    sleep 5
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "[$(date)] Failed to download server after $MAX_RETRIES attempts"
    exit 1
fi

# Accept EULA
echo "eula=true" > eula.txt

# Create server.properties with optimized settings
cat > /opt/minecraft/server.properties <<'EOF'
server-port=25565
max-players=10
gamemode=survival
difficulty=normal
allow-flight=false
view-distance=8
simulation-distance=8
spawn-protection=16
max-world-size=29999984
network-compression-threshold=256
enable-jmx-monitoring=false
enable-rcon=false
enable-query=false
enable-status=true
enforce-secure-profile=true
online-mode=true
prevent-proxy-connections=false
use-native-transport=true
motd=AWS Minecraft Java Server
white-list=false
enforce-whitelist=false
broadcast-rcon-to-ops=true
spawn-monsters=true
spawn-animals=true
spawn-npcs=true
EOF

# Set correct permissions
chown -R ubuntu:ubuntu /opt/minecraft
chmod -R 755 /opt/minecraft

# Create and configure service
cat > /etc/systemd/system/minecraft.service <<'EOF'
[Unit]
Description=Minecraft Java Server
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/minecraft
ExecStart=/usr/bin/java -Xmx1024M -Xms512M -XX:+UseG1GC -XX:+ParallelRefProcEnabled \
    -XX:MaxGCPauseMillis=200 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC \
    -XX:+AlwaysPreTouch -XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 \
    -XX:G1HeapRegionSize=8M -XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 \
    -XX:G1MixedGCCountTarget=4 -XX:InitiatingHeapOccupancyPercent=15 \
    -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1RSetUpdatingPauseTimePercent=5 \
    -XX:SurvivorRatio=32 -XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1 \
    -jar server.jar nogui
Restart=on-failure
RestartSec=5
StandardOutput=append:/var/log/minecraft/server.log
StandardError=append:/var/log/minecraft/server.log
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
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

echo "[$(date)] Installation completed successfully"