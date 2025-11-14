"""
Lambda handler using Cloud Custodian as a Python library (Native Mode)

Event-driven execution with policy mapping and validation.
The Lambda function:
1. Receives EventBridge events (S3 CloudTrail API calls)
2. Validates the event and extracts event information
3. Looks up the appropriate policy from policy mapping configuration
4. Downloads the policy file from S3
5. Executes the specific Cloud Custodian policy

Benefits:
- Event-driven architecture
- Dynamic policy selection based on event type
- Centralized policy management in S3
- Better error handling and logging
- Direct access to Custodian objects
"""

import json
import logging
import os
from typing import Dict, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Import custom modules
from validator import EventValidator, validate_policy_mapping_config
from policy_executor import PolicyExecutor

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for EventBridge triggered execution
    
    This handler processes EventBridge events, validates them, determines which
    Cloud Custodian policy to execute, and runs the policy.
    
    Event format (from EventBridge):
    {
      "version": "0",
      "id": "...",
      "detail-type": "AWS API Call via CloudTrail",
      "source": "aws.s3",
      "account": "...",
      "time": "...",
      "region": "us-east-1",
      "resources": [],
      "detail": {
        "eventVersion": "1.08",
        "eventTime": "...",
        "eventName": "CreateBucket",
        "eventSource": "s3.amazonaws.com",
        "requestParameters": {
          "bucketName": "my-bucket"
        },
        ...
      }
    }
    
    Environment Variables:
    - POLICY_MAPPING_BUCKET: S3 bucket containing policy mapping configuration
    - POLICY_MAPPING_KEY: S3 key for policy mapping JSON file
    - AWS_REGION: AWS region (set by Lambda automatically)
    - DRYRUN: Set to 'true' to run in dry-run mode (optional)
    """
    logger.info(f"Lambda invocation started")
    logger.info(f"Event received: {json.dumps(event, default=str)}")
    
    # Check if this is a test invocation
    if not event or 'detail-type' not in event:
        logger.warning("Received test or invalid event format")
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Lambda function is healthy and ready to process EventBridge events',
                'note': 'This Lambda is designed to be triggered by EventBridge S3 CloudTrail events',
                'expected_event_format': {
                    'detail-type': 'AWS API Call via CloudTrail',
                    'source': 'aws.s3',
                    'detail': {
                        'eventName': 'CreateBucket|PutBucketAcl|...',
                        'eventSource': 's3.amazonaws.com',
                        'requestParameters': {'bucketName': 'bucket-name'}
                    }
                }
            })
        }
    
    try:
        # Get configuration from environment variables
        policy_mapping_bucket = os.environ.get('POLICY_MAPPING_BUCKET')
        policy_mapping_key = os.environ.get('POLICY_MAPPING_KEY', 'config/policy-mapping.json')
        region = os.environ.get('AWS_REGION', 'us-east-1')
        dryrun = os.environ.get('DRYRUN', 'false').lower() == 'true'
        
        if not policy_mapping_bucket:
            raise ValueError("POLICY_MAPPING_BUCKET environment variable is not set")
        
        logger.info(f"Configuration: bucket={policy_mapping_bucket}, "
                   f"key={policy_mapping_key}, region={region}, dryrun={dryrun}")
        
        # Initialize policy executor
        executor = PolicyExecutor(region=region)
        
        # Download policy mapping configuration from S3
        logger.info("Downloading policy mapping configuration...")
        policy_mapping = executor.download_policy_mapping(
            bucket=policy_mapping_bucket,
            key=policy_mapping_key
        )
        
        # Validate policy mapping configuration
        validate_policy_mapping_config(policy_mapping)
        
        # Initialize event validator
        validator = EventValidator(policy_mapping)
        
        # Validate event and get policy details
        logger.info("Validating event and determining policies...")
        policy_details = validator.get_policy_details(event)
        
        event_info = policy_details['event_info']
        policies = policy_details['policies']
        
        logger.info(f"Event validated: {event_info['event_name']}")
        logger.info(f"Found {len(policies)} policies to execute")
        
        # Execute all policies mapped to this event
        execution_results = []
        for policy_config in policies:
            logger.info(f"Executing policy: {policy_config['policy_name']} from {policy_config['source_file']}")
            
            try:
                execution_result = executor.execute_policy(
                    policy_config=policy_config,
                    event_info=event_info,
                    dryrun=dryrun
                )
                
                execution_results.append({
                    'policy_name': policy_config['policy_name'],
                    'status': 'success',
                    'result': execution_result
                })
                logger.info(f"Policy {policy_config['policy_name']} executed successfully")
                
            except Exception as policy_error:
                logger.error(f"Policy {policy_config['policy_name']} execution failed: {str(policy_error)}")
                execution_results.append({
                    'policy_name': policy_config['policy_name'],
                    'status': 'failed',
                    'error': str(policy_error)
                })
        
        logger.info(f"All policies execution completed. Success: {sum(1 for r in execution_results if r['status'] == 'success')}/{len(policies)}")
        
        # Return success response
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Executed {len(policies)} Cloud Custodian policies',
                'event_info': {
                    'event_name': event_info['event_name'],
                    'event_time': event_info['event_time'],
                    'aws_region': event_info.get('aws_region', 'us-east-1'),
                },
                'policies_executed': len(policies),
                'execution_results': execution_results,
                'dryrun': dryrun,
            }, default=str)
        }
    
    except ValueError as ve:
        # Validation or configuration errors
        logger.error(f"Validation error: {str(ve)}")
        return {
            'statusCode': 400,
            'body': json.dumps({
                'message': 'Event validation or configuration error',
                'error': str(ve),
                'error_type': 'ValidationError'
            })
        }
    
    except Exception as e:
        # Unexpected errors
        logger.error(f"Lambda execution failed: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Cloud Custodian execution failed',
                'error': str(e),
                'error_type': type(e).__name__
            })
        }


# For backward compatibility and manual testing
def load_policy_from_s3(bucket: str, key: str) -> dict:
    """Load policy file from S3 (legacy function for backward compatibility)"""
    import boto3
    import yaml
    
    s3 = boto3.client('s3')
    response = s3.get_object(Bucket=bucket, Key=key)
    policy_content = response['Body'].read().decode('utf-8')
    return yaml.safe_load(policy_content)
