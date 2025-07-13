"""
AWS Ollama Platform - Models Management Lambda Function

Handles model listing, starting, and stopping operations.
Integrates with ECS for dynamic model deployment.
"""

import json
import boto3
import os
import uuid
from datetime import datetime, timezone
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
ecs_client = boto3.client('ecs')
elbv2_client = boto3.client('elbv2')


def lambda_handler(event, context):
    """
    Main Lambda handler for model management operations.
    
    Supported endpoints:
    - GET /models
    - POST /models/start
    - DELETE /models/{id}/stop
    """
    try:
        http_method = event['httpMethod']
        path = event['path']
        user_info = get_user_info_from_context(event)
        
        logger.info(f"Processing {http_method} request to {path} for user {user_info['user_id']}")
        
        if path == '/models' and http_method == 'GET':
            return list_models()
        elif path == '/models/start' and http_method == 'POST':
            return start_model(event, user_info)
        elif path.startswith('/models/') and path.endswith('/stop') and http_method == 'DELETE':
            instance_id = path.split('/')[-2]
            return stop_model(instance_id, user_info)
        else:
            return create_error_response(404, 'Not found')
            
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        return create_error_response(500, 'Internal server error')


def get_user_info_from_context(event):
    """Extract user information from Cognito JWT token."""
    claims = event.get('requestContext', {}).get('authorizer', {}).get('claims', {})
    groups = claims.get('cognito:groups', '')
    
    return {
        'user_id': claims.get('sub'),
        'email': claims.get('email'),
        'groups': groups.split(',') if groups else []
    }


def list_models():
    """List all available models."""
    try:
        models_table = dynamodb.Table(os.environ['MODELS_TABLE_NAME'])
        
        response = models_table.scan(
            FilterExpression='is_active = :active',
            ExpressionAttributeValues={':active': True}
        )
        
        models = response.get('Items', [])
        
        # Sort models by name
        models.sort(key=lambda x: x.get('model_name', ''))
        
        return create_success_response({
            'models': models,
            'count': len(models)
        })
        
    except Exception as e:
        logger.error(f"Failed to list models: {str(e)}")
        return create_error_response(500, 'Failed to retrieve models')


def start_model(event, user_info):
    """Start a new model instance."""
    try:
        body = json.loads(event['body'])
        model_id = body.get('model_id')
        instance_type = body.get('instance_type', 'fargate')
        custom_name = body.get('name', '')
        
        if not model_id:
            return create_error_response(400, 'model_id is required')
        
        # Get model configuration
        models_table = dynamodb.Table(os.environ['MODELS_TABLE_NAME'])
        model_response = models_table.get_item(Key={'model_id': model_id})
        
        if 'Item' not in model_response:
            return create_error_response(404, 'Model not found')
        
        model = model_response['Item']
        instance_id = str(uuid.uuid4())
        
        # Check user's instance limits
        if not check_user_instance_limits(user_info['user_id']):
            return create_error_response(429, 'Instance limit exceeded')
        
        # Create ECS service
        service_name = f"ollama-{instance_id[:8]}"
        task_definition_arn = create_task_definition(model, instance_type, instance_id)
        
        # Create target group for this instance
        target_group_arn = create_target_group(service_name)
        
        # Create ECS service
        ecs_service_response = ecs_client.create_service(
            cluster=os.environ['ECS_CLUSTER_NAME'],
            serviceName=service_name,
            taskDefinition=task_definition_arn,
            desiredCount=1,
            launchType='FARGATE' if instance_type == 'fargate' else 'EC2',
            networkConfiguration={
                'awsvpcConfiguration': {
                    'subnets': os.environ.get('PRIVATE_SUBNET_IDS', '').split(','),
                    'securityGroups': [os.environ.get('ECS_SECURITY_GROUP_ID')],
                    'assignPublicIp': 'DISABLED'
                }
            } if instance_type == 'fargate' else {},
            loadBalancers=[
                {
                    'targetGroupArn': target_group_arn,
                    'containerName': 'ollama',
                    'containerPort': 11434
                }
            ],
            tags=[
                {'key': 'Environment', 'value': os.environ['ENVIRONMENT']},
                {'key': 'Project', 'value': 'aws-ollama-platform'},
                {'key': 'Owner', 'value': user_info['user_id']},
                {'key': 'Model', 'value': model_id}
            ]
        )
        
        # Store instance information
        instances_table = dynamodb.Table(os.environ['INSTANCES_TABLE_NAME'])
        
        endpoint_url = f"https://ollama-{instance_id[:8]}.{os.environ.get('DOMAIN_NAME', 'example.com')}"
        
        instances_table.put_item(
            Item={
                'instance_id': instance_id,
                'model_id': model_id,
                'user_id': user_info['user_id'],
                'service_name': service_name,
                'ecs_service_arn': ecs_service_response['service']['serviceArn'],
                'target_group_arn': target_group_arn,
                'task_definition_arn': task_definition_arn,
                'status': 'starting',
                'instance_type': instance_type,
                'endpoint_url': endpoint_url,
                'custom_name': custom_name,
                'created_at': datetime.now(timezone.utc).isoformat(),
                'ttl': int((datetime.now(timezone.utc).timestamp() + 24*3600))  # 24 hours TTL
            }
        )
        
        logger.info(f"Started model {model_id} as instance {instance_id} for user {user_info['user_id']}")
        
        return create_success_response({
            'instance_id': instance_id,
            'service_name': service_name,
            'status': 'starting',
            'endpoint_url': endpoint_url,
            'estimated_ready_time': '2-5 minutes'
        }, status_code=201)
        
    except Exception as e:
        logger.error(f"Failed to start model: {str(e)}")
        return create_error_response(500, 'Failed to start model')


