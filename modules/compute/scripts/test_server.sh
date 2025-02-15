#!/bin/bash
set -e

# Ensure script runs with correct permissions
if [ "$(id -u)" -eq 0 ]; then
    echo "This script should not be run as root"
    exit 1
fi

# Install required packages if not present
if ! command -v netstat &> /dev/null; then
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y net-tools
fi

# Ensure log directory exists and is writable
sudo mkdir -p /var/log/minecraft
sudo chown -R ubuntu:ubuntu /var/log/minecraft
LOG_FILE="/var/log/minecraft/validation.log"
touch $LOG_FILE

echo "[$(date)] Starting Minecraft server validation tests..." | tee -a $LOG_FILE

# Function to log messages
log_message() {
    echo "[$(date)] $1" | tee -a $LOG_FILE
}

# Function to check server status
check_server_status() {
    log_message "Checking server status..."
    if systemctl is-active minecraft.service >/dev/null 2>&1; then
        log_message "Server is running"
        return 0
    else
        log_message "Server is not running"
        return 1
    fi
}

# Function to check volume mount
check_volume_mount() {
    log_message "Checking volume mount..."
    if mountpoint -q /mnt/minecraft_data; then
        if [ -w "/mnt/minecraft_data" ]; then
            log_message "Volume mounted and writable"
            return 0
        else
            log_message "Volume mounted but not writable"
            return 1
        fi
    else
        log_message "Volume mount failed"
        return 1
    fi
}

# Function to check server logs
check_server_logs() {
    log_message "Checking server logs..."
    # Wait up to 2 minutes for server to start
    for i in {1..24}; do
        if [ -f "/opt/minecraft/bedrock_server" ]; then
            if grep -q "Server started\." /var/log/minecraft/server.log || \
               grep -q "IPv4 supported, port:" /var/log/minecraft/server.log; then
                log_message "Bedrock server started successfully"
                return 0
            fi
        else
            if grep -q "Done ([0-9.]*s)! For help, type \"help\"" /var/log/minecraft/server.log; then
                log_message "Java server started successfully"
                return 0
            fi
        fi
        log_message "Waiting for server start... (attempt $i)"
        sleep 5
    done
    log_message "Server start not detected in logs after 2 minutes"
    return 1
}

# Function to check server process
check_server_process() {
    log_message "Checking server process..."
    
    # Check for bedrock server process first (exact binary name)
    if pgrep -x "bedrock_server" >/dev/null; then
        local SERVER_PID=$(pgrep -x "bedrock_server")
        log_message "Found Bedrock server process (PID: $SERVER_PID)"
        return 0
    fi
    
    # Check for Java server process as fallback
    if pgrep -f "java.*server.jar" >/dev/null; then
        local SERVER_PID=$(pgrep -f "java.*server.jar")
        log_message "Found Java server process (PID: $SERVER_PID)"
        return 0
    fi
    
    log_message "No server process found"
    return 1
}

# Function to test world persistence
test_world_persistence() {
    log_message "Testing world data persistence..."
    local TEST_FILE="/mnt/minecraft_data/worlds/test_file_$(date +%s)"
    local TEST_DATA="test_data_$(date +%s)"
    
    echo "$TEST_DATA" > "$TEST_FILE"
    sync
    
    if [ -f "$TEST_FILE" ]; then
        local READ_DATA=$(cat "$TEST_FILE")
        if [ "$READ_DATA" = "$TEST_DATA" ]; then
            log_message "World data persistence test passed"
            rm "$TEST_FILE"
            return 0
        else
            log_message "World data read verification failed"
            return 1
        fi
    else
        log_message "World data persistence test failed"
        return 1
    fi
}

# Function to test network ports
test_network_ports() {
    log_message "Testing network ports..."
    
    # Get server type from server.jar or bedrock_server presence
    if [ -f "/opt/minecraft/bedrock_server" ]; then
        # Test both UDP and TCP for Bedrock
        for PORT in 19132 19133; do
            # Check UDP
            if ! netstat -lnu | grep -q ":$PORT\s"; then
                log_message "Port $PORT/udp is not listening"
                return 1
            fi
            log_message "Port $PORT/udp is listening"

            # Some features need TCP too, check it
            if ! netstat -lnt | grep -q ":$PORT\s"; then
                log_message "Warning: Port $PORT/tcp is not listening (optional)"
            else
                log_message "Port $PORT/tcp is also listening"
            fi
        done
    else
        # Java server uses TCP
        if ! netstat -lnt | grep -q ":25565\s"; then
            log_message "Port 25565/tcp is not listening"
            return 1
        fi
        log_message "Port 25565/tcp is listening"
    fi
    
    return 0
}

# Function to check permissions
check_permissions() {
    log_message "Checking directory permissions..."
    
    local dirs=("/opt/minecraft" "/mnt/minecraft_data" "/var/log/minecraft")
    for dir in "${dirs[@]}"; do
        if [ ! -w "$dir" ]; then
            log_message "Directory $dir is not writable"
            return 1
        fi
    done
    
    log_message "All directory permissions are correct"
    return 0
}

# Function to check server binary
check_server_binary() {
    log_message "Checking server binary..."
    if [ -f "/opt/minecraft/bedrock_server" ]; then
        if [ -x "/opt/minecraft/bedrock_server" ]; then
            log_message "Bedrock server binary found and executable"
            return 0
        else
            log_message "Bedrock server binary found but not executable"
            return 1
        fi
    elif [ -f "/opt/minecraft/server.jar" ]; then
        if [ -r "/opt/minecraft/server.jar" ]; then
            log_message "Java server JAR found and readable"
            return 0
        else
            log_message "Java server JAR found but not readable"
            return 1
        fi
    else
        log_message "No server binary found"
        return 1
    fi
}

# Run tests and collect results
TESTS_PASSED=0
TESTS_FAILED=0

run_test() {
    local test_name=$1
    local test_func=$2
    
    log_message "Running test: $test_name"
    if $test_func; then
        ((TESTS_PASSED++))
        log_message "✓ $test_name passed"
        return 0
    else
        ((TESTS_FAILED++))
        log_message "✗ $test_name failed"
        return 1
    fi
}

# Run all tests
run_test "Service Status" check_server_status
run_test "Volume Mount" check_volume_mount
run_test "Server Process" check_server_process
run_test "Server Logs" check_server_logs
run_test "Network Ports" test_network_ports
run_test "World Persistence" test_world_persistence
run_test "Directory Permissions" check_permissions
run_test "Server Binary" check_server_binary

# Ensure world directory exists
mkdir -p /mnt/minecraft_data/worlds

# Report results
log_message "Test Summary:"
log_message "Tests passed: $TESTS_PASSED"
log_message "Tests failed: $TESTS_FAILED"

# Enhanced reporting with more details
if [ $TESTS_FAILED -eq 0 ]; then
    log_message "✅ All validation tests passed successfully!"
    # Create success marker file
    touch "/var/log/minecraft/validation_success"
    exit 0
else
    log_message "❌ $TESTS_FAILED test(s) failed. Check $LOG_FILE for details"
    # List failed tests
    grep "✗" "$LOG_FILE"
    exit 1
fi