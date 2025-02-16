#!/bin/bash
set -e

LOG_DIR="/var/log/minecraft"
MAIN_LOG="$LOG_DIR/main_validation.log"
MAX_RETRIES=3

# Ensure log directory exists with proper permissions
sudo mkdir -p "$LOG_DIR"
sudo chown -R ubuntu:ubuntu "$LOG_DIR"
sudo chmod 755 "$LOG_DIR"

log_message() {
    echo "[$(date)] $1" | tee -a "$MAIN_LOG"
}

# Verify required tools and dependencies
check_dependencies() {
    local missing_deps=0
    local required_tools=("aws" "jq" "netstat" "systemctl")
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            log_message "❌ Required tool not found: $tool"
            missing_deps=$((missing_deps + 1))
        fi
    done
    
    return $missing_deps
}

# Verify script locations and permissions
verify_scripts() {
    local script_dir="/opt/minecraft/test"
    local missing_scripts=0
    local required_scripts=("test_server.sh" "test_backup.sh")
    
    for script in "${required_scripts[@]}"; do
        local script_path="$script_dir/$script"
        if [ ! -f "$script_path" ]; then
            log_message "❌ Required script not found: $script"
            missing_scripts=$((missing_scripts + 1))
            continue
        fi
        
        if [ ! -x "$script_path" ]; then
            log_message "❌ Script not executable: $script"
            if ! chmod +x "$script_path"; then
                log_message "Failed to set executable permission on $script"
                missing_scripts=$((missing_scripts + 1))
            fi
        fi
    done
    
    return $missing_scripts
}

