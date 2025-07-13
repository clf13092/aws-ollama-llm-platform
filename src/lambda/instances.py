"""
AWS Ollama Platform - Instances Management Lambda Function

Handles instance listing, monitoring, and log retrieval operations.
Provides user access control for instance management.
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
dynamodb = boto3.resource('dynamodb')
logs_client = boto3.client('logs')
ecs_client = boto3.client('ecs')


def lambda_handler(event, context):
    """
    Main Lambda handler for instance management operations.
    
    Supported endpoints:
    - GET /instances
    - GET /instances/{id}
    - GET /instances/{id}/logs
    - GET /instances/{id}/status
    """
    try:
        http_method = event['httpMethod']
        path = event['path']
        user_info = get_user_info_from_context(event)
        
        logger.info(f"Processing {http_method} request to {path} for user {user_info['user_id']}")
        
        if path == '/instances' and http_method == 'GET':
            return list_instances(user_info)
        elif path.startswith('/instances/') and not path.count('/') > 2 and http_method == 'GET':
            instance_id = path.split('/')[-1]
            return get_instance(instance_id, user_info)
        elif path.endswith('/logs') and http_method == 'GET':
            instance_id = path.split('/')[-2]
            return get_instance_logs(instance_id, user_info)
        elif path.endswith('/status') and http_method == 'GET':
            instance_id = path.split('/')[-2]
            return get_instance_status(instance_id, user_info)
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


def list_instances(user_info):
    """List instances based on user permissions."""
    try:
        instances_table = dynamodb.Table(os.environ['INSTANCES_TABLE_NAME'])
        
        if 'Administrators' in user_info['groups']:
            # Administrators can see all instances
            response = instances_table.scan()
        else:
            # Regular users can only see their own instances
            response = instances_table.query(
                IndexName='UserIdIndex',
                KeyConditionExpression=boto3.dynamodb.conditions.Key('user_id').eq(user_info['user_id'])
            )
        
        instances = response.get('Items', [])
        
        # Sort instances by creation date (newest first)
        instances.sort(key=lambda x: x.get('created_at', ''), reverse=True)
        
        # Enrich instances with real-time status if possible
        for instance in instances:
            try:
                instance['real_time_status'] = get_ecs_service_status(instance)
            except Exception as e:
                logger.warning(f"Could not get real-time status for instance {instance['instance_id']}: {str(e)}")
                instance['real_time_status'] = instance.get('status', 'unknown')
        
        return create_success_response({
            'instances': instances,
            'count': len(instances),
            'user_filter': 'all' if 'Administrators' in user_info['groups'] else 'own'
        })
        
    except Exception as e:
        logger.error(f"Failed to list instances: {str(e)}")
        return create_error_response(500, 'Failed to retrieve instances')


def get_instance(instance_id, user_info):
    """Get detailed information about a specific instance."""
    try:
        instances_table = dynamodb.Table(os.environ['INSTANCES_TABLE_NAME'])
        response = instances_table.get_item(Key={'instance_id': instance_id})
        
        if 'Item' not in response:
            return create_error_response(404, 'Instance not found')
        
        instance = response['Item']
        
        # Check access permissions
        if instance['user_id'] != user_info['user_id'] and 'Administrators' not in user_info['groups']:
            return create_error_response(403, 'Access denied')
        
        # Add real-time status information
        try:
            instance['real_time_status'] = get_ecs_service_status(instance)
            instance['service_details'] = get_ecs_service_details(instance)
        except Exception as e:
            logger.warning(f"Could not get real-time info for instance {instance_id}: {str(e)}")
            instance['real_time_status'] = instance.get('status', 'unknown')
        
        # Add usage statistics
        instance['usage_stats'] = get_instance_usage_stats(instance_id)
        
        return create_success_response(instance)
        
    except Exception as e:
        logger.error(f"Failed to get instance {instance_id}: {str(e)}")
        return create_error_response(500, 'Failed to retrieve instance')


def get_instance_logs(instance_id, user_info):
    """Get logs for a specific instance."""
    try:
        # First check if user has access to this instance
        instances_table = dynamodb.Table(os.environ['INSTANCES_TABLE_NAME'])
        response = instances_table.get_item(Key={'instance_id': instance_id})
        
        if 'Item' not in response:
            return create_error_response(404, 'Instance not found')
        
        instance = response['Item']
        
        # Check access permissions
        if instance['user_id'] != user_info['user_id'] and 'Administrators' not in user_info['groups']:
            return create_error_response(403, 'Access denied')
        
        # Get logs from CloudWatch
        log_group_name = f"/ecs/{os.environ['ENVIRONMENT']}-ollama"
        log_stream_prefix = f"ollama-{instance_id[:8]}"
        
        try:
            # Get log streams for this instance
            streams_response = logs_client.describe_log_streams(
                logGroupName=log_group_name,
                logStreamNamePrefix=log_stream_prefix,
                orderBy='LastEventTime',
                descending=True,
                limit=5
            )
            
            logs = []
            for stream in streams_response.get('logStreams', []):
                try:
                    events_response = logs_client.get_log_events(
                        logGroupName=log_group_name,
                        logStreamName=stream['logStreamName'],
                        limit=100,
                        startFromHead=False
                    )
                    
                    for event in events_response.get('events', []):
                        logs.append({
                            'timestamp': datetime.fromtimestamp(event['timestamp'] / 1000, timezone.utc).isoformat(),
                            'message': event['message'],
                            'stream': stream['logStreamName']
                        })
                        
                except Exception as e:
                    logger.warning(f"Could not get events from stream {stream['logStreamName']}: {str(e)}")
            
            # Sort logs by timestamp (newest first)
            logs.sort(key=lambda x: x['timestamp'], reverse=True)
            
            return create_success_response({
                'logs': logs[:100],  # Limit to 100 most recent logs
                'instance_id': instance_id,
                'log_group': log_group_name,
                'stream_prefix': log_stream_prefix
            })
            
        except logs_client.exceptions.ResourceNotFoundException:
            # Log group doesn't exist yet or no logs available
            return create_success_response({
                'logs': [],
                'instance_id': instance_id,
                'message': 'No logs available yet'
            })
            
    except Exception as e:
        logger.error(f"Failed to get logs for instance {instance_id}: {str(e)}")
        return create_error_response(500, 'Failed to retrieve logs')


def get_instance_status(instance_id, user_info):
    """Get real-time status of a specific instance."""
    try:
        # Check access permissions first
        instances_table = dynamodb.Table(os.environ['INSTANCES_TABLE_NAME'])
        response = instances_table.get_item(Key={'instance_id': instance_id})
        
        if 'Item' not in response:
            return create_error_response(404, 'Instance not found')
        
        instance = response['Item']
        
        if instance['user_id'] != user_info['user_id'] and 'Administrators' not in user_info['groups']:
            return create_error_response(403, 'Access denied')
        
        # Get real-time status from ECS
        status_info = {
            'instance_id': instance_id,
            'stored_status': instance.get('status', 'unknown'),
            'real_time_status': get_ecs_service_status(instance),
            'service_details': get_ecs_service_details(instance),
            'last_updated': datetime.now(timezone.utc).isoformat()
        }
        
        # Update stored status if different
        if status_info['real_time_status'] != status_info['stored_status']:
            try:
                instances_table.update_item(
                    Key={'instance_id': instance_id},
                    UpdateExpression='SET #status = :status, last_status_update = :timestamp',
                    ExpressionAttributeNames={'#status': 'status'},
                    ExpressionAttributeValues={
                        ':status': status_info['real_time_status'],
                        ':timestamp': status_info['last_updated']
                    }
                )
                logger.info(f"Updated status for instance {instance_id} from {status_info['stored_status']} to {status_info['real_time_status']}")
            except Exception as e:
                logger.warning(f"Could not update stored status for instance {instance_id}: {str(e)}")
        
        return create_success_response(status_info)
        
    except Exception as e:
        logger.error(f"Failed to get status for instance {instance_id}: {str(e)}")
        return create_error_response(500, 'Failed to retrieve instance status')


def get_ecs_service_status(instance):
    """Get real-time ECS service status."""
    try:
        if 'service_name' not in instance or 'ecs_service_arn' not in instance:
            return instance.get('status', 'unknown')
        
        cluster_name = os.environ.get('ECS_CLUSTER_NAME', f"{os.environ['ENVIRONMENT']}-ollama-cluster")
        
        response = ecs_client.describe_services(
            cluster=cluster_name,
            services=[instance['service_name']]
        )
        
        if not response.get('services'):
            return 'stopped'
        
        service = response['services'][0]
        service_status = service.get('status', 'UNKNOWN')
        
        # Map ECS status to our status
        if service_status == 'ACTIVE':
            desired_count = service.get('desiredCount', 0)
            running_count = service.get('runningCount', 0)
            
            if desired_count == 0:
                return 'stopped'
            elif running_count == desired_count:
                return 'running'
            elif running_count > 0:
                return 'starting'
            else:
                return 'pending'
        elif service_status == 'DRAINING':
            return 'stopping'
        else:
            return 'unknown'
            
    except Exception as e:
        logger.warning(f"Could not get ECS service status: {str(e)}")
        return instance.get('status', 'unknown')


def get_ecs_service_details(instance):
    """Get detailed ECS service information."""
    try:
        if 'service_name' not in instance:
            return {}
        
        cluster_name = os.environ.get('ECS_CLUSTER_NAME', f"{os.environ['ENVIRONMENT']}-ollama-cluster")
        
        response = ecs_client.describe_services(
            cluster=cluster_name,
            services=[instance['service_name']]
        )
        
        if not response.get('services'):
            return {'error': 'Service not found'}
        
        service = response['services'][0]
        
        return {
            'service_arn': service.get('serviceArn'),
            'task_definition': service.get('taskDefinition'),
            'desired_count': service.get('desiredCount', 0),
            'running_count': service.get('runningCount', 0),
            'pending_count': service.get('pendingCount', 0),
            'platform_version': service.get('platformVersion'),
            'launch_type': service.get('launchType'),
            'created_at': service.get('createdAt').isoformat() if service.get('createdAt') else None
        }
        
    except Exception as e:
        logger.warning(f"Could not get ECS service details: {str(e)}")
        return {'error': str(e)}


def get_instance_usage_stats(instance_id):
    """Get usage statistics for an instance (placeholder for future implementation)."""
    try:
        # This would integrate with CloudWatch metrics in a full implementation
        # For now, return basic usage information
        return {
            'uptime_hours': 0,
            'api_requests': 0,
            'cpu_usage_avg': 0,
            'memory_usage_avg': 0,
            'last_request': None,
            'note': 'Usage statistics will be available after CloudWatch integration'
        }
        
    except Exception as e:
        logger.warning(f"Could not get usage stats for instance {instance_id}: {str(e)}")
        return {}


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