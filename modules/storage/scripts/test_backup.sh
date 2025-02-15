#!/bin/bash
set -e

echo "[$(date)] Starting backup validation tests..."

# Configuration
BACKUP_DIR="/mnt/minecraft_data/backups"
WORLDS_DIR="/mnt/minecraft_data/worlds"
TEST_WORLD="test_world_$(date +%s)"
RESTORE_DIR="/mnt/minecraft_data/restore_test"

# Function to check backup vault
check_backup_vault() {
    local VAULT_NAME="$1"
    aws backup describe-backup-vault --backup-vault-name "$VAULT_NAME" || return 1
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

# Function to test local backup creation
test_local_backup_creation() {
    echo "Creating test world directory..."
    mkdir -p "$WORLDS_DIR/$TEST_WORLD"
    echo "test data" > "$WORLDS_DIR/$TEST_WORLD/test_file"
    
    echo "Running backup script..."
    /opt/minecraft/backup.sh
    
    # Verify backup file exists
    local LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/world_backup_*.tar.gz | head -n1)
    if [ -f "$LATEST_BACKUP" ]; then
        echo "Local backup created successfully: $LATEST_BACKUP"
        return 0
    else
        echo "Local backup creation failed"
        return 1
    fi
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

# Main test execution
echo "Running comprehensive backup validation tests..."

# Run AWS Backup configuration tests if parameters provided
if [ "$#" -eq 4 ]; then
    VAULT_NAME="$1"
    PLAN_ID="$2"
    SELECTION_ID="$3"
    RESOURCE_ARN="$4"
    
    echo "1. Testing AWS Backup configuration..."
    check_backup_vault "$VAULT_NAME"
    check_backup_plan "$PLAN_ID"
    check_backup_selection "$PLAN_ID" "$SELECTION_ID"
fi

echo "2. Testing local backup functionality..."
test_local_backup_creation

echo "3. Testing backup restoration..."
test_backup_restoration

echo "4. Testing backup versioning..."
test_backup_versioning

echo "5. Testing AWS Backup integration..."
test_aws_backup

# Cleanup
rm -rf "$WORLDS_DIR/$TEST_WORLD"
rm -rf "$RESTORE_DIR"

echo "[$(date)] Backup validation tests completed"