# Clean up previous test results
rm -f "$LOG_DIR"/*_validation_success
rm -f "$LOG_DIR"/validation_status.json

log_message "Starting main validation process..."

# Check dependencies first
log_message "Checking dependencies..."
if ! check_dependencies; then
    log_message "❌ Missing required dependencies. Please check the log for details."
    exit 1
fi

# Verify scripts
log_message "Verifying test scripts..."
if ! verify_scripts; then
    log_message "❌ Missing or invalid test scripts. Please check the log for details."
    exit 1
fi

# Test server stop/start functionality
test_server_restart() {
    log_message "Testing server stop/start functionality..."
    
    # Stop server
    sudo systemctl stop minecraft
    sleep 10
    
    if systemctl is-active minecraft >/dev/null 2>&1; then
        log_message "❌ Server failed to stop"
        return 1
    fi
    
    # Start server
    sudo systemctl start minecraft
    
    # Wait for server to start (up to 60 seconds)
    for i in {1..12}; do
        if systemctl is-active minecraft >/dev/null 2>&1; then
            log_message "✓ Server successfully restarted"
            return 0
        fi
        sleep 5
    done
    
    log_message "❌ Server failed to restart"
    return 1
}

# Run comprehensive server tests with improved error handling
run_server_tests() {
    local attempt=$1
    log_message "Running server tests (attempt $attempt/$MAX_RETRIES)..."
    
    # Run test scripts
    TEST_SERVER_SCRIPT="/opt/minecraft/test/test_server.sh"
    if [ ! -x "$TEST_SERVER_SCRIPT" ]; then
        if ! chmod +x "$TEST_SERVER_SCRIPT"; then
            log_message "❌ Failed to set executable permissions on test_server.sh"
            return 1
        fi
    fi
    
    # Verify script exists before running
    if [ ! -f "$TEST_SERVER_SCRIPT" ]; then
        log_message "❌ test_server.sh not found at $TEST_SERVER_SCRIPT"
        return 1
    fi
    
    # Run with error capture
    if ! output=$($TEST_SERVER_SCRIPT 2>&1); then
        log_message "❌ test_server.sh failed with output:"
        log_message "$output"
        if [ $attempt -lt $MAX_RETRIES ]; then
            log_message "Server tests failed, restarting server and retrying..."
            test_server_restart
            sleep 30
            return 1
        else
            log_message "❌ Server tests failed after $MAX_RETRIES attempts"
            return 1
        fi
    fi
    
    log_message "✓ Server tests completed successfully"
    return 0
}

# Run comprehensive backup tests
run_backup_tests() {
    local attempt=$1
    log_message "Running backup tests (attempt $attempt/$MAX_RETRIES)..."
    
    TEST_BACKUP_SCRIPT="/opt/minecraft/test/test_backup.sh"
    if [ ! -x "$TEST_BACKUP_SCRIPT" ]; then
        chmod +x "$TEST_BACKUP_SCRIPT"
    fi
    
    if $TEST_BACKUP_SCRIPT; then
        return 0
    else
        if [ $attempt -lt $MAX_RETRIES ]; then
            log_message "Backup tests failed, retrying..."
            sleep 5
            return 1
        else
            log_message "❌ Backup tests failed after $MAX_RETRIES attempts"
            return 1
        fi
    fi
}

# Main test execution with retries
SERVER_STATUS=1
BACKUP_STATUS=1
PERSISTENCE_STATUS=1

# Test server functionality
for i in $(seq 1 "$MAX_RETRIES"); do
    if run_server_tests "$i"; then
        SERVER_STATUS=0
        break
    fi
done

# Test backup functionality
for i in $(seq 1 "$MAX_RETRIES"); do
    if run_backup_tests "$i"; then
        BACKUP_STATUS=0
        break
    fi
done

# Test world data persistence with improved error handling
log_message "Testing world data persistence..."
TEST_FILE="/mnt/minecraft_data/worlds/persistence_test_$(date +%s).txt"

for i in $(seq 1 "$MAX_RETRIES"); do
    log_message "Persistence test attempt $i/$MAX_RETRIES..."
    
    if ! mountpoint -q /mnt/minecraft_data; then
        log_message "❌ Data volume not mounted, retrying..."
        sleep 5
        continue
    fi
    
    if echo "Test data $(date)" > "${TEST_FILE}" 2>/dev/null; then
        sync
        sleep 2
        if [ -f "${TEST_FILE}" ] && grep -q "Test data" "${TEST_FILE}"; then
            log_message "✓ World data persistence test passed (attempt ${i})"
            PERSISTENCE_STATUS=0
            rm -f "${TEST_FILE}"
            break
        fi
    fi
    
    log_message "Persistence test failed, retrying..."
    sleep 5
done

# Write detailed status with improved error reporting
cat > "$LOG_DIR/validation_status.json" <<EOF
{
    "server_status": $SERVER_STATUS,
    "backup_status": $BACKUP_STATUS,
    "persistence_status": $PERSISTENCE_STATUS,
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "details": {
        "server_log": "$(tail -n 10 /var/log/minecraft/server.log 2>/dev/null || echo 'No server log')",
        "validation_log": "$(tail -n 10 $MAIN_LOG 2>/dev/null || echo 'No validation log')",
        "system_status": {
            "disk_space": "$(df -h /mnt/minecraft_data 2>/dev/null || echo 'Unable to check disk space')",
            "memory_usage": "$(free -h 2>/dev/null || echo 'Unable to check memory')",
            "service_status": "$(systemctl status minecraft.service 2>/dev/null || echo 'Unable to check service')"
        }
    }
}
EOF

# Final results with enhanced reporting
log_message "Final Test Results:"
log_message "Server Tests: $([ $SERVER_STATUS -eq 0 ] && echo '✅ Passed' || echo '❌ Failed')"
log_message "Backup Tests: $([ $BACKUP_STATUS -eq 0 ] && echo '✅ Passed' || echo '❌ Failed')"
log_message "Persistence: $([ $PERSISTENCE_STATUS -eq 0 ] && echo '✅ Passed' || echo '❌ Failed')"

# Overall validation result
if [ $SERVER_STATUS -eq 0 ] && [ $BACKUP_STATUS -eq 0 ] && [ $PERSISTENCE_STATUS -eq 0 ]; then
    log_message "✅ All validation tests completed successfully!"
    touch "$LOG_DIR/full_validation_success"
    exit 0
else
    log_message "❌ Some tests failed. Check logs for details:"
    log_message "Main log: $MAIN_LOG"
    log_message "Server log: /var/log/minecraft/server.log"
    log_message "Status file: $LOG_DIR/validation_status.json"
    
    # Print relevant sections of logs for debugging
    log_message "Recent server log entries:"
    tail -n 20 /var/log/minecraft/server.log 2>/dev/null || echo "No server log available"
    
    log_message "System status:"
    systemctl status minecraft.service
    
    exit 1
fi