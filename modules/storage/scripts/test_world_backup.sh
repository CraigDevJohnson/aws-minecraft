#!/bin/bash
set -euo pipefail

# Configuration
BACKUP_DIR="/mnt/minecraft_data/backups"
WORLDS_DIR="/mnt/minecraft_data/worlds"
TEST_WORLD="test_world_$(date +%s)"
RESTORE_DIR="/mnt/minecraft_data/restore_test"
MAX_RETRIES=3
LOG_DIR="/var/log/minecraft"
BACKUP_TEST_LOG="$LOG_DIR/test_world_backup.log"
IMDS_ENDPOINT=${1:-"169.254.169.254"}
IMDS_TOKEN_TTL=${2:-"21600"}
DEBUG=true
# Ensure log directory exists with proper permissions
if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
    echo "[$(date)] [WARNING] Could not create log directory. Logging to /tmp/test_world_backup.log"
    LOG_DIR="/tmp"
    BACKUP_TEST_LOG="$LOG_DIR/test_world_backup.log"
fi

if ! touch "$BACKUP_TEST_LOG" 2>/dev/null; then
    echo "[$(date)] [WARNING] Could not create log file. Logging to stdout only"
    BACKUP_TEST_LOG="/dev/stdout"
fi

if [ "$BACKUP_TEST_LOG" != "/dev/stdout" ]; then
    chmod 755 "$LOG_DIR" 2>/dev/null || true
    chmod 644 "$BACKUP_TEST_LOG" 2>/dev/null || true
fi

log_message() {
    local level="$1"
    local message="$2"
    echo "[$(date)] [$level] $message" | tee -a "$BACKUP_TEST_LOG"
}

debug_message() {
    if [ "$DEBUG" = true ]; then
        log_message "DEBUG" "$1"
    fi
}

log_message "INFO" "Starting world backup validation tests..."
# Environment configuration with fallbacks
log_message "INFO" "Checking environment configuration..."
ENVIRONMENT="${MINECRAFT_ENVIRONMENT:-dev}"
debug_message "Initial environment value: $ENVIRONMENT"

# Function to validate environment
validate_environment() {
    local env="$1"
    case "$env" in
        dev|prod) return 0 ;;
        *)
            log_message "ERROR" "Invalid environment '$env'. Must be one of: dev, prod"
            return 1
            ;;
    esac
}

# Validate environment before proceeding
if validate_environment "$ENVIRONMENT"; then
    debug_message "Using initial environment: $ENVIRONMENT"
    VAULT_NAME="minecraft-${ENVIRONMENT}-backup-vault"
    BACKUP_ROLE_NAME="minecraft-${ENVIRONMENT}-backup-role"
    PLAN_NAME="minecraft-${ENVIRONMENT}-backup-plan"
    SELECTION_NAME="minecraft-${ENVIRONMENT}-backup-selection"
else
    debug_message "Defaulting to 'dev' environment"
    ENVIRONMENT="dev"
    VAULT_NAME="minecraft-dev-backup-vault"
    BACKUP_ROLE_NAME="minecraft-dev-backup-role"
    PLAN_NAME="minecraft-dev-backup-plan"
    SELECTION_NAME="minecraft-dev-backup-selection"
fi

log_message "INFO" "Running backup validation for environment: $ENVIRONMENT"
log_message "INFO" "Using backup vault: $VAULT_NAME"
log_message "INFO" "Using backup role: $BACKUP_ROLE_NAME"
log_message "INFO" "Using backup plan: $PLAN_NAME"
log_message "INFO" "Using backup selection: $SELECTION_NAME"

