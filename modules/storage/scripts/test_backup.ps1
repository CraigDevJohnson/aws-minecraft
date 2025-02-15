# AWS Backup Testing Script for Windows
# Requires AWS CLI to be installed and configured

# Configuration
$BackupDir = "/mnt/minecraft_data/backups"
$WorldsDir = "/mnt/minecraft_data/worlds"
$TestWorld = "test_world_$(Get-Date -Format 'yyyyMMddHHmmss')"
$RestoreDir = "/mnt/minecraft_data/restore_test"

# Function to check backup vault
function Test-BackupVault {
    param($VaultName)
    try {
        Write-Host "Checking backup vault '$VaultName'..."
        aws backup describe-backup-vault --backup-vault-name $VaultName
        return $true
    } catch {
        Write-Error "Failed to validate backup vault: $_"
        return $false
    }
}

# Function to check backup plan
function Test-BackupPlan {
    param($PlanId)
    try {
        Write-Host "Checking backup plan '$PlanId'..."
        aws backup get-backup-plan --backup-plan-id $PlanId
        return $true
    } catch {
        Write-Error "Failed to validate backup plan: $_"
        return $false
    }
}

# Function to validate backup selection
function Test-BackupSelection {
    param($PlanId, $SelectionId)
    try {
        Write-Host "Checking backup selection..."
        aws backup get-backup-selection --backup-plan-id $PlanId --selection-id $SelectionId
        return $true
    } catch {
        Write-Error "Failed to validate backup selection: $_"
        return $false
    }
}

# Function to test local backup creation
function Test-LocalBackupCreation {
    try {
        Write-Host "Creating test world directory..."
        New-Item -Path "$WorldsDir/$TestWorld" -ItemType Directory -Force
        "test data" | Set-Content "$WorldsDir/$TestWorld/test_file"
        
        Write-Host "Running backup script..."
        & /opt/minecraft/backup.sh
        
        # Verify backup file exists
        $latestBackup = Get-ChildItem "$BackupDir/world_backup_*.tar.gz" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latestBackup) {
            Write-Host "Local backup created successfully: $($latestBackup.Name)"
            return $true
        } else {
            Write-Error "Local backup creation failed"
            return $false
        }
    } catch {
        Write-Error "Failed to create local backup: $_"
        return $false
    }
}

# Function to test backup restoration
function Test-BackupRestoration {
    try {
        $latestBackup = Get-ChildItem "$BackupDir/world_backup_*.tar.gz" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        
        Write-Host "Testing backup restoration..."
        New-Item -Path $RestoreDir -ItemType Directory -Force
        tar -xzf $latestBackup.FullName -C $RestoreDir
        
        if (Test-Path "$RestoreDir/$TestWorld/test_file") {
            Write-Host "Backup restoration test passed"
            return $true
        } else {
            Write-Error "Backup restoration test failed"
            return $false
        }
    } catch {
        Write-Error "Failed to test backup restoration: $_"
        return $false
    }
}

# Function to test AWS Backup integration
function Test-AwsBackupIntegration {
    try {
        Write-Host "Checking AWS Backup IAM role..."
        aws iam get-role --role-name AWSBackupDefaultServiceRole 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "AWS Backup role exists"
        } else {
            Write-Error "AWS Backup role not found"
            return $false
        }
        
        # List recent backups
        $date = (Get-Date).AddDays(-1).ToString('yyyy-MM-ddTHH:mm:ssZ')
        aws backup list-recovery-points-by-backup-vault `
            --backup-vault-name minecraft-backup-vault `
            --by-created-after $date 2>&1 | Out-Null
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "AWS Backup vault accessible"
            return $true
        } else {
            Write-Error "AWS Backup vault access failed"
            return $false
        }
    } catch {
        Write-Error "Failed to test AWS Backup integration: $_"
        return $false
    }
}

# Function to test backup versioning
function Test-BackupVersioning {
    try {
        Write-Host "Testing backup versioning..."
        # Create multiple backups
        1..3 | ForEach-Object {
            Write-Host "Creating test backup $_..."
            "test data $_" | Set-Content "$WorldsDir/$TestWorld/test_file_$_"
            & /opt/minecraft/backup.sh
            Start-Sleep -Seconds 2
        }
        
        # Check if we have the correct number of backups (should keep last 5)
        $backupCount = (Get-ChildItem "$BackupDir/world_backup_*.tar.gz").Count
        if ($backupCount -le 5) {
            Write-Host "Backup versioning test passed (found $backupCount backups)"
            return $true
        } else {
            Write-Error "Backup versioning test failed (found $backupCount backups, expected <= 5)"
            return $false
        }
    } catch {
        Write-Error "Failed to test backup versioning: $_"
        return $false
    }
}

# Main execution
Write-Host "Running comprehensive backup validation tests..."

$tests = @(
    @{ Name = "Local Backup Creation"; Test = { Test-LocalBackupCreation } }
    @{ Name = "Backup Restoration"; Test = { Test-BackupRestoration } }
    @{ Name = "Backup Versioning"; Test = { Test-BackupVersioning } }
    @{ Name = "AWS Backup Integration"; Test = { Test-AwsBackupIntegration } }
)

# Add AWS Backup configuration tests if parameters provided
if ($args.Count -eq 4) {
    $VaultName = $args[0]
    $PlanId = $args[1]
    $SelectionId = $args[2]
    $ResourceArn = $args[3]
    
    $tests = @(
        @{ Name = "Backup Vault Check"; Test = { Test-BackupVault $VaultName } }
        @{ Name = "Backup Plan Check"; Test = { Test-BackupPlan $PlanId } }
        @{ Name = "Backup Selection Check"; Test = { Test-BackupSelection $PlanId $SelectionId } }
    ) + $tests
}

$allTestsPassed = $true
foreach ($test in $tests) {
    Write-Host "`nRunning test: $($test.Name)"
    if (-not (& $test.Test)) {
        $allTestsPassed = $false
        Write-Error "Test failed: $($test.Name)"
    }
}

# Cleanup
Remove-Item -Path "$WorldsDir/$TestWorld" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path $RestoreDir -Recurse -Force -ErrorAction SilentlyContinue

if ($allTestsPassed) {
    Write-Host "`nAll backup validation tests completed successfully!"
    exit 0
} else {
    Write-Error "`nSome tests failed. Please check the error messages above."
    exit 1
}