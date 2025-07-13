"""
AWS Ollama Platform - Authentication Lambda Function

Handles user authentication, signup, and password reset operations
using AWS Cognito User Pool.
"""

import json
import boto3
import os
from datetime import datetime, timezone
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
cognito_client = boto3.client('cognito-idp')
dynamodb = boto3.resource('dynamodb')


def lambda_handler(event, context):
    """
    Main Lambda handler for authentication operations.
    
    Supported endpoints:
    - POST /auth/login
    - POST /auth/signup
    - POST /auth/reset-password
    """
    try:
        http_method = event['httpMethod']
        path = event['path']
        
        logger.info(f"Processing {http_method} request to {path}")
        
        if path == '/auth/login' and http_method == 'POST':
            return handle_login(event)
        elif path == '/auth/signup' and http_method == 'POST':
            return handle_signup(event)
        elif path == '/auth/reset-password' and http_method == 'POST':
            return handle_reset_password(event)
        else:
            return create_error_response(404, 'Not found')
            
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        return create_error_response(500, 'Internal server error')


def handle_login(event):
    """Handle user login with email and password."""
    try:
        body = json.loads(event['body'])
        email = body.get('email')
        password = body.get('password')
        
        if not email or not password:
            return create_error_response(400, 'Email and password are required')
        
        # Authenticate with Cognito
        response = cognito_client.admin_initiate_auth(
            UserPoolId=os.environ['USER_POOL_ID'],
            ClientId=os.environ['USER_POOL_CLIENT_ID'],
            AuthFlow='ADMIN_USER_PASSWORD_AUTH',
            AuthParameters={
                'USERNAME': email,
                'PASSWORD': password
            }
        )
        
        # Update user record in DynamoDB
        update_user_last_login(email)
        
        return create_success_response({
            'access_token': response['AuthenticationResult']['AccessToken'],
            'id_token': response['AuthenticationResult']['IdToken'],
            'refresh_token': response['AuthenticationResult']['RefreshToken'],
            'expires_in': response['AuthenticationResult']['ExpiresIn'],
            'token_type': 'Bearer'
        })
        
    except cognito_client.exceptions.NotAuthorizedException:
        return create_error_response(401, 'Invalid credentials')
    except cognito_client.exceptions.UserNotConfirmedException:
        return create_error_response(401, 'User account not confirmed')
    except cognito_client.exceptions.PasswordResetRequiredException:
        return create_error_response(401, 'Password reset required')
    except Exception as e:
        logger.error(f"Login error: {str(e)}")
        return create_error_response(500, 'Authentication failed')


def handle_signup(event):
    """Handle user registration."""
    try:
        body = json.loads(event['body'])
        email = body.get('email')
        password = body.get('password')
        name = body.get('name', '')
        
        if not email or not password:
            return create_error_response(400, 'Email and password are required')
        
        # Create user in Cognito
        user_attributes = [
            {'Name': 'email', 'Value': email},
            {'Name': 'email_verified', 'Value': 'true'}
        ]
        
        if name:
            user_attributes.append({'Name': 'name', 'Value': name})
        
        cognito_client.admin_create_user(
            UserPoolId=os.environ['USER_POOL_ID'],
            Username=email,
            UserAttributes=user_attributes,
            TemporaryPassword=password,
            MessageAction='SUPPRESS'
        )
        
        # Set permanent password
        cognito_client.admin_set_user_password(
            UserPoolId=os.environ['USER_POOL_ID'],
            Username=email,
            Password=password,
            Permanent=True
        )
        
        # Add user to default group
        try:
            cognito_client.admin_add_user_to_group(
                UserPoolId=os.environ['USER_POOL_ID'],
                Username=email,
                GroupName='Users'
            )
        except Exception as e:
            logger.warning(f"Failed to add user to group: {str(e)}")
        
        # Create user record in DynamoDB
        create_user_record(email, name)
        
        return create_success_response({
            'message': 'User created successfully',
            'email': email
        }, status_code=201)
        
    except cognito_client.exceptions.UsernameExistsException:
        return create_error_response(409, 'User already exists')
    except cognito_client.exceptions.InvalidPasswordException:
        return create_error_response(400, 'Invalid password format')
    except Exception as e:
        logger.error(f"Signup error: {str(e)}")
        return create_error_response(500, 'User creation failed')


def handle_reset_password(event):
    """Handle password reset request."""
    try:
        body = json.loads(event['body'])
        email = body.get('email')
        
        if not email:
            return create_error_response(400, 'Email is required')
        
        # Initiate password reset
        cognito_client.admin_reset_user_password(
            UserPoolId=os.environ['USER_POOL_ID'],
            Username=email
        )
        
        return create_success_response({
            'message': 'Password reset email sent successfully'
        })
        
    except cognito_client.exceptions.UserNotFoundException:
        return create_error_response(404, 'User not found')
    except Exception as e:
        logger.error(f"Password reset error: {str(e)}")
        return create_error_response(500, 'Password reset failed')


def create_user_record(email, name):
    """Create user record in DynamoDB."""
    try:
        users_table = dynamodb.Table(os.environ['USERS_TABLE_NAME'])
        
        # Get user details from Cognito
        user_info = cognito_client.admin_get_user(
            UserPoolId=os.environ['USER_POOL_ID'],
            Username=email
        )
        
        cognito_sub = None
        for attr in user_info['UserAttributes']:
            if attr['Name'] == 'sub':
                cognito_sub = attr['Value']
                break
        
        users_table.put_item(
            Item={
                'user_id': cognito_sub,
                'cognito_sub': cognito_sub,
                'email': email,
                'name': name,
                'role': 'User',
                'created_at': datetime.now(timezone.utc).isoformat(),
                'last_login': datetime.now(timezone.utc).isoformat(),
                'is_active': True
            }
        )
        
    except Exception as e:
        logger.error(f"Failed to create user record: {str(e)}")


def update_user_last_login(email):
    """Update user's last login timestamp."""
    try:
        # Get user details from Cognito
        user_info = cognito_client.admin_get_user(
            UserPoolId=os.environ['USER_POOL_ID'],
            Username=email
        )
        
        cognito_sub = None
        for attr in user_info['UserAttributes']:
            if attr['Name'] == 'sub':
                cognito_sub = attr['Value']
                break
        
        if cognito_sub:
            users_table = dynamodb.Table(os.environ['USERS_TABLE_NAME'])
            users_table.update_item(
                Key={'user_id': cognito_sub},
                UpdateExpression='SET last_login = :timestamp',
                ExpressionAttributeValues={
                    ':timestamp': datetime.now(timezone.utc).isoformat()
                }
            )
            
    except Exception as e:
        logger.error(f"Failed to update last login: {str(e)}")


def create_success_response(data, status_code=200):
    """Create a successful API response."""
    return {
        'statusCode': status_code,
        'headers': {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type,Authorization',
            'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
            'Content-Type': 'application/json'
        },
        'body': json.dumps(data)
    }


def create_error_response(status_code, message):
    """Create an error API response."""
    return {
        'statusCode': status_code,
        'headers': {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type,Authorization',
            'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
            'Content-Type': 'application/json'
        },
        'body': json.dumps({'error': message})
    }