# function to check AWS credentials are available
check_aws_credentials() {
    local retry_count=0
    while [ $retry_count -lt $MAX_RETRIES ]; do
        # Get IMDSv2 token for metadata access
        local token=$(curl -X PUT "http://$IMDS_ENDPOINT/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: $IMDS_TOKEN_TTL" --retry 3 --retry-delay 1 --silent --fail)
        if [ -n "$token" ]; then
            log_message "INFO" "IMDSv2 token acquired successfully"
            debug_message "IMDSv2 token: $token"
            # Get region from instance metadata
            local region=$(curl -H "X-aws-ec2-metadata-token: $token" "http://$IMDS_ENDPOINT/latest/meta-data/placement/region")
            if [ -n "$region" ]; then
                log_message "INFO" "Instance region acquired successfully"
                debug_message "Instance region: $region"
                aws configure set region "$region"
                log_message "INFO" "AWS credentials available and region set"
                return 0
            else
                log_message "WARNING" "Failed to get instance region, will retry..."
            fi
        else
            log_message "WARNING" "Failed to acquire IMDSv2 token, will retry..."
        fi
        log_message "WARNING" "Waiting for AWS credentials... (attempt $((retry_count + 1)))"
        sleep 5
        ((retry_count++))
    done
    log_message "ERROR" "Failed to acquire AWS credentials after $MAX_RETRIES attempts"
    return 1
}

# Function to check backup vault
check_backup_vault() {
    local retry_count=0
    
    while [ $retry_count -lt $MAX_RETRIES ]; do
        log_message "INFO" "Checking AWS Backup vault configuration..."
        
        # First verify AWS CLI can make requests
        local caller_identity=$(aws sts get-caller-identity)
        if [ $? -ne 0 ]; then
            log_message "WARNING" "Unable to validate AWS credentials"
            sleep 5
            ((retry_count++))
            continue
        fi
        log_message "INFO" "AWS credentials validated"
        debug_message "Caller identity details: $caller_identity"

        local vault_info=$(aws backup describe-backup-vault --backup-vault-name "$VAULT_NAME")
        
        # Check if vault exists
        if [ -n "$vault_info" ]; then
            log_message "INFO" "✓ Backup vault '$VAULT_NAME' found"
            debug_message "Backup vault details: $vault_info"
            
            # Verify permissions by trying to list recovery points
            local recovery_points=$(aws backup list-recovery-points-by-backup-vault --backup-vault-name "$VAULT_NAME")
            if [ $? -ne 0 ]; then
                local recovery_points_json=$(echo $recovery_points | jq .RecoveryPoints)
                log_message "INFO" "✓ Backup vault permissions verified"
                debug_message "Recovery points in vault (will be null if initial deployment): $recovery_points_json"
                return 0
            else
                log_message "ERROR" "Unable to list recovery points in vault"
            fi
        else
            log_message "ERROR" "Backup vault '$VAULT_NAME' not found"
            log_message "ERROR" "Available backup vaults: $(aws backup list-backup-vaults --max-results 20 | jq .BackupVaultList)"
        fi
        
        log_message "WARNING" "Waiting for backup vault... (attempt $((retry_count + 1)))"
        sleep 5
        ((retry_count++))
    done
    
    log_message "ERROR" "Failed to verify backup vault after $MAX_RETRIES attempts"
    return 1
}

# Function to check backup plan
check_backup_plan() {
    log_message "INFO" "Checking backup plan configuration..."
    # Query the backup plan ID using the plan name
    local plan_id=$(aws backup list-backup-plans --query "BackupPlansList[?BackupPlanName=='$PLAN_NAME'].BackupPlanId" --output text)
    if [ -n "$plan_id" ]; then
        PLAN_ID="$plan_id"
        log_message "INFO" "✓ Found backup plan ID"
        debug_message "Backup Plan ID: $PLAN_ID"
        local plan_rules=$(aws backup get-backup-plan --backup-plan-id "$PLAN_ID" --output json)
        if [ $? -ne 0 ]; then
            local plan_rules_json=$(echo $plan_rules | jq .BackupPlan.Rules)
            log_message "INFO" "✓ Backup plan rules"
            debug_message "$plan_rules_json"
            return 0
        else
            log_message "ERROR" "No backup plan rules found"
        fi
    else
        log_message "ERROR" "Backup plan '$PLAN_NAME' not found"
        # List available backup plans for debugging
        log_message "ERROR" "Available backup plans: $(aws backup list-backup-plans --max-results 20 | jq .BackupPlansList)"
        return 1
    fi
}

