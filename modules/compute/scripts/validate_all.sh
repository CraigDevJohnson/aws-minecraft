#!/bin/bash
set -euo pipefail

# Constants
IMDS_ENDPOINT=${1:-"169.254.169.254"}
IMDS_TOKEN_TTL=${2:-"21600"}
LOG_DIR="/var/log/minecraft"
MAIN_LOG="$LOG_DIR/main_validation.log"
SCRIPT_DIR="/opt/minecraft/test"
MAX_RETRIES=3

# Enable debug output
DEBUG=true

# Ensure log directory exists with proper permissions
sudo mkdir -p "$LOG_DIR"
sudo chown -R ubuntu:ubuntu "$LOG_DIR"
sudo chmod 755 "$LOG_DIR"

log_message() {
    local level="$1"
    local message="$2"
    echo "[$(date)] [$level] $message" | tee -a "$MAIN_LOG"
}

debug_message() {
    if [ "$DEBUG" = true ]; then
        log_message "DEBUG" "$1"
    fi
}

# Get IMDSv2 token
get_imds_token() {
    local token
    token=$(curl -X PUT "http://${IMDS_ENDPOINT}/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: ${IMDS_TOKEN_TTL}" \
        --retry 3 --retry-delay 1 --silent --fail)
    
    if [ $? -eq 0 ] && [ -n "$token" ]; then
        return 0
    else
        return 1
    fi
}

# Initialize environment
initialize_environment() {
    local missing=0
    
    # Check required commands
    local cmds=("curl" "jq" "aws")
    for cmd in "${cmds[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_message "ERROR" "Required command not found: $cmd"
            ((missing++))
        fi
    done

    # Check required directories and permissions
    local dirs=("/opt/minecraft" "/mnt/minecraft_data" "$LOG_DIR")
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            log_message "ERROR" "Directory does not exist: $dir"
            ((missing++))
            continue
        fi
        
        if [ ! -w "$dir" ]; then
            log_message "ERROR" "Cannot write to directory: $dir"
            log_message "INFO" "Directory permissions: $(ls -ld $dir)"
            log_message "INFO" "Current user: $(whoami)"
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

# Verify script integrity
verify_script_integrity() {
    local script="$1"
    
    debug_message "Verifying script: $script"
    
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
    if ! bash -n "$script" 2>/dev/null; then
        log_message "ERROR" "Script contains syntax errors: $script"
        return 1
    fi
    
    debug_message "Script verification successful: $script"
    return 0
}

# Verify all required scripts with detailed logging
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
            log_message "ERROR" "Script verification failed for: $script"
            # Show script contents for debugging if it exists
            if [ -f "$script" ]; then
                debug_message "Script contents of $script:"
                debug_message "$(cat "$script")"
            fi
        else
            debug_message "Script verification passed for: $script"
        fi
    done
    
    return "$failed"
}

# Main execution
main() {
    log_message "INFO" "Starting validation suite"
    
    # Initialize environment
    log_message "INFO" "Initializing environment..."
    if ! initialize_environment; then
        log_message "ERROR" "Environment initialization failed"
        return 1
    fi
    
    # Verify scripts
    log_message "INFO" "Verifying scripts..."
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
    # Pass through the environment variable if it exists
    export MINECRAFT_ENVIRONMENT="${MINECRAFT_ENVIRONMENT:-dev}"
    if ! "$SCRIPT_DIR/test_backup.sh"; then
        log_message "ERROR" "Backup tests failed"
        return 1
    fi
    
    log_message "SUCCESS" "All validation tests completed successfully"
    return 0
}

# Run main function with error handling
if main; then
    exit 0
else
    log_message "ERROR" "Validation suite failed. Check $MAIN_LOG for details"
    exit 1
fi