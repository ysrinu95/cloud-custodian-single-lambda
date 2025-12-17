"""
Cloud Custodian Mailer Lambda Function
Processes messages from SQS queue and publishes to SNS topic
"""

import json
import logging
import os
import boto3
from datetime import datetime

# Configure logging
LOG_LEVEL = os.environ.get('LOG_LEVEL', 'INFO')
logger = logging.getLogger()
logger.setLevel(getattr(logging, LOG_LEVEL))

# Initialize AWS clients
sns_client = boto3.client('sns')
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN')


def format_message(custodian_message):
    """
    Format Cloud Custodian message for email notification
    
    Args:
        custodian_message: Message from Cloud Custodian policy
        
    Returns:
        Formatted string for email
    """
    try:
        # Extract key information
        policy_name = custodian_message.get('policy', {}).get('name', 'Unknown Policy')
        account_id = custodian_message.get('account_id', 'Unknown')
        region = custodian_message.get('region', 'Unknown')
        resources = custodian_message.get('resources', [])
        action = custodian_message.get('action', {})
        event = custodian_message.get('event', {})
        
        # Build formatted message
        lines = [
            "=" * 80,
            f"Cloud Custodian Policy Alert: {policy_name}",
            "=" * 80,
            "",
            f"Account ID: {account_id}",
            f"Region: {region}",
            f"Timestamp: {datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')}",
            "",
        ]
        
        # Add event information if available
        if event:
            event_name = event.get('detail', {}).get('eventName', 'N/A')
            event_source = event.get('detail', {}).get('eventSource', 'N/A')
            lines.extend([
                "Event Details:",
                f"  Event Name: {event_name}",
                f"  Event Source: {event_source}",
                "",
            ])
        
        # Add resource information
        lines.append(f"Resources Affected: {len(resources)}")
        lines.append("")
        
        for idx, resource in enumerate(resources[:10], 1):  # Limit to first 10 resources
            lines.append(f"Resource {idx}:")
            
            # Try to extract meaningful resource identifiers
            resource_id = (
                resource.get('InstanceId') or
                resource.get('LoadBalancerArn') or
                resource.get('BucketName') or
                resource.get('ImageId') or
                resource.get('Name') or
                resource.get('ARN') or
                'Unknown'
            )
            lines.append(f"  ID: {resource_id}")
            
            # Add resource type if available
            resource_type = (
                resource.get('ResourceType') or
                ('EC2 Instance' if 'InstanceId' in resource else '') or
                ('Load Balancer' if 'LoadBalancerArn' in resource else '') or
                ('S3 Bucket' if 'BucketName' in resource else '') or
                ('AMI' if 'ImageId' in resource else '') or
                'Unknown Type'
            )
            lines.append(f"  Type: {resource_type}")
            
            # Add tags if available
            tags = resource.get('Tags', [])
            if tags and isinstance(tags, list):
                lines.append("  Tags:")
                for tag in tags[:5]:  # Limit to first 5 tags
                    if isinstance(tag, dict):
                        key = tag.get('Key', 'N/A')
                        value = tag.get('Value', 'N/A')
                        lines.append(f"    {key}: {value}")
            
            lines.append("")
        
        if len(resources) > 10:
            lines.append(f"... and {len(resources) - 10} more resources")
            lines.append("")
        
        # Add action information
        if action:
            action_type = action.get('type', 'N/A')
            lines.extend([
                f"Action Taken: {action_type}",
                "",
            ])
        
        lines.extend([
            "=" * 80,
            "This is an automated notification from Cloud Custodian.",
            "=" * 80,
        ])
        
        return "\n".join(lines)
        
    except Exception as e:
        logger.error(f"Error formatting message: {e}")
        return json.dumps(custodian_message, indent=2)


def handler(event, context):
    """
    Lambda handler for processing SQS messages and publishing to SNS
    
    Args:
        event: SQS event with Cloud Custodian messages
        context: Lambda context
        
    Returns:
        Response with processing status
    """
    logger.info(f"Processing {len(event.get('Records', []))} messages from SQS")
    
    if not SNS_TOPIC_ARN:
        logger.error("SNS_TOPIC_ARN environment variable not set")
        return {
            'statusCode': 500,
            'body': json.dumps('SNS_TOPIC_ARN not configured')
        }
    
    successful = 0
    failed = 0
    
    for record in event.get('Records', []):
        try:
            # Parse SQS message body
            message_body = json.loads(record['body'])
            logger.debug(f"Processing message: {json.dumps(message_body, default=str)}")
            
            # Format message for email
            formatted_message = format_message(message_body)
            
            # Extract policy name for subject
            policy_name = message_body.get('policy', {}).get('name', 'Cloud Custodian Alert')
            account_id = message_body.get('account_id', 'Unknown')
            resource_count = len(message_body.get('resources', []))
            
            subject = f"🚨 Cloud Custodian: {policy_name} ({resource_count} resources in {account_id})"
            
            # Publish to SNS
            response = sns_client.publish(
                TopicArn=SNS_TOPIC_ARN,
                Subject=subject[:100],  # SNS subject limit is 100 characters
                Message=formatted_message
            )
            
            logger.info(f"Published message to SNS. MessageId: {response['MessageId']}")
            successful += 1
            
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse message body: {e}")
            logger.error(f"Message body: {record.get('body')}")
            failed += 1
            
        except Exception as e:
            logger.error(f"Error processing message: {e}")
            logger.error(f"Record: {json.dumps(record, default=str)}")
            failed += 1
    
    logger.info(f"Processing complete. Successful: {successful}, Failed: {failed}")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'successful': successful,
            'failed': failed,
            'total': len(event.get('Records', []))
        })
    }