def stop_model(instance_id, user_info):
    """Stop a running model instance."""
    try:
        instances_table = dynamodb.Table(os.environ['INSTANCES_TABLE_NAME'])
        
        # Get instance information
        response = instances_table.get_item(Key={'instance_id': instance_id})
        
        if 'Item' not in response:
            return create_error_response(404, 'Instance not found')
        
        instance = response['Item']
        
        # Check permissions
        if instance['user_id'] != user_info['user_id'] and 'Administrators' not in user_info['groups']:
            return create_error_response(403, 'Access denied')
        
        # Stop ECS service
        try:
            ecs_client.update_service(
                cluster=os.environ['ECS_CLUSTER_NAME'],
                service=instance['service_name'],
                desiredCount=0
            )
            
            # Wait a moment then delete the service
            import time
            time.sleep(5)
            
            ecs_client.delete_service(
                cluster=os.environ['ECS_CLUSTER_NAME'],
                service=instance['service_name']
            )
            
        except Exception as e:
            logger.warning(f"Failed to stop ECS service: {str(e)}")
        
        # Delete target group
        try:
            elbv2_client.delete_target_group(
                TargetGroupArn=instance.get('target_group_arn')
            )
        except Exception as e:
            logger.warning(f"Failed to delete target group: {str(e)}")
        
        # Update instance status
        instances_table.update_item(
            Key={'instance_id': instance_id},
            UpdateExpression='SET #status = :status, stopped_at = :stopped_at',
            ExpressionAttributeNames={'#status': 'status'},
            ExpressionAttributeValues={
                ':status': 'stopped',
                ':stopped_at': datetime.now(timezone.utc).isoformat()
            }
        )
        
        logger.info(f"Stopped instance {instance_id} for user {user_info['user_id']}")
        
        return create_success_response({
            'instance_id': instance_id,
            'status': 'stopped'
        })
        
    except Exception as e:
        logger.error(f"Failed to stop model: {str(e)}")
        return create_error_response(500, 'Failed to stop model')


def check_user_instance_limits(user_id):
    """Check if user has reached instance limits."""
    try:
        instances_table = dynamodb.Table(os.environ['INSTANCES_TABLE_NAME'])
        
        response = instances_table.query(
            IndexName='UserIdIndex',
            KeyConditionExpression=boto3.dynamodb.conditions.Key('user_id').eq(user_id),
            FilterExpression='#status IN (:running, :starting)',
            ExpressionAttributeNames={'#status': 'status'},
            ExpressionAttributeValues={
                ':running': 'running',
                ':starting': 'starting'
            }
        )
        
        active_instances = len(response.get('Items', []))
        max_instances = int(os.environ.get('MAX_INSTANCES_PER_USER', '5'))
        
        return active_instances < max_instances
        
    except Exception as e:
        logger.error(f"Failed to check instance limits: {str(e)}")
        return False