# Function to validate backup selection
check_backup_selection() {
    # Query the backup selection ID using the plan ID and selection name
    local selection_id=$(aws backup list-backup-selections --backup-plan-id $PLAN_ID --query "BackupSelectionsList[?SelectionName=='$SELECTION_NAME'].SelectionId" --output text)
    if [ -n "$selection_id" ]; then
        log_message "INFO" "✓ Found backup selection ID"
        debug_message "Backup Selection ID: $selection_id"
        local backup_selections=$(aws backup get-backup-selection --backup-plan-id $PLAN_ID --selection-id $selection_id --output json)
        if [ $? -ne 0 ]; then
            local backup_selections_json=$(echo $backup_selections | jq .BackupSelection)
            log_message "INFO" "✓ Backup selection details:"
            debug_message "$backup_selections_json"
            return 0
        else
            log_message "ERROR" "No backup selection details found"
            return 1
        fi
    else 
        log_message "ERROR" "Backup selection '$SELECTION_NAME' not found"
        # List available backup selections for debugging
        log_message "ERROR"  "Available backup selections: $(aws backup list-backup-selections --backup-plan-id $PLAN_ID --max-results 20 | jq .BackupSelectionsList)"
        return 1
    fi
}

# Function to check if server is ready to perform tests
check_server_readiness() {
    local max_attempts=30
    local attempt=1
    local wait_time=10
    local test_server_script="/opt/minecraft/test_server.sh"
    
    # Check for AWS Credentials
    log_message "INFO" "Checking AWS credentials..."
    if ! check_aws_credentials; then
        log_message "ERROR" "Failed AWS credentials check"
        return 1
    fi
    
    # Check for AWS Backup Vault
    log_message "INFO"  "Checking AWS Backup Vault..."
    if ! check_backup_vault; then
        log_message "ERROR" "Failed AWS Backup Vault check"
        return 1
    fi
    
    # Check for Backup Plan
    log_message "INFO"  "Checking Backup Plan..."
    if ! check_backup_plan; then
        log_message "ERROR" "Failed Backup Plan check"
        return 1
    fi

    # Check for Backup Selection
    log_message "INFO"  "Checking Backup Selection..."
    if ! check_backup_selection; then
        log_message "ERROR" "Failed Backup Selection check"
        return 1
    fi

    log_message "INFO" "Server readiness check passed, proceeding with backup tests..."
    return 0
}

# Enhanced local backup testing with retries
test_local_backup_creation() {
    log_message "INFO" "Creating test world directory..."
    mkdir -p "$WORLDS_DIR/$TEST_WORLD"
    echo "test data" > "$WORLDS_DIR/$TEST_WORLD/test_file"
    sync
    
    log_message "INFO" "Running backup script..."
    local retry_count=0
    while [ $retry_count -lt $MAX_RETRIES ]; do
        if /opt/minecraft/backup.sh; then
            # Verify backup file exists
            local latest_backup
            latest_backup=$(ls -t "$BACKUP_DIR"/world_backup_*.tar.gz 2>/dev/null | head -n1) || true
            
            if [ -f "$latest_backup" ]; then
                log_message "INFO" "Local backup created successfully: $latest_backup"
                return 0
            fi
        fi
        log_message "WARNING" "Backup attempt $((retry_count + 1)) failed, retrying..."
        sleep 5
        ((retry_count++))
    done
    
    log_message "INFO" "Local backup creation failed after $MAX_RETRIES attempts"
    return 1
}

# Function to test backup restoration
test_backup_restoration() {
    local latest_backup=$(ls -t "$BACKUP_DIR"/world_backup_*.tar.gz | head -n1)
    
    log_message "INFO" "Testing backup restoration..."
    mkdir -p "$RESTORE_DIR"
    tar -xzf "$latest_backup" -C "$RESTORE_DIR"
    
    if [ -f "$RESTORE_DIR/$TEST_WORLD/test_file" ]; then
        log_message "INFO" "Backup restoration test passed"
        return 0
    else
        log_message "ERROR" "Backup restoration test failed"
        return 1
    fi
}

