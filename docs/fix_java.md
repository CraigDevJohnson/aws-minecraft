# Java Server Deployment Troubleshooting Guide

## Initial Assessment
From the reported symptoms:
- server_type is set to "java"
- Some Java-specific configurations were applied
- Bedrock server is running instead of Java server

## Step-by-Step Verification

### 1. Configuration Validation
Check the following files for server_type value:

```bash
# Environment variables
tofu output server_type
# Should return "java"
Returns Java

# Check server.properties on instance
ssh -i <key_name>.pem ubuntu@<server_ip> "cat /opt/minecraft/server.properties"
# Should match Java configuration from admin/configs/java.properties
Matches Bedrock Properties
```

### 2. Script Execution Path Analysis
Check which installation script was executed:

```bash
# On the server, check installation logs
ssh -i <key_name>.pem ubuntu@<server_ip> "cat /var/log/minecraft/install.log"
# Look for lines indicating which script was executed (install_java.sh or install_bedrock.sh)
++ date '+%Y-%m-%d %H:%M:%S'
+ echo '[2025-02-21 09:40:31] Starting Minecraft Bedrock server installation...'
[2025-02-21 09:40:31] Starting Minecraft Bedrock server installation...
+ apt-get update
```

### 3. Server Process Verification
Check running processes:

```bash
# On the server
ssh -i <key_name>.pem ubuntu@<server_ip> "ps aux | grep -E 'java|bedrock'"
# Should show Java process if correctly deployed
ubuntu      1299  2.8  6.2 995052 246888 ?       Sl   06:23   1:15 ./bedrock_server
```

### 4. Service Configuration Check
Verify systemd service setup:

```bash
# On the server
ssh -i <key_name>.pem ubuntu@<server_ip> "cat /etc/systemd/system/minecraft.service"
# Should show Java-specific configuration with JVM parameters
No JVM parameters
```

### 5. File System Inspection
Check installed server files:

```bash
# On the server
ssh -i <key_name>.pem ubuntu@<server_ip> "ls -la /opt/minecraft/"
# Should have server.jar for Java, not bedrock_server
Has bedrock_server and no server.jar
```

## Common Failure Points

1. **User Data Script Selection**
   - Check `modules/compute/main.tf` for correct script path selection
   - Verify local.script_path evaluation

2. **Installation Script Download**
   - Check S3 bucket contents for correct script versions
   - Verify script download logs in user_data.sh execution

3. **Server Type Variable Propagation**
   - Verify variable passing through all module levels
   - Check for hardcoded values overriding variables

## Instance State Investigation

### Instance Persistence Analysis
1. **Check Instance State:**
```bash
# View current instance state and creation time
tofu show | grep -A 10 "aws_instance"
# Check AWS console or use AWS CLI
aws ec2 describe-instances --filters "Name=tag:Name,Values=minecraft-server" --query 'Reservations[].Instances[].{ID:InstanceId,LaunchTime:LaunchTime,State:State.Name}'
```

2. **Verify State File:**
```bash
# Check current state file for instance details
tofu state show aws_instance.minecraft_server
```

3. **Resource Modification Behavior:**
```bash
# Check plan output for in-place updates vs replacements
tofu plan -var="server_type=java" -detailed-exitcode
```

## Recovery Steps

1. Stop the current server:
```bash
ssh -i <key_name>.pem ubuntu@<server_ip> "sudo systemctl stop minecraft"
```

2. Clean existing installation:
```bash
ssh -i <key_name>.pem ubuntu@<server_ip> "sudo rm -rf /opt/minecraft/*"
```

3. Re-run tofu with explicit variable setting:
```bash
tofu destroy -var="server_type=java"
tofu apply -var="server_type=java" -var="instance_type=t3.large"
```

## Modified Recovery Steps

1. **Force New Instance Creation:**
```bash
# Add -replace flag to force new instance creation
tofu apply -var="server_type=java" -replace="aws_instance.minecraft_server"
```

2. **Alternative Full Reset:**
```bash
# Remove instance from state without destroying
tofu state rm aws_instance.minecraft_server
# Clean local state
tofu init -reconfigure
# Reapply with correct variables
tofu apply -var="server_type=java"
```

3. **Verify Clean Deployment:**
```bash
# Check instance metadata for fresh deployment
ssh -i <key_name>.pem ubuntu@<server_ip> "cat /var/log/cloud-init-output.log"
```

## Debugging Tools

1. **Enable Debug Logging**
   - Add `TF_LOG=DEBUG` before tofu commands
   - Check CloudWatch logs for instance initialization

2. **Script Validation**
   - Use `validate_all.sh` script on server
   - Check test results in `/var/log/minecraft/test/`

## Prevention Measures

1. Add lifecycle block to force replacement on server_type change:
```hcl
lifecycle {
  replace_triggered_by = [
    var.server_type
  ]
}
```

2. Add validation rules to prevent in-place updates:
```hcl
lifecycle {
  prevent_destroy = false
  create_before_destroy = true
}
```

3. Consider adding a unique identifier to force new instance:
```hcl
resource "aws_instance" "minecraft_server" {
  # ...existing code...
  tags = {
    Name = "minecraft-${var.server_type}-${random_id.server_id.hex}"
  }
}
```

## Next Steps

1. Document findings from each verification step
2. Compare results against expected Java server configuration
3. Identify specific point of failure in deployment process
4. Consider adding additional validation checks to prevent mixed installations