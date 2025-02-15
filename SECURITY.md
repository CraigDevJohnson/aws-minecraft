# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.x     | :white_check_mark: |

## Reporting a Security Vulnerability

If you discover a security vulnerability within this project:

1. **Do Not** open a public issue
2. Send a private message to the repository maintainers
3. Include detailed information about the vulnerability
4. Allow time for the issue to be addressed before public disclosure

We take security issues seriously and will respond as quickly as possible.

## Security Best Practices

When deploying this infrastructure:

1. Always use private SSH keys and never commit them
2. Restrict security group access to necessary IPs only
3. Keep all AWS credentials secure and never commit them
4. Enable AWS CloudTrail for API activity monitoring
5. Regularly rotate credentials and SSH keys
6. Keep the Minecraft server and system packages updated
7. Monitor CloudWatch logs for suspicious activity