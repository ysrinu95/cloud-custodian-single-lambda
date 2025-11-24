"""
Lambda Handler for Cross-Account Cloud Custodian Execution

Main entry point for processing EventBridge events from member accounts
and executing Cloud Custodian policies with cross-account role assumption.
"""

import json
import logging
import os
import boto3
from typing import Dict, Any
from cross_account_executor import (
    CrossAccountExecutor,
    extract_account_from_event,
    extract_region_from_event
)
from validator import validate_event

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.getenv('LOG_LEVEL', 'INFO'))

# Environment variables
POLICY_BUCKET = os.getenv('POLICY_BUCKET')
ACCOUNT_MAPPING_KEY = os.getenv('ACCOUNT_MAPPING_KEY', 'config/account-policy-mapping.json')


def load_account_policy_mapping() -> Dict[str, Any]:
    """
    Load account-specific policy mapping from S3
    
    Returns:
        Dict containing account policy mappings
    """
    s3 = boto3.client('s3')
    
    try:
        logger.info(f"Loading account policy mapping from s3://{POLICY_BUCKET}/{ACCOUNT_MAPPING_KEY}")
        
        response = s3.get_object(
            Bucket=POLICY_BUCKET,
            Key=ACCOUNT_MAPPING_KEY
        )
        
        mapping = json.loads(response['Body'].read().decode('utf-8'))
        logger.info(f"Loaded mapping for {len(mapping.get('account_mapping', {}))} accounts")
        
        return mapping
        
    except Exception as e:
        logger.error(f"Failed to load account policy mapping: {str(e)}")
        raise


def load_policy_from_s3(policy_name: str) -> Dict[str, Any]:
    """
    Load Cloud Custodian policy YAML from S3
    
    Args:
        policy_name: Name of the policy file (without .yml extension)
        
    Returns:
        Dict containing policy configuration
    """
    import yaml
    
    s3 = boto3.client('s3')
    policy_key = f"policies/{policy_name}.yml"
    
    try:
        logger.info(f"Loading policy from s3://{POLICY_BUCKET}/{policy_key}")
        
        response = s3.get_object(
            Bucket=POLICY_BUCKET,
            Key=policy_key
        )
        
        policy_yaml = response['Body'].read().decode('utf-8')
        policy_config = yaml.safe_load(policy_yaml)
        
        # Extract first policy if it's a list
        if 'policies' in policy_config:
            return policy_config['policies'][0]
        
        return policy_config
        
    except Exception as e:
        logger.error(f"Failed to load policy {policy_name}: {str(e)}")
        raise


def get_policies_for_event(account_id: str, event_name: str, policy_mapping: Dict[str, Any]) -> list:
    """
    Get list of policies to execute for a given account and event
    Uses two-tier lookup: account-specific policies first, then global policies
    
    Args:
        account_id: AWS account ID where event occurred
        event_name: Name of the event (e.g., 'RunInstances')
        policy_mapping: Complete policy mapping configuration
        
    Returns:
        List of policy file names to execute (without .yml extension)
    """
    # Check account-specific policies first
    account_mapping = policy_mapping.get('account_mapping', {})
    
    if account_id in account_mapping:
        account_config = account_mapping[account_id]
        account_name = account_config.get('name', account_id)
        
        # Check for account-specific event mapping
        account_event_mapping = account_config.get('event_mapping', {})
        
        if event_name in account_event_mapping:
            policy_configs = account_event_mapping[event_name]
            policy_names = [p['source_file'].replace('.yml', '') for p in policy_configs]
            logger.info(f"Found {len(policy_names)} account-specific policy(ies) for event '{event_name}' in account {account_name}: {policy_names}")
            return policy_names
    
    # Fallback to global event mapping
    global_event_mapping = policy_mapping.get('event_mapping', {})
    
    if event_name in global_event_mapping:
        policy_configs = global_event_mapping[event_name]
        policy_names = [p['source_file'].replace('.yml', '') for p in policy_configs]
        logger.info(f"Found {len(policy_names)} global policy(ies) for event '{event_name}': {policy_names}")
        return policy_names
    
    logger.info(f"No policies configured for event '{event_name}' in account {account_id}")
    return []


def handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler function
    
    Args:
        event: EventBridge event payload
        context: Lambda context object
        
    Returns:
        Dict containing execution results
    """
    logger.info(f"Received event: {json.dumps(event, default=str)}")
    
    try:
        # Validate event
        validation_result = validate_event(event)
        if not validation_result['valid']:
            logger.error(f"Event validation failed: {validation_result['error']}")
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'success': False,
                    'error': validation_result['error']
                })
            }
        
        event_info = validation_result['event_info']
        
        # Extract account and region
        account_id = extract_account_from_event(event)
        if not account_id:
            logger.error("Could not extract account ID from event")
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'success': False,
                    'error': 'Missing account ID in event'
                })
            }
        
        region = extract_region_from_event(event)
        event_name = event_info.get('event_name', 'Unknown')
        
        logger.info(f"Processing event '{event_name}' from account {account_id} in region {region}")
        
        # Load account policy mapping
        account_mapping = load_account_policy_mapping()
        
        # Get policies to execute
        policy_names = get_policies_for_event(account_id, event_name, account_mapping)
        
        if not policy_names:
            logger.info("No policies to execute for this event")
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'success': True,
                    'message': 'No policies configured for this event',
                    'account_id': account_id,
                    'event_name': event_name
                })
            }
        
        # Initialize cross-account executor
        executor = CrossAccountExecutor(
            account_id=account_id,
            region=region
        )
        
        # Assume role in target account
        try:
            assume_result = executor.assume_role()
            logger.info(f"Successfully assumed role, session expires at {assume_result['expiration']}")
        except Exception as e:
            logger.error(f"Failed to assume role in account {account_id}: {str(e)}")
            return {
                'statusCode': 500,
                'body': json.dumps({
                    'success': False,
                    'error': f'Failed to assume role: {str(e)}',
                    'account_id': account_id
                })
            }
        
        # Execute each policy
        results = []
        for policy_name in policy_names:
            try:
                # Load policy configuration
                policy_config = load_policy_from_s3(policy_name)
                
                # Execute policy
                result = executor.execute_policy(policy_config, event_info)
                results.append(result)
                
                logger.info(f"Policy '{policy_name}' execution completed: {result}")
                
            except Exception as e:
                logger.error(f"Failed to execute policy '{policy_name}': {str(e)}", exc_info=True)
                results.append({
                    'policy_name': policy_name,
                    'success': False,
                    'error': str(e)
                })
        
        # Summary
        successful = sum(1 for r in results if r.get('success'))
        total = len(results)
        
        response = {
            'statusCode': 200,
            'body': json.dumps({
                'success': True,
                'account_id': account_id,
                'region': region,
                'event_name': event_name,
                'policies_executed': total,
                'policies_successful': successful,
                'policies_failed': total - successful,
                'results': results
            }, default=str)
        }
        
        logger.info(f"Execution complete: {successful}/{total} policies successful")
        
        return response
        
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'body': json.dumps({
                'success': False,
                'error': str(e)
            })
        }
