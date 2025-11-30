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


def should_execute_policy_for_event(policy_config: Dict[str, Any], event_name: str) -> bool:
    """
    Determine if a policy should be executed for a given event
    
    Args:
        policy_config: The policy configuration dict
        event_name: Name of the CloudTrail event
        
    Returns:
        True if policy should be executed, False otherwise
    """
    # Check if policy has mode: cloudtrail (event-driven)
    mode = policy_config.get('mode', {})
    
    # If mode is a dict with type: cloudtrail
    if isinstance(mode, dict):
        if mode.get('type') != 'cloudtrail':
            return False
        
        # Check if events list contains this event
        events = mode.get('events', [])
        if event_name in events:
            logger.info(f"Policy '{policy_config.get('name')}' matches event '{event_name}'")
            return True
        else:
            logger.debug(f"Policy '{policy_config.get('name')}' does not match event '{event_name}' (expects: {events})")
            return False
    
    # If mode is just the string "cloudtrail", we need to check events separately
    # or accept it as matching all events (legacy format)
    if mode == 'cloudtrail':
        logger.info(f"Policy '{policy_config.get('name')}' is cloudtrail mode (legacy format)")
        return True
    
    # No mode specified or not cloudtrail - skip for event-driven execution
    logger.debug(f"Policy '{policy_config.get('name')}' is not event-driven (mode: {mode})")
    return False


def load_policy_from_s3(policy_name: str) -> list:
    """
    Load Cloud Custodian policy YAML from S3
    
    Args:
        policy_name: Name of the policy file (without .yml extension)
        
    Returns:
        List of policy configurations from the file
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
        
        # Return all policies from the file
        if 'policies' in policy_config:
            return policy_config['policies']
        
        # If single policy format, wrap in list
        return [policy_config]
        
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
        List of unique policy file names to execute (without .yml extension)
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
            policy_names = list(set([p['source_file'].replace('.yml', '') for p in policy_configs]))
            logger.info(f"Found {len(policy_names)} account-specific policy(ies) for event '{event_name}' in account {account_name}: {policy_names}")
            return policy_names
    
    # Fallback to global event mapping
    global_event_mapping = policy_mapping.get('event_mapping', {})
    
    if event_name in global_event_mapping:
        policy_configs = global_event_mapping[event_name]
        # Group by source file and collect policy names
        policies_by_file = {}
        for config in policy_configs:
            file_name = config['source_file'].replace('.yml', '')
            policy_name = config['policy_name']
            if file_name not in policies_by_file:
                policies_by_file[file_name] = []
            policies_by_file[file_name].append(policy_name)
        logger.info(f"Found {len(policy_configs)} global policy(ies) for event '{event_name}': {policies_by_file}")
        return policies_by_file
    
    logger.info(f"No policies configured for event '{event_name}' in account {account_id}")
    return {}


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
        policies_by_file = get_policies_for_event(account_id, event_name, account_mapping)
        
        if not policies_by_file:
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
        
        # Check if this is the central account (Lambda's own account)
        sts = boto3.client('sts')
        central_account_id = sts.get_caller_identity()['Account']
        
        if account_id == central_account_id:
            # Event is from central account - use default session (no role assumption needed)
            logger.info(f"Event is from central account {account_id} - using default session")
            executor.session = boto3.Session(region_name=region)
        else:
            # Event is from member account - assume cross-account role
            try:
                assume_result = executor.assume_role()
                logger.info(f"Successfully assumed role in member account {account_id}, session expires at {assume_result['expiration']}")
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
        
        # Execute each policy file
        results = []
        for policy_file, policy_names_to_execute in policies_by_file.items():
            try:
                # Load all policies from this file
                all_policies = load_policy_from_s3(policy_file)
                logger.info(f"Loaded {len(all_policies)} policy(ies) from {policy_file}")
                logger.info(f"Will execute only specific policies: {policy_names_to_execute}")
                
                # Execute only the specific policies listed in the mapping
                for policy_config in all_policies:
                    policy_display_name = policy_config.get('name', policy_file)
                    
                    # Skip policies not in the mapping for this event
                    if policy_display_name not in policy_names_to_execute:
                        logger.info(f"Skipping policy '{policy_display_name}' - not mapped to this event")
                        continue
                    
                    try:
                        result = executor.execute_policy(policy_config, event_info)
                        results.append(result)
                        logger.info(f"Policy '{policy_display_name}' execution completed: {result}")
                    except Exception as e:
                        logger.error(f"Failed to execute policy '{policy_display_name}': {str(e)}", exc_info=True)
                        results.append({
                            'policy_name': policy_display_name,
                            'success': False,
                            'error': str(e)
                        })
                
            except Exception as e:
                logger.error(f"Failed to load policy file '{policy_file}': {str(e)}", exc_info=True)
                results.append({
                    'policy_name': policy_file,
                    'success': False,
                    'error': f"Failed to load policy file: {str(e)}"
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
