# Minecraft Server Management API

## Overview
This API provides endpoints to manage the Minecraft server state (start/stop) and check its status. It is implemented using AWS Lambda and API Gateway.

## Base URL
- Development: {api_gateway_url}/dev/server
- Production: {api_gateway_url}/prod/server

## Authentication
- Start/Status: No authentication required
- Stop: Requires admin token in request body

## Endpoints

### Check Server Status
```
POST /server
{
    "action": "status"
}
```

#### Response
```json
{
    "state": "running|stopped|pending|stopping",
    "instanceId": "i-xxxxxxxxxxxxx",
    "environment": "dev|prod"
}
```

### Start Server
```
POST /server
{
    "action": "start"
}
```

#### Response
```json
{
    "message": "Server is starting",
    "state": "pending"
}
```

### Stop Server (Admin Only)
```
POST /server
{
    "action": "stop",
    "token": "your-admin-token"
}
```

#### Response
```json
{
    "message": "Server is stopping",
    "state": "stopping"
}
```

## Error Responses

### Invalid Action
```json
{
    "error": "Invalid action. Must be start, stop, or status"
}
```

### Unauthorized
```json
{
    "error": "Unauthorized"
}
```

### Invalid State Transition
```json
{
    "error": "Cannot {action} server in state {currentState}",
    "currentState": "running|stopped|pending|stopping"
}
```

## CORS
- Development: Allows all origins (*)
- Production: Restricted to specific domain

## Rate Limiting
- Development: No rate limiting
- Production: TBD based on usage patterns

## Monitoring
- CloudWatch Logs enabled
- Request tracking via API Gateway
- Error reporting via CloudWatch Metrics

## Security Considerations
1. Admin token must be securely stored and rotated
2. Production environment should use API keys
3. CORS origins must be restricted in production
4. Rate limiting should be implemented in production
5. Consider implementing WAF rules for production

## Example Usage

### curl
```bash
# Check Status
curl -X POST https://{api_url}/server \
  -H "Content-Type: application/json" \
  -d '{"action":"status"}'

# Start Server
curl -X POST https://{api_url}/server \
  -H "Content-Type: application/json" \
  -d '{"action":"start"}'

# Stop Server (Admin)
curl -X POST https://{api_url}/server \
  -H "Content-Type: application/json" \
  -d '{"action":"stop","token":"your-admin-token"}'
```

### JavaScript
```javascript
async function checkServerStatus() {
  const response = await fetch('https://{api_url}/server', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      action: 'status'
    })
  });
  return await response.json();
}
```

## Implementation Status

### Completed
- Basic endpoint structure
- Server state management
- Admin authentication
- Error handling
- CORS for development

### Pending
- Production CORS configuration
- API key implementation
- Rate limiting
- WAF rules
- Monitoring setup
- Secret rotation
- Load testing