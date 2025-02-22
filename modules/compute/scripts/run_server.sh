#!/bin/bash

SERVER_LOG=/var/log/minecraft/server.log
log_message() {
  local level="$1"
  local message="$2"
  echo "[$(date)] [$level] $message" | tee -a "$SERVER_LOG"
}

debug_message() {
  if [ "$DEBUG" = true ]; then
    log_message "DEBUG" "$1"
  fi
}

# Change to the Minecraft server directory
cd /opt/minecraft

# Wait for network to be available
log_message "INFO" "Checking if network available..."
while ! ping -c 1 -W 1 8.8.8.8; do
  log_message "INFO" "Waiting for network..."
  sleep 1
done
log_message "INFO" "Network is available"

# Wait for data volume to be available
log_message "INFO" "Checking if data volume available..."
while ! mountpoint -q /mnt/minecraft_data; do
  log_message "INFO" "Waiting for data volume..."
  sleep 1
done
log_message "INFO" "Data volume is available"

# Start the Minecraft server
log_message "INFO" "Starting Minecraft server..."
if [ -f "bedrock_server" ]; then
  log_message "INFO" "Starting Bedrock server..."
  ./bedrock_server
  log_message "INFO" "Bedrock Minecraft server started"
  exit 0
elif [ -f "server.jar" ]; then
  log_message "INFO" "Starting Java server..."
  exec java -Xms512M -Xmx1024M -XX:+UseG1GC -jar server.jar nogui
  log_message "INFO" "Java Minecraft server started"
  exit 0
fi
exit 1

