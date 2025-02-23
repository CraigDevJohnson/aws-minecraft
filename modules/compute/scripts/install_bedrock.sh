#!/bin/bash
# Ensure script runs with root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" 
    exec sudo "$0" "$@"
fi

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

# Create log file and directory with proper permissions
mkdir -p /var/log/minecraft
touch /var/log/minecraft/install.log
if [ "$LINUX_DISTRO" == "Ubuntu" ]; then
    chown -R ubuntu:ubuntu /var/log/minecraft
else
    chown -R ec2-user:ec2-user /var/log/minecraft
fi
chmod -R 755 /var/log/minecraft

# Redirect all output to log file
exec 1> >(tee -a /var/log/minecraft/install.log)
exec 2>&1

set -ex  # Exit on error, print commands

timestamp() {
    date "+%Y-%m-%d %H:%M:%S"
}

echo "[$(timestamp)] Starting Minecraft Bedrock server installation..."

# Resolve Ubuntu required packages
if [ "$LINUX_DISTRO" == "Ubuntu" ]; then
    log_message "INFO" "Amazon Linux detected, installing required packages..."
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

    log_message "INFO" "Installing required apt packages ($APT_PACKAGES)..."
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

# Copy server.properties files
cp /tmp/bedrock.properties /opt/minecraft/server.properties

# Configure server allow-list
cat > /opt/minecraft/allowlist.json <<'EOF'
[
    {
        "ignoresPlayerLimit": false,
        "name": "Kankberry"
    },
    {
        "ignoresPlayerLimit": false,
        "name": "Fraid4Brave",
    }
]
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