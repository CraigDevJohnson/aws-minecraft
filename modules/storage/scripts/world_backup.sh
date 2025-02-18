#!/bin/bash
set -e

BACKUP_DIR="/mnt/minecraft_data/worlds_backups"
WORLDS_DIR="/mnt/minecraft_data/worlds"
WORLD_BACKUP_LOG="/var/log/minecraft/world_backup.log"
DATE=$(date +%Y%m%d%H%M%S)

log_message() {
    local level="$1"
    local message="$2"
    echo "[$(date)] [$level] $message" | tee -a "$WORLD_BACKUP_LOG"
}

debug_message() {
    if [ "$DEBUG" = true ]; then
        log_message "DEBUG" "$1"
    fi
}
log_message "INFO" "Starting backup process..."

log_message "INFO" "Checking if backup directory already exists..."
if [ ! -d "$BACKUP_DIR" ]; then
    if ! mkdir -p "$BACKUP_DIR"; then
        log_message "ERROR" "Failed to create backup directory"
        exit 1
    fi
    log_message "INFO" "Backup directory created successfully"
    debug_message "Backup directory: $BACKUP_DIR"
else
    log_message "INFO" "Backup directory already exists"
    debug_message "Backup directory: $BACKUP_DIR"
fi


if ! tar -czf "$BACKUP_DIR/world_backup_$DATE.tar.gz" -C "$WORLDS_DIR" .; then
    log_message "ERROR" "Backup failed"
    exit 1
fi

ls -t "$BACKUP_DIR"/world_backup_*.tar.gz | tail -n +6 | xargs -r rm

log_message "INFO" "Backup completed successfully"
debug_message "Backup file: $BACKUP_DIR/world_backup_$DATE.tar.gz"
exit 0