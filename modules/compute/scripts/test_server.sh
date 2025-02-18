#!/bin/bash
set -e

# Ensure script runs with correct permissions
if [ "$(id -u)" -eq 0 ]; then
    echo "This script should not be run as root"
    exit 1
fi

# Install required packages if not present
if ! command -v ss &> /dev/null; then
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y iproute2
fi

# Ensure log directory exists and is writable
sudo mkdir -p /var/log/minecraft
sudo chown -R ubuntu:ubuntu /var/log/minecraft
LOG_FILE="/var/log/minecraft/validation.log"
touch $LOG_FILE

# Enable debug mode for troubleshooting
DEBUG=true

log_message() {
    local level=$1
    local message=$2
    echo "[$(date)] [$level] $message" | tee -a $LOG_FILE
}

debug_message() {
    if [ "$DEBUG" = true ]; then
        log_message "DEBUG" "$1"
    fi
}

# Function to check server status
check_server_status() {
    log_message "INFO" "Checking server status..."
    if systemctl is-active minecraft.service >/dev/null 2>&1; then
        log_message "INFO" "Server is running"
        return 0
    else
        log_message "ERROR" "Server is not running"
        return 1
    fi
}

# Function to check server process
check_server_process() {
    log_message "INFO" "Checking server process..."
    if pgrep -x "bedrock_server" >/dev/null; then
        log_message "INFO" "Server process is running"
        return 0
    else
        log_message "ERROR" "Server process not found"
        return 1
    fi
}

# Function to check logs
check_server_logs() {
    log_message "INFO" "Checking server logs..."
    if grep -q "Server started." /var/log/minecraft/server.log; then
        log_message "INFO" "Server startup confirmed in logs"
        return 0
    else
        log_message "ERROR" "Server startup not found in logs"
        return 1
    fi
}

# Function to check network ports
check_network_ports() {
    log_message "INFO" "Checking network ports..."
    
    # Check for UDP ports (UNCONN state)
    if ss -uln | grep -q 19132; then
        log_message "INFO" "Port 19132 (UDP/IPv4) is listening"
        if ss -uln | grep -q 19133; then
            log_message "INFO" "Port 19133 (UDP/IPv6) is listening"
            return 0
        fi
    fi
    
    # Debug output to help diagnose issues
    log_message "DEBUG" "Current UDP ports:"
    ss -uln | tee -a $LOG_FILE
    
    log_message "ERROR" "Required ports not listening (need 19132 UDP/IPv4 and 19133 UDP/IPv6)"
    return 1
}

# Modified run_test function
run_test() {
    local test_name=$1
    local test_function=$2
    
    debug_message "Starting test: $test_name using function: $test_function"
    log_message "INFO" "Running test: $test_name"
    
    # Call the function and capture its output and return value
    local output
    local ret_val
    
    output=$($test_function 2>&1)
    ret_val=$?
    
    debug_message "Test output: $output"
    debug_message "Return value: $ret_val"
    
    if [ $ret_val -eq 0 ]; then
        ((TESTS_PASSED++))
        log_message "INFO" "✓ $test_name passed"
        return 0
    else
        ((TESTS_FAILED++))
        log_message "ERROR" "✗ $test_name failed"
        log_message "ERROR" "Failure details: $output"
        return 1
    fi
}

# Main test execution
log_message "INFO" "Starting Minecraft server validation tests..."

TESTS_PASSED=0
TESTS_FAILED=0

debug_message "Running all tests sequentially"

# Run each test individually with proper error handling
run_test "Service Status" check_server_status || true
run_test "Process Check" check_server_process || true
run_test "Log Check" check_server_logs || true
run_test "Network Ports" check_network_ports || true

# Report results
log_message "INFO" "Test Summary:"
log_message "INFO" "Tests passed: $TESTS_PASSED"
log_message "INFO" "Tests failed: $TESTS_FAILED"

if [ $TESTS_FAILED -eq 0 ]; then
    log_message "INFO" "✅ All validation tests passed successfully!"
    exit 0
else
    log_message "ERROR" "❌ Some tests failed. Check the logs for details."
    exit 1
fi