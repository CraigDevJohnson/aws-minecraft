#!/bin/bash
# This script installs Java 21 and Minecraft Java server on an Amazon Linux 2022.03 instance.
# Ensure script runs with root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" 
    exec sudo "$0" "$@"
fi

# Variables
INSTALL_LOG=/var/log/minecraft/install_java.log
DNF_PACKAGES=""
MC_DIR="/opt/minecraft"
DEBUG=false

# Determine distro
LINUX_DISTRO=$(grep -oP '^NAME=\K.+' /etc/os-release | tr -d '"')
if [ "$LINUX_DISTRO" == "Amazon Linux" ]; then
    log_message "INFO" "Detected Amazon Linux"
    LINUX_USER="ec2-user"
elif [ "$LINUX_DISTRO" == "Ubuntu" ]; then
    log_message "INFO" "Detected Ubuntu"
    LINUX_USER="ubuntu"
else
    log_message "ERROR" "Unsupported Linux distribution: $LINUX_DISTRO"
    exit 1
fi

# Create log file and directory with proper permissions
mkdir -p /var/log/minecraft
touch "$INSTALL_LOG"
if [ "$LINUX_DISTRO" == "Amazon Linux" ]; then
    chown -R "$LINUX_USER":"$LINUX_USER" /var/log/minecraft
else
    chown -R "$LINUX_USER":"$LINUX_USER" /var/log/minecraft
fi
chmod -R 755 /var/log/minecraft

set -ex  # Exit on error, print commands

# logging functions
log_message() {
    local level="$1"
    local message="$2"
    echo "[$(date)] [$level] $message" | tee -a "$INSTALL_LOG"
}

debug_message() {
    if [ "$DEBUG" = true ]; then
        log_message "DEBUG" "$1"
    fi
}

log_message "INFO" "Starting Minecraft Java server installation..."

# Resolve packages required for installation
log_message "INFO" "Installing required packages..."
if [ "$LINUX_DISTRO" == "Amazon Linux" ]; then
    # Update package lists
    dnf update -y
    dnf upgrade -y

    if ! command -v java &> /dev/null; then
        log_message "INFO" "Java not installed, adding to package list..."
        DNF_PACKAGES+=" java-21-amazon-corretto-headless"
    fi
    # Add jq to package list if not present
    if ! command -v jq &> /dev/null; then
        log_message "INFO" "jq not installed, adding to package list..."
        DNF_PACKAGES+=" jq"
    fi
    # Add curl to package list if not present
    if ! command -v curl &> /dev/null; then
        log_message "INFO" "curl not installed, adding to package list..."
        DNF_PACKAGES+=" curl"
    fi
    # Add wget to package list if not present
    if ! command -v wget &> /dev/null; then
        log_message "INFO" "wget not installed, adding to package list..."
        DNF_PACKAGES+=" wget"
    fi
    # Add AWS CLI to package list if not present (required for getting tags)
    if ! command -v aws &> /dev/null; then
        log_message "INFO" "aws-cli not installed, adding to package list..."
        DNF_PACKAGES+=" aws-cli"
    fi

    # Install required packages and verify installation
    if [[ "$DNF_PACKAGES" =~ [^[:space:]] ]]; then
        log_message "INFO" "Installing required dnf packages ($DNF_PACKAGES)..."
        dnf install -y $DNF_PACKAGES
    else
        debug_message "No DNF packages to install"
    fi
    JAVA_VERSION=$(java -version 2>&1)
    JQ_VERSION=$(jq --version)
    CURL_VERSION=$(curl --version | head -n 1)
    WGET_VERSION=$(wget --version | head -n 1)
    AWS_CLI_VERSION=$(aws --version 2>&1)
    if [ -n "$JAVA_VERSION" ] && [ -n "$JQ_VERSION" ] && [ -n "$CURL_VERSION" ] && [ -n "$WGET_VERSION" ] && [ -n "$AWS_CLI_VERSION" ]; then
        log_message "INFO" "Verified all required packages are present"
        debug_message "Java version: $JAVA_VERSION"
        debug_message "JQ version: $JQ_VERSION"
        debug_message "Curl version: $CURL_VERSION"
        debug_message "Wget version: $WGET_VERSION"
        debug_message "AWS CLI version: $AWS_CLI_VERSION"
    else
        log_message "ERROR" "Failed to verify required packages"
        exit 1
    fi
