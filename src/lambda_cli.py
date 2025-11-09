"""
Lambda handler using Cloud Custodian CLI (Subprocess Mode)

This approach executes the 'custodian' CLI command as a subprocess.
Benefits:
- Familiar to users who know the CLI
- Can use all CLI features and flags
- Easy to test locally

Drawbacks:
- Subprocess overhead
- Less Pythonic
- Harder to handle complex outputs
"""

import json
import logging
import os
import subprocess
import tempfile
from pathlib import Path
from typing import Dict, Any, List

import boto3

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)


def download_policy_from_s3(bucket: str, key: str, local_path: str) -> str:
    """Download policy file from S3 to local path"""
    s3 = boto3.client('s3')
    s3.download_file(bucket, key, local_path)
    logger.info(f"Downloaded policy from s3://{bucket}/{key} to {local_path}")
    return local_path


def execute_custodian_cli(
    policy_file: str,
    output_dir: str,
    region: str = None,
    dryrun: bool = False,
    verbose: bool = False,
    additional_args: List[str] = None
) -> Dict[str, Any]:
    """
    Execute Cloud Custodian using CLI command
    
    Args:
        policy_file: Path to policy YAML file
        output_dir: Directory for output files
        region: AWS region
        dryrun: Run in dry-run mode
        verbose: Enable verbose logging
        additional_args: Additional CLI arguments
    
    Returns:
        Dictionary with execution results
    """
    results = {
        'success': False,
        'stdout': '',
        'stderr': '',
        'return_code': None
    }
    
    try:
        # Build custodian command
        cmd = [
            'custodian', 'run',
            '--output-dir', output_dir,
            '--cache-period', '0'  # Disable caching for Lambda
        ]
        
        if region:
            cmd.extend(['--region', region])
        
        if dryrun:
            cmd.append('--dryrun')
        
        if verbose:
            cmd.extend(['--verbose'])
        
        if additional_args:
            cmd.extend(additional_args)
        
        # Add policy file last
        cmd.append(policy_file)
        
        logger.info(f"Executing command: {' '.join(cmd)}")
        
        # Execute command
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=840  # 14 minutes (Lambda max is 15 min)
        )
        
        results['stdout'] = result.stdout
        results['stderr'] = result.stderr
        results['return_code'] = result.returncode
        results['success'] = result.returncode == 0
        
        # Log output
        if result.stdout:
            logger.info(f"Custodian STDOUT:\n{result.stdout}")
        
        if result.stderr:
            logger.warning(f"Custodian STDERR:\n{result.stderr}")
        
        if result.returncode != 0:
            logger.error(f"Custodian command failed with return code {result.returncode}")
        else:
            logger.info("Custodian execution completed successfully")
        
        return results
        
    except subprocess.TimeoutExpired:
        error_msg = "Custodian execution timed out"
        logger.error(error_msg)
        results['stderr'] = error_msg
        return results
        
    except Exception as e:
        error_msg = f"Error executing custodian CLI: {str(e)}"
        logger.error(error_msg)
        results['stderr'] = error_msg
        return results


def parse_custodian_output(output_dir: str) -> Dict[str, Any]:
    """
    Parse Custodian output files to extract results
    
    Args:
        output_dir: Directory containing Custodian output
    
    Returns:
        Dictionary with parsed results
    """
    summary = {
        'policies': [],
        'total_resources': 0
    }
    
    try:
        output_path = Path(output_dir)
        
        # Each policy creates a subdirectory
        for policy_dir in output_path.iterdir():
            if policy_dir.is_dir():
                policy_name = policy_dir.name
                resources_file = policy_dir / 'resources.json'
                
                if resources_file.exists():
                    with open(resources_file, 'r') as f:
                        resources = json.load(f)
                        resource_count = len(resources) if isinstance(resources, list) else 0
                        
                        summary['policies'].append({
                            'name': policy_name,
                            'resource_count': resource_count
                        })
                        summary['total_resources'] += resource_count
                        
                        logger.info(f"Policy '{policy_name}' found {resource_count} resources")
        
        return summary
        
    except Exception as e:
        logger.error(f"Error parsing output: {str(e)}")
        return summary


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for EventBridge triggered execution using CLI
    
    Event format options:
    1. Policy in S3:
       {
         "policy_source": "s3",
         "bucket": "my-bucket",
         "key": "policies/my-policy.yml",
         "dryrun": false,
         "verbose": true
       }
    
    2. Policy in Lambda package:
       {
         "policy_source": "file",
         "policy_path": "/var/task/policies/sample-policies.yml",
         "dryrun": false
       }
    
    3. With additional CLI arguments:
       {
         "policy_source": "file",
         "policy_path": "/var/task/policies/sample-policies.yml",
         "additional_args": ["--metrics", "aws"]
       }
    """
    logger.info(f"Received event: {json.dumps(event, default=str)}")
    
    try:
        # Extract parameters from event
        policy_source = event.get('policy_source', 'file')
        dryrun = event.get('dryrun', False)
        verbose = event.get('verbose', True)
        region = event.get('region', os.environ.get('AWS_REGION', 'us-east-1'))
        additional_args = event.get('additional_args', [])
        
        # Create temporary directories
        with tempfile.TemporaryDirectory() as temp_dir:
            output_dir = os.path.join(temp_dir, 'output')
            os.makedirs(output_dir, exist_ok=True)
            
            # Determine policy file path
            if policy_source == 's3':
                bucket = event.get('bucket', os.environ.get('POLICY_BUCKET'))
                key = event.get('key', os.environ.get('POLICY_KEY'))
                
                if not bucket or not key:
                    raise ValueError("S3 bucket and key must be provided")
                
                policy_file = os.path.join(temp_dir, 'policy.yml')
                download_policy_from_s3(bucket, key, policy_file)
                
            else:  # file
                policy_file = event.get('policy_path', os.environ.get('POLICY_PATH', '/var/task/policies/sample-policies.yml'))
                
                if not os.path.exists(policy_file):
                    raise FileNotFoundError(f"Policy file not found: {policy_file}")
            
            logger.info(f"Using policy file: {policy_file}")
            
            # Execute Custodian CLI
            execution_results = execute_custodian_cli(
                policy_file=policy_file,
                output_dir=output_dir,
                region=region,
                dryrun=dryrun,
                verbose=verbose,
                additional_args=additional_args
            )
            
            # Parse output files
            if execution_results['success']:
                summary = parse_custodian_output(output_dir)
            else:
                summary = {'error': 'Execution failed'}
            
            return {
                'statusCode': 200 if execution_results['success'] else 500,
                'body': json.dumps({
                    'message': 'Cloud Custodian CLI execution completed',
                    'execution': {
                        'success': execution_results['success'],
                        'return_code': execution_results['return_code']
                    },
                    'summary': summary,
                    'stdout': execution_results['stdout'][-2000:] if execution_results['stdout'] else '',  # Last 2000 chars
                    'stderr': execution_results['stderr'][-2000:] if execution_results['stderr'] else ''
                }, default=str)
            }
    
    except Exception as e:
        logger.error(f"Lambda execution failed: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Cloud Custodian CLI execution failed',
                'error': str(e)
            })
        }