# Function to test AWS Backup integration
test_aws_backup() {
    log_message "INFO" "Checking AWS Backup IAM role..."
    local backup_iam_role=$(aws iam get-role --role-name "$BACKUP_ROLE_NAME")
    if [ $? -ne 0 ]; then
        backup_iam_role_json=$(echo $backup_iam_role | jq .Role)
        log_message "INFO" "AWS Backup role exists"
        debug_message "$backup_iam_role_json"
    else
        log_message "ERROR" "AWS Backup role not found"
        return 1
    fi
    
    # List recent backups
    log_message "INFO" "Checking if AWS Backup vault is accessible..."
    backup_recovery_points=$(aws backup list-recovery-points-by-backup-vault --backup-vault-name "$VAULT_NAME" --by-created-after "$(date -d '24 hours ago' --iso-8601=seconds)")
    if [ $? -eq 0 ]; then
        log_message "INFO" "AWS Backup vault accessible"
        ##### NEED TO UPDATE IF LOGIC AS IT IS NOT A STRING #####
        if [ -n "$backup_recovery_points" ]; then
            log_message "INFO" "Checking recent recovery points..."
            backup_recovery_points_json=$(echo $backup_recovery_points | jq .RecoveryPoints)
            log_message "INFO" "Found recent recovery points"
            debug_message "$backup_recovery_points_json"
        else
            log_message "WARNING" "No recent recovery points found"
        fi
        return 0
    else
        log_message "ERROR" "AWS Backup vault access failed"
        return 1
    fi
}

# Function to test backup versioning
test_backup_versioning() {
    log_message "INFO" "Testing backup versioning..."
    # Create multiple backups
    for i in {1..5}; do
        log_message "INFO" "Creating test backup $i..."
        log_message "INFO" "test data $i" > "$WORLDS_DIR/$TEST_WORLD/test_file_$i"
        /opt/minecraft/world_backup.sh
        sleep 2
    done
    
    # Check if we have the correct number of backups (should keep last 5)
    local backup_count=$(ls "$BACKUP_DIR"/world_backup_*.tar.gz | wc -l)
    if [ "$backup_count" -le 5 ]; then
        log_message "INFO" "Backup versioning test passed (found $backup_count backups)"
        return 0
    else
        log_message "ERROR" "Backup versioning test failed (found $backup_count backups, expected <= 5)"
        return 1
    fi
}



# Main function to orchestrate all tests
main() {
    log_message "INFO" "[$(date)] Starting backup validation..."
    
    log_message "INFO" "Checking server backup readiness..."
    if ! check_server_readiness; then
        log_message "ERROR" "Server readiness check failed"
        return 1
    fi
    
    log_message "INFO" "Testing local backup functionality..."
    if ! test_local_backup_creation; then
        log_message "ERROR" "Local backup testing failed"
        return 1
    fi
    
    log_message "INFO" "Testing backup restoration..."
    if ! test_backup_restoration; then
        log_message "ERROR" "Backup restoration test failed"
        return 1
    fi
    
    log_message "INFO" "Testing AWS Backup integration..."
    if ! test_aws_backup; then
        log_message "ERROR" "AWS Backup integration test failed"
        return 1
    fi
    
    log_message "INFO" "Testing backup versioning..."
    if ! test_backup_versioning; then
        log_message "ERROR" "Backup versioning test failed"
        return 1
    fi
    
    # Clean up test data
    rm -rf "$WORLDS_DIR/$TEST_WORLD" "$RESTORE_DIR"
    log_message "INFO" "Cleaned up test data"

    log_message "INFO" "All world backup validation tests passed"
    return 0
}

# Execute main with error handling
if main; then
    log_message "INFO" "World backup validation completed successfully"
    exit 0
else
    log_message "ERROR" "World backup validation failed"
    exit 1
fi