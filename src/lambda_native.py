"""
Lambda handler using Cloud Custodian as a Python library (Native Mode)

This approach imports Cloud Custodian as a library and executes policies programmatically.
Benefits:
- More Pythonic and maintainable
- Better error handling and logging
- Direct access to Custodian objects
- No subprocess overhead
"""

import json
import logging
import os
import tempfile
from pathlib import Path
from typing import Dict, Any

import yaml
from c7n.config import Config
from c7n.policy import PolicyCollection
from c7n import policy

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)


def load_policy_from_s3(bucket: str, key: str) -> dict:
    """Load policy file from S3"""
    import boto3
    
    s3 = boto3.client('s3')
    response = s3.get_object(Bucket=bucket, Key=key)
    policy_content = response['Body'].read().decode('utf-8')
    return yaml.safe_load(policy_content)


def load_policy_from_file(policy_path: str) -> dict:
    """Load policy file from local path or Lambda package"""
    with open(policy_path, 'r') as f:
        return yaml.safe_load(f)


def execute_custodian_policy(policy_data: dict, output_dir: str, region: str = None) -> Dict[str, Any]:
    """
    Execute Cloud Custodian policy using the library
    
    Args:
        policy_data: Dictionary containing policy configuration
        output_dir: Directory for output files
        region: AWS region (optional, defaults to Lambda region)
    
    Returns:
        Dictionary with execution results
    """
    results = {
        'policies_executed': [],
        'resources_found': {},
        'errors': []
    }
    
    try:
        # Set up configuration
        config = Config.empty(
            region=region or os.environ.get('AWS_REGION', 'us-east-1'),
            output_dir=output_dir,
            log_group=os.environ.get('LOG_GROUP', None),
            metrics_enabled=False,
            account_id=os.environ.get('ACCOUNT_ID'),
        )
        
        # Load policies
        policies = PolicyCollection.from_data(policy_data, config)
        
        # Execute each policy
        for p in policies:
            logger.info(f"Executing policy: {p.name}")
            
            try:
                # Run the policy
                resources = p.run()
                
                results['policies_executed'].append(p.name)
                results['resources_found'][p.name] = len(resources)
                
                logger.info(f"Policy '{p.name}' found {len(resources)} resources")
                
                # Log sample of resources (first 5)
                if resources:
                    logger.info(f"Sample resources from '{p.name}': {json.dumps(resources[:5], default=str)}")
                
            except Exception as e:
                error_msg = f"Error executing policy '{p.name}': {str(e)}"
                logger.error(error_msg)
                results['errors'].append(error_msg)
        
        return results
        
    except Exception as e:
        error_msg = f"Error in policy execution: {str(e)}"
        logger.error(error_msg)
        results['errors'].append(error_msg)
        return results


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for EventBridge triggered execution
    
    Event format options:
    1. Policy in S3:
       {
         "policy_source": "s3",
         "bucket": "my-bucket",
         "key": "policies/my-policy.yml"
       }
    
    2. Policy in Lambda package:
       {
         "policy_source": "file",
         "policy_path": "/var/task/policies/sample-policies.yml"
       }
    
    3. Policy inline:
       {
         "policy_source": "inline",
         "policy": {
           "policies": [...]
         }
       }
    """
    logger.info(f"Received event: {json.dumps(event, default=str)}")
    
    try:
        # Determine policy source
        policy_source = event.get('policy_source', 'file')
        
        # Load policy based on source
        if policy_source == 's3':
            bucket = event.get('bucket', os.environ.get('POLICY_BUCKET'))
            key = event.get('key', os.environ.get('POLICY_KEY'))
            
            if not bucket or not key:
                raise ValueError("S3 bucket and key must be provided")
            
            logger.info(f"Loading policy from S3: s3://{bucket}/{key}")
            policy_data = load_policy_from_s3(bucket, key)
            
        elif policy_source == 'inline':
            logger.info("Using inline policy")
            policy_data = event.get('policy')
            
            if not policy_data:
                raise ValueError("Inline policy must be provided")
                
        else:  # file
            policy_path = event.get('policy_path', os.environ.get('POLICY_PATH', '/var/task/policies/sample-policies.yml'))
            
            logger.info(f"Loading policy from file: {policy_path}")
            policy_data = load_policy_from_file(policy_path)
        
        # Create temporary output directory
        with tempfile.TemporaryDirectory() as output_dir:
            logger.info(f"Using output directory: {output_dir}")
            
            # Execute policies
            results = execute_custodian_policy(
                policy_data=policy_data,
                output_dir=output_dir,
                region=event.get('region', os.environ.get('AWS_REGION'))
            )
            
            logger.info(f"Execution completed: {json.dumps(results, default=str)}")
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Cloud Custodian policies executed successfully',
                    'results': results
                }, default=str)
            }
    
    except Exception as e:
        logger.error(f"Lambda execution failed: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Cloud Custodian execution failed',
                'error': str(e)
            })
        }
