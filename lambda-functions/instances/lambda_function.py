import json
import boto3
import os
import uuid
from datetime import datetime, timezone
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# AWS clients
dynamodb = boto3.resource('dynamodb')
ecs_client = boto3.client('ecs')

def lambda_handler(event, context):
    """
    Instances API Lambda Handler
    Handles CRUD operations for Ollama model instances
    """
    try:
        http_method = event['httpMethod']
        path = event['path']
        user_info = get_user_info_from_context(event)
        
        logger.info(f"Processing {http_method} {path} for user {user_info.get('user_id')}")
        
        if path == '/instances' and http_method == 'GET':
            return list_instances(user_info)
        elif path == '/instances' and http_method == 'POST':
            return create_instance(event, user_info)
        elif path.startswith('/instances/') and http_method == 'DELETE':
            instance_id = path.split('/')[-1]
            return delete_instance(instance_id, user_info)
        elif path.startswith('/instances/') and http_method == 'GET':
            instance_id = path.split('/')[-1]
            return get_instance(instance_id, user_info)
        else:
            return {
                'statusCode': 404,
                'headers': cors_headers(),
                'body': json.dumps({'error': 'Not found'})
            }
    except Exception as e:
        logger.error(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': cors_headers(),
            'body': json.dumps({'error': 'Internal server error', 'message': str(e)})
        }

def get_user_info_from_context(event):
    """Extract user information from Cognito JWT claims"""
    claims = event.get('requestContext', {}).get('authorizer', {}).get('claims', {})
    return {
        'user_id': claims.get('sub'),
        'email': claims.get('email'),
        'username': claims.get('cognito:username'),
        'groups': claims.get('cognito:groups', '').split(',') if claims.get('cognito:groups') else []
    }

def create_instance(event, user_info):
    """Create a new Ollama model instance"""
    try:
        body = json.loads(event['body'])
        model_id = body.get('modelId')
        instance_type = body.get('instanceType', 'ml.m5.large')
        
        if not model_id:
            return {
                'statusCode': 400,
                'headers': cors_headers(),
                'body': json.dumps({'error': 'modelId is required'})
            }
        
        # Get model information from DynamoDB
        models_table = dynamodb.Table(os.environ['MODELS_TABLE_NAME'])
        model_response = models_table.get_item(Key={'id': model_id})
        
        if 'Item' not in model_response:
            return {
                'statusCode': 404,
                'headers': cors_headers(),
                'body': json.dumps({'error': 'Model not found'})
            }
        
        model_info = model_response['Item']
        
        # Generate unique instance ID
        instance_id = str(uuid.uuid4())
        
        # Start ECS task with appropriate configuration
        task_arn = start_ecs_task(instance_id, model_id, model_info, instance_type, user_info)
        
        # Save instance information to DynamoDB
        instances_table = dynamodb.Table(os.environ['INSTANCES_TABLE_NAME'])
        
        instance_data = {
            'id': instance_id,
            'user_id': user_info['user_id'],
            'model_id': model_id,
            'model_name': model_info['name'],
            'status': 'starting',
            'instance_type': instance_type,
            'task_arn': task_arn,
            'created_at': datetime.now(timezone.utc).isoformat(),
            'updated_at': datetime.now(timezone.utc).isoformat(),
            'estimated_cost': get_estimated_cost(instance_type),
            'endpoint': f"https://{instance_id}.{os.environ.get('DOMAIN_NAME', 'localhost')}/api"
        }
        
        instances_table.put_item(Item=instance_data)
        
        logger.info(f"Created instance {instance_id} for user {user_info['user_id']}")
        
        return {
            'statusCode': 201,
            'headers': cors_headers(),
            'body': json.dumps({
                'id': instance_id,
                'modelId': model_id,
                'modelName': model_info['name'],
                'status': 'starting',
                'instanceType': instance_type,
                'estimatedCost': get_estimated_cost(instance_type),
                'endpoint': instance_data['endpoint'],
                'startedAt': instance_data['created_at']
            })
        }
        
    except Exception as e:
        logger.error(f"Error creating instance: {str(e)}")
        return {
            'statusCode': 500,
            'headers': cors_headers(),
            'body': json.dumps({'error': 'Failed to create instance', 'message': str(e)})
        }

