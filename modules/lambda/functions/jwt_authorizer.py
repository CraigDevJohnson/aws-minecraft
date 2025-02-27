import jwt  # Changed from 'import PyJWT as jwt'
import os
import boto3

def get_public_key():
    ssm = boto3.client('ssm')
    try:
        response = ssm.get_parameter(Name='/minecraft/jwt/public-key', WithDecryption=True)
        key_str = response['Parameter']['Value']
        
        # Format the key properly
        if not key_str.startswith('-----BEGIN'):
            # Split the key into 64-character chunks
            chunks = [key_str[i:i+64] for i in range(0, len(key_str), 64)]
            key_str = "-----BEGIN PUBLIC KEY-----\n" + "\n".join(chunks) + "\n-----END PUBLIC KEY-----"
        return key_str
    except Exception as e:
        print(f"Error getting public key: {str(e)}")
        raise

def generate_policy(principal_id, effect, resource):
    return {
        'principalId': principal_id,
        'policyDocument': {
            'Version': '2012-10-17',
            'Statement': [{
                'Action': 'execute-api:Invoke',
                'Effect': effect,
                'Resource': resource
            }]
        }
    }

def lambda_handler(event, context):
    try:
        print("Event:", event)  # Debug logging
        
        # Extract token - handle both API Gateway v2 and v1 formats
        auth_header = None
        if event.get('type') == 'REQUEST' and event.get('identitySource'):
            auth_header = event['identitySource'][0]
        else:
            auth_header = event.get('headers', {}).get('authorization')
        
        if not auth_header or not auth_header.startswith('Bearer '):
            print("No Bearer token found in:", auth_header)
            return generate_policy('user', 'Deny', event.get('routeArn', '*'))
        
        token = auth_header.replace('Bearer ', '')
        print("Extracted token:", token)  # Debug logging
        
        # Get the public key
        public_key = get_public_key()
        print("Public key:", public_key)  # Debug logging
        
        # Verify the JWT token
        try:
            payload = jwt.decode(
                token,
                public_key,
                algorithms=['RS256'],
                audience='minecraft-server-client',
                issuer='minecraft-auth'
            )
            print("Token verified successfully:", payload)  # Debug logging
            return generate_policy('user', 'Allow', event.get('routeArn', '*'))
            
        except jwt.InvalidTokenError as e:
            print(f"Token validation failed: {str(e)}")
            return generate_policy('user', 'Deny', event.get('routeArn', '*'))
            
    except Exception as e:
        print(f"Authorization error: {str(e)}")
        return generate_policy('user', 'Deny', event.get('routeArn', '*'))