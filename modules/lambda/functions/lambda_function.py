import boto3 # type: ignore
import json
import os
import time
import uuid
import hmac
import hashlib
import traceback
from botocore.exceptions import ClientError # type: ignore

def generate_secure_token(environment):
    """Generate a secure token for API authentication
    Returns a 64-character hexadecimal string that combines:
    - UUID v4 for uniqueness
    - HMAC-SHA256 for cryptographic security
    - Environment-specific salt
    """
    # Generate a random UUID
    random_uuid = str(uuid.uuid4())
    
    # Create an environment-specific salt
    salt = f"minecraft-{environment}-{int(time.time())}"
    
    # Create HMAC using SHA256
    hmac_obj = hmac.new(
        salt.encode('utf-8'),
        random_uuid.encode('utf-8'),
        hashlib.sha256
    )
    
    return hmac_obj.hexdigest()

def get_admin_token():
    """Get admin token from SSM Parameter Store"""
    try:
        ssm = boto3.client('ssm')
        response = ssm.get_parameter(
            Name=f"/minecraft/{os.environ.get('ENVIRONMENT')}/admin_token",
            WithDecryption=True
        )
        return response['Parameter']['Value']
    except ClientError as e:
        print(f"Error getting admin token: {e}")
        raise

def validate_auth_token(token):
    """Validate the authentication token for stop operations"""
    if not token:
        print("No token provided")
        return False
        
    try:
        expected_token = get_admin_token()
        is_valid = token == expected_token
        print(f"Token validation result:")
        print(f"- Token provided: Yes (length: {len(token)})")
        print(f"- Token format valid: {bool(token and len(token) == 64)}")
        print(f"- Environment: {os.environ.get('ENVIRONMENT')}")
        print(f"- SSM parameter exists: Yes")
        print(f"- Token match: {is_valid}")
        return is_valid
    except Exception as e:
        print(f"Error validating token: {str(e)}")
        print("Full error context:")
        traceback.print_exc()
        return False

def get_instance_state(ec2_client, instance_id):
    """Get the current state of the EC2 instance"""
    try:
        response = ec2_client.describe_instances(InstanceIds=[instance_id])
        return response['Reservations'][0]['Instances'][0]['State']['Name']
    except ClientError as e:
        print(f"Error getting instance state: {e}")
        raise

def lambda_handler(event, context):
    # Environment variables
    instance_id = os.environ.get('INSTANCE_ID')
    environment = os.environ.get('ENVIRONMENT')
    region = os.environ.get('AWS_REGION', 'us-west-2')
    
    if not instance_id:
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps({'error': 'INSTANCE_ID environment variable not set'})
        }

    # Initialize AWS client
    ec2_client = boto3.client('ec2', region_name=region)
    
    try:
        # Get the action from the request - APIGatewayV2 format
        body = json.loads(event.get('body', '{}'))
        action = body.get('action')
        
        if action not in ['start', 'stop', 'status']:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json'
                },
                'body': json.dumps({'error': 'Invalid action. Must be start, stop, or status'})
            }
        
        # Check authentication for stop action
        if action == 'stop':
            token = body.get('token')
            if not token or not validate_auth_token(token):
                return {
                    'statusCode': 403,
                    'headers': {
                        'Content-Type': 'application/json'
                    },
                    'body': json.dumps({'error': 'Unauthorized'})
                }

        current_state = get_instance_state(ec2_client, instance_id)
        
        if action == 'status':
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json'
                },
                'body': json.dumps({
                    'state': current_state,
                    'instanceId': instance_id,
                    'environment': environment
                })
            }
            
        if action == 'start' and current_state == 'stopped':
            ec2_client.start_instances(InstanceIds=[instance_id])
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json'
                },
                'body': json.dumps({'message': 'Server is starting', 'state': 'pending'})
            }
            
        elif action == 'stop' and current_state == 'running':
            ec2_client.stop_instances(InstanceIds=[instance_id])
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json'
                },
                'body': json.dumps({'message': 'Server is stopping', 'state': 'stopping'})
            }
            
        else:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json'
                },
                'body': json.dumps({
                    'error': f'Cannot {action} server in state {current_state}',
                    'currentState': current_state
                })
            }

    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps({'error': str(e)})
        }