def create_task_definition(model, instance_type, instance_id):
    """Create ECS task definition for the model."""
    try:
        family_name = f"{os.environ['ENVIRONMENT']}-ollama-{model['model_id']}-{instance_id[:8]}"
        
        # Select appropriate CPU and memory based on model requirements
        cpu_req = model.get('cpu_requirements', {})
        cpu = str(cpu_req.get('vcpu', 1) * 1024)
        memory = str(cpu_req.get('memory_mb', 2048))
        
        container_def = {
            'name': 'ollama',
            'image': model.get('image_uri', 'ollama/ollama:latest'),
            'essential': True,
            'portMappings': [
                {
                    'containerPort': 11434,
                    'protocol': 'tcp'
                }
            ],
            'environment': [
                {'name': 'OLLAMA_HOST', 'value': '0.0.0.0'},
                {'name': 'OLLAMA_ORIGINS', 'value': '*'},
                {'name': 'OLLAMA_MODEL', 'value': model['model_id']}
            ],
            'healthCheck': {
                'command': ['CMD-SHELL', 'curl -f http://localhost:11434/api/tags || exit 1'],
                'interval': 30,
                'timeout': 5,
                'retries': 3,
                'startPeriod': 120
            },
            'logConfiguration': {
                'logDriver': 'awslogs',
                'options': {
                    'awslogs-group': f"/ecs/{os.environ['ENVIRONMENT']}-ollama",
                    'awslogs-region': os.environ['AWS_REGION'],
                    'awslogs-stream-prefix': f"ollama-{instance_id[:8]}"
                }
            }
        }
        
        task_def = {
            'family': family_name,
            'networkMode': 'awsvpc',
            'requiresCompatibilities': ['FARGATE' if instance_type == 'fargate' else 'EC2'],
            'cpu': cpu,
            'memory': memory,
            'executionRoleArn': os.environ.get('ECS_EXECUTION_ROLE_ARN'),
            'taskRoleArn': os.environ.get('ECS_TASK_ROLE_ARN'),
            'containerDefinitions': [container_def],
            'tags': [
                {'key': 'Environment', 'value': os.environ['ENVIRONMENT']},
                {'key': 'Project', 'value': 'aws-ollama-platform'},
                {'key': 'Model', 'value': model['model_id']}
            ]
        }
        
        # Add GPU configuration if needed
        if instance_type == 'gpu' and model.get('gpu_requirements'):
            container_def['resourceRequirements'] = [
                {
                    'type': 'GPU',
                    'value': '1'
                }
            ]
            task_def['requiresCompatibilities'] = ['EC2']
            task_def['placementConstraints'] = [
                {
                    'type': 'memberOf',
                    'expression': 'attribute:ecs.instance-type =~ g4dn.*'
                }
            ]
        
        response = ecs_client.register_task_definition(**task_def)
        return response['taskDefinition']['taskDefinitionArn']
        
    except Exception as e:
        logger.error(f"Failed to create task definition: {str(e)}")
        raise


def create_target_group(service_name):
    """Create ALB target group for the service."""
    try:
        response = elbv2_client.create_target_group(
            Name=service_name[:32],  # Target group names have length limits
            Protocol='HTTP',
            Port=11434,
            VpcId=os.environ.get('VPC_ID'),
            TargetType='ip',
            HealthCheckEnabled=True,
            HealthCheckGracePeriodSeconds=300,
            HealthCheckIntervalSeconds=30,
            HealthCheckPath='/api/tags',
            HealthCheckPort='traffic-port',
            HealthCheckProtocol='HTTP',
            HealthCheckTimeoutSeconds=5,
            HealthyThresholdCount=2,
            UnhealthyThresholdCount=2,
            Matcher={'HttpCode': '200'},
            Tags=[
                {'Key': 'Environment', 'Value': os.environ['ENVIRONMENT']},
                {'Key': 'Project', 'Value': 'aws-ollama-platform'},
                {'Key': 'Service', 'Value': service_name}
            ]
        )
        
        return response['TargetGroups'][0]['TargetGroupArn']
        
    except Exception as e:
        logger.error(f"Failed to create target group: {str(e)}")
        raise


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