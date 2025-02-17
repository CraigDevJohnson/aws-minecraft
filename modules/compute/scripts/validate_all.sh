#!/bin/bash
set -euo pipefail

# Constants
IMDS_ENDPOINT=${1:-"169.254.169.254"}
IMDS_TOKEN_TTL=${2:-"21600"}
LOG_DIR="/var/log/minecraft"
MAIN_LOG="$LOG_DIR/main_validation.log"
SCRIPT_DIR="/opt/minecraft/test"
MAX_RETRIES=3

# Ensure log directory exists with proper permissions
sudo mkdir -p "$LOG_DIR"
sudo chown -R ubuntu:ubuntu "$LOG_DIR"
sudo chmod 755 "$LOG_DIR"

log_message() {
    local level="$1"
    local message="$2"
    echo "[$(date)] [$level] $message" | tee -a "$MAIN_LOG"
}

# Verify script integrity
verify_script_integrity() {
    local script="$1"
    
    if [ ! -f "$script" ]; then
        log_message "ERROR" "Script not found: $script"
        return 1
    fi
    
    if [ ! -x "$script" ]; then
        log_message "WARNING" "Script not executable: $script, attempting to fix"
        chmod +x "$script" || {
            log_message "ERROR" "Failed to make script executable: $script"
            return 1
        }
    fi
    
    # Check for script syntax errors
    bash -n "$script" 2>/dev/null || {
        log_message "ERROR" "Script contains syntax errors: $script"
        return 1
    }
    
    return 0
}

# Verify all required scripts
verify_all_scripts() {
    local failed=0
    local required_scripts=(
        "$SCRIPT_DIR/test_server.sh"
        "$SCRIPT_DIR/test_backup.sh"
    )
    
    for script in "${required_scripts[@]}"; do
        log_message "INFO" "Verifying script: $script"
        if ! verify_script_integrity "$script"; then
            ((failed++))
        fi
    done
    
    return "$failed"
}

# Get IMDSv2 token
get_imds_token() {
    curl -X PUT "http://${IMDS_ENDPOINT}/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: ${IMDS_TOKEN_TTL}" \
        --connect-timeout 1 \
        --retry 3 \
        --silent
}

# Initialize validation environment
initialize_environment() {
    log_message "INFO" "Initializing validation environment"
    
    # Check system dependencies
    local deps=(aws jq curl systemctl)
    local missing=0
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            log_message "ERROR" "Missing required dependency: $dep"
            ((missing++))
        fi
    done
    # Get IMDSv2 token and check metadata service
    local token
    if ! token=$(get_imds_token); then
        log_message "ERROR" "Failed to get IMDSv2 token"
        ((missing++))
    else
        if ! curl -H "X-aws-ec2-metadata-token: $token" \
            -sf --connect-timeout 1 \
            "http://${IMDS_ENDPOINT}/latest/meta-data/" >/dev/null; then
            log_message "ERROR" "Cannot access instance metadata service at ${IMDS_ENDPOINT}"
            ((missing++))
        fi
    fi
    
    # Check filesystem access with better error reporting
    local dirs=("/opt/minecraft" "/mnt/minecraft_data" "$LOG_DIR")
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            log_message "ERROR" "Directory does not exist: $dir"
            ((missing++))
            continue
        fi
        
        if [ ! -w "$dir" ]; then
            # Get more details about the directory
            log_message "ERROR" "Cannot write to directory: $dir"
            log_message "INFO" "Directory permissions: $(ls -ld $dir)"
            log_message "INFO" "Current user: $(whoami)"
            log_message "INFO" "Mount status: $(mount | grep $dir || echo 'not mounted')"
            ((missing++))
        fi
    done
    
    # If /mnt/minecraft_data is not mounted, try to mount it
    if ! mountpoint -q /mnt/minecraft_data; then
        log_message "WARNING" "Minecraft data directory not mounted, attempting to mount..."
        if sudo mount /mnt/minecraft_data; then
            log_message "INFO" "Successfully mounted minecraft data directory"
        else
            log_message "ERROR" "Failed to mount minecraft data directory"
            ((missing++))
        fi
    fi
    
    return "$missing"
}

# Main execution
main() {
    log_message "INFO" "Starting validation suite"
    
    # Initialize environment
    if ! initialize_environment; then
        log_message "ERROR" "Environment initialization failed"
        return 1
    fi
    
    # Verify scripts
    if ! verify_all_scripts; then
        log_message "ERROR" "Script verification failed"
        return 1
    fi
    
    # Run server tests
    log_message "INFO" "Running server tests"
    if ! "$SCRIPT_DIR/test_server.sh"; then
        log_message "ERROR" "Server tests failed"
        return 1
    fi
    
    # Run backup tests
    log_message "INFO" "Running backup tests"
    if ! "$SCRIPT_DIR/test_backup.sh"; then
        log_message "ERROR" "Backup tests failed"
        return 1
    fi
    
    log_message "SUCCESS" "All validation tests completed successfully"
    touch "$LOG_DIR/validation_success"
    return 0
}

# Run main function with error handling
if main; then
    exit 0
else
    log_message "ERROR" "Validation suite failed. Check $MAIN_LOG for details"
    exit 1
fi