def start_ecs_task(instance_id, model_id, model_info, instance_type, user_info):
    """Start ECS task with model-specific configuration"""
    
    # Get task definition and container image based on model and instance type
    task_config = get_task_configuration(model_id, instance_type)
    
    # Container environment variables
    container_overrides = {
        'name': 'ollama',
        'environment': [
            {'name': 'OLLAMA_HOST', 'value': '0.0.0.0'},
            {'name': 'OLLAMA_ORIGINS', 'value': '*'},
            {'name': 'MODEL_NAME', 'value': model_info.get('ollama_model_name', model_id)},
            {'name': 'INSTANCE_ID', 'value': instance_id},
            {'name': 'USER_ID', 'value': user_info['user_id']},
            {'name': 'PRELOAD_MODEL', 'value': 'true'}
        ]
    }
    
    # Add container image override if using pre-built model image
    if task_config.get('container_image'):
        container_overrides['image'] = task_config['container_image']
    
    # ECS task configuration
    run_task_params = {
        'cluster': os.environ['ECS_CLUSTER_NAME'],
        'taskDefinition': task_config['task_definition'],
        'launchType': task_config['launch_type'],
        'overrides': {
            'containerOverrides': [container_overrides]
        },
        'tags': [
            {'key': 'Environment', 'value': os.environ['ENVIRONMENT']},
            {'key': 'Project', 'value': 'aws-ollama-platform'},
            {'key': 'InstanceId', 'value': instance_id},
            {'key': 'UserId', 'value': user_info['user_id']},
            {'key': 'ModelId', 'value': model_id}
        ]
    }
    
    # Add network configuration for Fargate
    if task_config['launch_type'] == 'FARGATE':
        run_task_params['networkConfiguration'] = {
            'awsvpcConfiguration': {
                'subnets': os.environ['PRIVATE_SUBNET_IDS'].split(','),
                'securityGroups': [os.environ['ECS_SECURITY_GROUP_ID']],
                'assignPublicIp': 'DISABLED'
            }
        }
    
    # Add placement constraints for EC2 with specific instance types
    if task_config['launch_type'] == 'EC2' and task_config.get('placement_constraints'):
        run_task_params['placementConstraints'] = task_config['placement_constraints']
    
    # Start the ECS task
    response = ecs_client.run_task(**run_task_params)
    
    if not response['tasks']:
        raise Exception("Failed to start ECS task")
    
    task_arn = response['tasks'][0]['taskArn']
    logger.info(f"Started ECS task {task_arn} for instance {instance_id}")
    
    return task_arn

def get_task_configuration(model_id, instance_type):
    """
    Get appropriate task definition and configuration based on model and instance type
    """
    
    # Model-specific ECR image mapping
    model_images = {
        'llama2:7b': os.environ.get('LLAMA2_7B_IMAGE_URI'),
        'llama2:13b': os.environ.get('LLAMA2_13B_IMAGE_URI'),
        'codellama:7b': os.environ.get('CODELLAMA_7B_IMAGE_URI'),
        'codellama:13b': os.environ.get('CODELLAMA_13B_IMAGE_URI'),
        'mistral:7b': os.environ.get('MISTRAL_7B_IMAGE_URI')
    }
    
    # Instance type categorization
    gpu_instance_types = ['ml.g4dn.xlarge', 'ml.g4dn.2xlarge', 'ml.p3.2xlarge']
    large_cpu_types = ['ml.m5.2xlarge', 'ml.m5.4xlarge', 'ml.c5.4xlarge']
    
    config = {
        'container_image': model_images.get(model_id),
        'launch_type': 'FARGATE',  # Default to Fargate
        'task_definition': os.environ['CPU_TASK_DEFINITION_ARN']
    }
    
    # GPU instances require EC2 launch type
    if instance_type in gpu_instance_types:
        config.update({
            'launch_type': 'EC2',
            'task_definition': os.environ['GPU_TASK_DEFINITION_ARN'],
            'placement_constraints': [
                {
                    'type': 'memberOf',
                    'expression': f'attribute:ecs.instance-type == {instance_type}'
                }
            ]
        })
    
    # Large CPU instances might benefit from EC2
    elif instance_type in large_cpu_types:
        config.update({
            'launch_type': 'EC2',
            'placement_constraints': [
                {
                    'type': 'memberOf',
                    'expression': f'attribute:ecs.instance-type == {instance_type}'
                }
            ]
        })
    
    return config

def delete_instance(instance_id, user_info):
    """Delete an instance and stop its ECS task"""
    try:
        instances_table = dynamodb.Table(os.environ['INSTANCES_TABLE_NAME'])
        
        # Get instance information
        response = instances_table.get_item(Key={'id': instance_id})
        
        if 'Item' not in response:
            return {
                'statusCode': 404,
                'headers': cors_headers(),
                'body': json.dumps({'error': 'Instance not found'})
            }
        
        instance = response['Item']
        
        # Permission check (admin or owner only)
        if instance['user_id'] != user_info['user_id'] and 'Administrators' not in user_info['groups']:
            return {
                'statusCode': 403,
                'headers': cors_headers(),
                'body': json.dumps({'error': 'Access denied'})
            }
        
        # Stop ECS task
        if instance.get('task_arn'):
            try:
                ecs_client.stop_task(
                    cluster=os.environ['ECS_CLUSTER_NAME'],
                    task=instance['task_arn'],
                    reason=f'User requested deletion of instance {instance_id}'
                )
                logger.info(f"Stopped ECS task {instance['task_arn']}")
            except Exception as e:
                logger.warning(f"Failed to stop ECS task: {str(e)}")
        
        # Delete instance from DynamoDB
        instances_table.delete_item(Key={'id': instance_id})
        
        logger.info(f"Deleted instance {instance_id}")
        
        return {
            'statusCode': 204,
            'headers': cors_headers()
        }
        
    except Exception as e:
        logger.error(f"Error deleting instance: {str(e)}")
        return {
            'statusCode': 500,
            'headers': cors_headers(),
            'body': json.dumps({'error': 'Failed to delete instance', 'message': str(e)})
        }

