#!/bin/bash
set -euo pipefail

echo "[$(date)] Starting backup validation tests..."

# Configuration
BACKUP_DIR="/mnt/minecraft_data/backups"
WORLDS_DIR="/mnt/minecraft_data/worlds"
TEST_WORLD="test_world_$(date +%s)"
RESTORE_DIR="/mnt/minecraft_data/restore_test"
MAX_RETRIES=3

# Ensure AWS credentials are available
check_aws_credentials() {
    local retry_count=0
    local token=""
    
    while [ $retry_count -lt $MAX_RETRIES ]; do
        token=$(curl -X PUT "http://169.254.169.254/latest/api/token" \
            -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" \
            --connect-timeout 5 \
            --retry 3 \
            --silent)
            
        if [ -n "$token" ]; then
            # Get and configure region
            local region=$(curl -H "X-aws-ec2-metadata-token: $token" \
                -s http://169.254.169.254/latest/meta-data/placement/region)
            if [ -n "$region" ]; then
                aws configure set region "$region"
                return 0
            fi
        fi
        
        echo "Waiting for AWS credentials... (attempt $((retry_count + 1)))"
        sleep 5
        ((retry_count++))
    done
    
    return 1
}

# Function to check backup vault
check_backup_vault() {
    local VAULT_NAME="$1"
    local retry_count=0
    
    while [ $retry_count -lt $MAX_RETRIES ]; do
        if aws backup describe-backup-vault --backup-vault-name "$VAULT_NAME" >/dev/null 2>&1; then
            return 0
        fi
        echo "Waiting for backup vault... (attempt $((retry_count + 1)))"
        sleep 5
        ((retry_count++))
    done
    return 1
}

# Function to check backup plan
check_backup_plan() {
    local PLAN_ID="$1"
    aws backup get-backup-plan --backup-plan-id "$PLAN_ID" || return 1
}

# Function to validate backup selection
check_backup_selection() {
    local PLAN_ID="$1"
    local SELECTION_ID="$2"
    aws backup get-backup-selection --backup-plan-id "$PLAN_ID" --selection-id "$SELECTION_ID" || return 1
}

# Enhanced local backup testing with retries
test_local_backup_creation() {
    echo "Creating test world directory..."
    mkdir -p "$WORLDS_DIR/$TEST_WORLD"
    echo "test data" > "$WORLDS_DIR/$TEST_WORLD/test_file"
    sync
    
    echo "Running backup script..."
    local retry_count=0
    while [ $retry_count -lt $MAX_RETRIES ]; do
        if /opt/minecraft/backup.sh; then
            # Verify backup file exists
            local LATEST_BACKUP
            LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/world_backup_*.tar.gz 2>/dev/null | head -n1) || true
            
            if [ -f "$LATEST_BACKUP" ]; then
                echo "Local backup created successfully: $LATEST_BACKUP"
                return 0
            fi
        fi
        echo "Backup attempt $((retry_count + 1)) failed, retrying..."
        sleep 5
        ((retry_count++))
    done
    
    echo "Local backup creation failed after $MAX_RETRIES attempts"
    return 1
}

# Function to test backup restoration
test_backup_restoration() {
    local LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/world_backup_*.tar.gz | head -n1)
    
    echo "Testing backup restoration..."
    mkdir -p "$RESTORE_DIR"
    tar -xzf "$LATEST_BACKUP" -C "$RESTORE_DIR"
    
    if [ -f "$RESTORE_DIR/$TEST_WORLD/test_file" ]; then
        echo "Backup restoration test passed"
        return 0
    else
        echo "Backup restoration test failed"
        return 1
    fi
}

# Function to test AWS Backup integration
test_aws_backup() {
    echo "Checking AWS Backup IAM role..."
    aws iam get-role --role-name AWSBackupDefaultServiceRole >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "AWS Backup role exists"
    else
        echo "AWS Backup role not found"
        return 1
    fi
    
    # List recent backups
    aws backup list-recovery-points-by-backup-vault \
        --backup-vault-name minecraft-backup-vault \
        --by-created-after "$(date -d '24 hours ago' --iso-8601=seconds)" \
        >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo "AWS Backup vault accessible"
        return 0
    else
        echo "AWS Backup vault access failed"
        return 1
    fi
}

# Function to test backup versioning
test_backup_versioning() {
    echo "Testing backup versioning..."
    # Create multiple backups
    for i in {1..3}; do
        echo "Creating test backup $i..."
        echo "test data $i" > "$WORLDS_DIR/$TEST_WORLD/test_file_$i"
        /opt/minecraft/backup.sh
        sleep 2
    done
    
    # Check if we have the correct number of backups (should keep last 5)
    local BACKUP_COUNT=$(ls "$BACKUP_DIR"/world_backup_*.tar.gz | wc -l)
    if [ "$BACKUP_COUNT" -le 5 ]; then
        echo "Backup versioning test passed (found $BACKUP_COUNT backups)"
        return 0
    else
        echo "Backup versioning test failed (found $BACKUP_COUNT backups, expected <= 5)"
        return 1
    fi
}

# Main test execution with improved error handling
main() {
    # Ensure required directories exist
    mkdir -p "$BACKUP_DIR" "$WORLDS_DIR" "$RESTORE_DIR"
    
    # Check AWS credentials first
    echo "Checking AWS credentials..."
    if ! check_aws_credentials; then
        echo "Failed to obtain AWS credentials"
        return 1
    fi
    
    echo "Testing local backup functionality..."
    if ! test_local_backup_creation; then
        echo "Local backup testing failed"
        return 1
    fi
    
    echo "Testing AWS Backup integration..."
    if ! check_backup_vault "minecraft-backup-vault"; then
        echo "AWS Backup vault check failed"
        return 1
    fi
    
    # Clean up test data
    rm -rf "$WORLDS_DIR/$TEST_WORLD" "$RESTORE_DIR"
    
    echo "[$(date)] Backup validation tests completed successfully"
    return 0
}

# Execute main with error handling
if main; then
    exit 0
else
    echo "[$(date)] Backup validation failed"
    exit 1
fi