fi


# Get IMDSv2 token for metadata access
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" --retry 3 --retry-delay 1 --silent --fail)
if [ -z "$TOKEN" ]; then
    log_message "ERROR" "Failed to get IMDSv2 token"
    exit 1
fi

# Get instance ID and region
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" "http://169.254.169.254/latest/meta-data/instance-id")
REGION=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" "http://169.254.169.254/latest/meta-data/placement/region")

# Get environment from instance tags, default to dev if not found
ENVIRONMENT=$(aws ec2 describe-tags --region "$REGION" --filters "Name=resource-id,Values=$INSTANCE_ID" "Name=key,Values=Environment" --query "Tags[0].Value" --output text)
if [ -n "$ENVIRONMENT" ]; then
    log_message "INFO" "Detected environment: $ENVIRONMENT"
else
    log_message "INFO" "Environment tag not found, defaulting to 'dev'"
    ENVIRONMENT="dev"
fi

if [ "$ENVIRONMENT" = "dev" ]; then
    DEBUG=true
fi

log_message "INFO" "Creating Minecraft directory ($MC_DIR)..."
# Create minecraft directory
mkdir -p "$MC_DIR"
cd "$MC_DIR"
log_message "INFO" "Minecraft directory created and set as working directory"
# Download Java server with retry logic
MAX_RETRIES=3
RETRY_COUNT=0
# Fetch latest version manifest and extract the latest release version and download URL
log_message "INFO" "Fetching latest Minecraft server version..."
VERSION_MANIFEST=$(curl -s https://launchermeta.mojang.com/mc/game/version_manifest.json)
LATEST_RELEASE=$(echo "$VERSION_MANIFEST" | jq -r '.latest.release')
VERSION_URL=$(echo "$VERSION_MANIFEST" | jq -r --arg VERSION "$LATEST_RELEASE" '.versions[] | select(.id==$VERSION) | .url')
DOWNLOAD_URL=$(curl -s "$VERSION_URL" | jq -r '.downloads.server.url')

debug_message "INFO" "Latest version: $LATEST_RELEASE"
debug_message "INFO" "Download URL: $DOWNLOAD_URL"

log_message "INFO" "Downloading Minecraft Java server..."
while [ "${RETRY_COUNT}" -lt "${MAX_RETRIES}" ]; do
    if wget --no-verbose -O server.jar "${DOWNLOAD_URL}"; then
        log_message "INFO" "Download successful"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    log_message "WARNING" "Download attempt ${RETRY_COUNT} failed, retrying in 5 seconds..."
    sleep 5
done

if [ "${RETRY_COUNT}" -eq "${MAX_RETRIES}" ]; then
    log_message "ERROR" "Failed to download server after ${MAX_RETRIES} attempts"
    exit 1
fi

# Accept EULA
echo "eula=true" > eula.txt

# Copy server.properties files
cp /tmp/java.properties /opt/minecraft/server.properties

# Set correct permissions
if [ "$LINUX_DISTRO" == "Amazon Linux" ]; then
    chown -R ec2-user:ec2-user /opt/minecraft
else
    chown -R ubuntu:ubuntu /opt/minecraft
fi
chmod -R 755 /opt/minecraft

# Create and configure service with environment-specific memory settings
cat > /etc/systemd/system/minecraft.service <<EOF
[Unit]
Description=Minecraft Java Server (${ENVIRONMENT})
After=network.target

[Service]
Type=simple
User=ec2-user
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
ec2-user soft nofile 65535
ec2-user hard nofile 65535
EOF

sysctl -p

# Start service
systemctl daemon-reload
systemctl enable minecraft
systemctl start minecraft

log_message "INFO" "Installation completed successfully in ${ENVIRONMENT} environment"