def list_instances(user_info):
    """List user's instances"""
    try:
        instances_table = dynamodb.Table(os.environ['INSTANCES_TABLE_NAME'])
        
        if 'Administrators' in user_info['groups']:
            # Admin can see all instances
            response = instances_table.scan()
        else:
            # Regular users can only see their own instances
            response = instances_table.scan(
                FilterExpression=boto3.dynamodb.conditions.Attr('user_id').eq(user_info['user_id'])
            )
        
        instances = []
        for item in response['Items']:
            instances.append({
                'id': item['id'],
                'modelId': item['model_id'],
                'modelName': item['model_name'],
                'status': item['status'],
                'instanceType': item['instance_type'],
                'estimatedCost': item['estimated_cost'],
                'endpoint': item['endpoint'],
                'startedAt': item['created_at']
            })
        
        return {
            'statusCode': 200,
            'headers': cors_headers(),
            'body': json.dumps(instances)
        }
        
    except Exception as e:
        logger.error(f"Error listing instances: {str(e)}")
        return {
            'statusCode': 500,
            'headers': cors_headers(),
            'body': json.dumps({'error': 'Failed to list instances', 'message': str(e)})
        }

def get_instance(instance_id, user_info):
    """Get specific instance details"""
    try:
        instances_table = dynamodb.Table(os.environ['INSTANCES_TABLE_NAME'])
        
        response = instances_table.get_item(Key={'id': instance_id})
        
        if 'Item' not in response:
            return {
                'statusCode': 404,
                'headers': cors_headers(),
                'body': json.dumps({'error': 'Instance not found'})
            }
        
        instance = response['Item']
        
        # Permission check
        if instance['user_id'] != user_info['user_id'] and 'Administrators' not in user_info['groups']:
            return {
                'statusCode': 403,
                'headers': cors_headers(),
                'body': json.dumps({'error': 'Access denied'})
            }
        
        # Update status from ECS if needed
        if instance.get('task_arn'):
            current_status = get_ecs_task_status(instance['task_arn'])
            if current_status != instance['status']:
                # Update status in DynamoDB
                instances_table.update_item(
                    Key={'id': instance_id},
                    UpdateExpression='SET #status = :status, updated_at = :updated_at',
                    ExpressionAttributeNames={'#status': 'status'},
                    ExpressionAttributeValues={
                        ':status': current_status,
                        ':updated_at': datetime.now(timezone.utc).isoformat()
                    }
                )
                instance['status'] = current_status
        
        return {
            'statusCode': 200,
            'headers': cors_headers(),
            'body': json.dumps({
                'id': instance['id'],
                'modelId': instance['model_id'],
                'modelName': instance['model_name'],
                'status': instance['status'],
                'instanceType': instance['instance_type'],
                'estimatedCost': instance['estimated_cost'],
                'endpoint': instance['endpoint'],
                'startedAt': instance['created_at'],
                'updatedAt': instance.get('updated_at', instance['created_at'])
            })
        }
        
    except Exception as e:
        logger.error(f"Error getting instance: {str(e)}")
        return {
            'statusCode': 500,
            'headers': cors_headers(),
            'body': json.dumps({'error': 'Failed to get instance', 'message': str(e)})
        }

def get_ecs_task_status(task_arn):
    """Get current ECS task status"""
    try:
        response = ecs_client.describe_tasks(
            cluster=os.environ['ECS_CLUSTER_NAME'],
            tasks=[task_arn]
        )
        
        if not response['tasks']:
            return 'stopped'
        
        task = response['tasks'][0]
        last_status = task.get('lastStatus', '').lower()
        
        # Map ECS status to application status
        status_mapping = {
            'pending': 'starting',
            'running': 'running',
            'stopping': 'stopping',
            'stopped': 'stopped'
        }
        
        return status_mapping.get(last_status, 'unknown')
        
    except Exception as e:
        logger.warning(f"Failed to get ECS task status: {str(e)}")
        return 'unknown'

def get_estimated_cost(instance_type):
    """Calculate estimated cost based on instance type"""
    cost_mapping = {
        'ml.m5.large': '$0.12/hour',
        'ml.m5.xlarge': '$0.24/hour',
        'ml.m5.2xlarge': '$0.48/hour',
        'ml.g4dn.xlarge': '$0.71/hour',
        'ml.g4dn.2xlarge': '$1.42/hour',
        'ml.p3.2xlarge': '$3.06/hour'
    }
    
    return cost_mapping.get(instance_type, '$0.00/hour')

def cors_headers():
    """Return CORS headers"""
    return {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,Authorization',
        'Access-Control-Allow-Methods': 'GET,POST,DELETE,OPTIONS'
    }
