"""
Lambda Handler for Cross-Account Cloud Custodian Execution

Main entry point for processing EventBridge events from member accounts
and executing Cloud Custodian policies with cross-account role assumption.

Also handles real-time SQS message processing with custom formatting for instant notifications.
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
from event_validator import validate_event
from realtime_notifier import process_realtime_sqs_messages

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.getenv('LOG_LEVEL', 'INFO'))

# Optional import - graceful degradation if not deployed yet
try:
    from compliance_pre_validator import ResourceValidator
    RESOURCE_VALIDATOR_AVAILABLE = True
except ImportError:
    logger.warning("ResourceValidator module not available - pre-validation disabled")
    ResourceValidator = None
    RESOURCE_VALIDATOR_AVAILABLE = False

# Note: Cloud Custodian logger configuration is done in cross_account_executor.py
# (after c7n imports, since c7n resets logging configuration on import)

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


def get_policies_for_event(account_id: str, event_name: str, policy_mapping: Dict[str, Any]) -> dict:
    """
    Get policies to execute for a given account and event
    Only checks account-specific event mappings - all policies must be explicitly mapped to events
    
    Args:
        account_id: AWS account ID where event occurred
        event_name: Name of the event (e.g., 'RunInstances')
        policy_mapping: Complete policy mapping configuration
        
    Returns:
        Dict mapping source files to list of policy names to execute
        Example: {'aws-ec2-security': ['ec2-stop-instances-on-launch']}
    """
    # Result will always be a dict: file_name -> [policy_names]
    policies_by_file = {}
    
    # Check account-specific policies
    account_mapping = policy_mapping.get('account_mapping', {})
    
    if account_id not in account_mapping:
        logger.info(f"Account {account_id} not found in policy mapping")
        return {}
    
    account_config = account_mapping[account_id]
    account_name = account_config.get('name', account_id)
    
    # Check for account-specific event mapping
    account_event_mapping = account_config.get('event_mapping', {})
    
    if event_name in account_event_mapping:
        policy_configs = account_event_mapping[event_name]
        # Group by source file
        for policy_config in policy_configs:
            file_name = policy_config['source_file'].replace('.yml', '')
            policy_name = policy_config['policy_name']
            if file_name not in policies_by_file:
                policies_by_file[file_name] = []
            policies_by_file[file_name].append(policy_name)
        
        logger.info(f"Found {len(policy_configs)} policy(ies) for event '{event_name}' in account {account_name}: {policies_by_file}")
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
    # Get unique invocation ID from Lambda context to filter SQS messages
    invocation_id = context.aws_request_id if context else None
    logger.info(f"Lambda invocation ID: {invocation_id}")
    
    # Set invocation ID as environment variable so Cloud Custodian can include it in SQS messages
    if invocation_id:
        os.environ['C7N_INVOCATION_ID'] = invocation_id
    
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
        
        # ===== PRE-VALIDATION FOR LONG-RUNNING RESOURCES =====
        # Check if this event supports pre-validation (ElastiCache, EKS, Elasticsearch, Redshift)
        if RESOURCE_VALIDATOR_AVAILABLE and ResourceValidator is not None:
            validator = ResourceValidator()
            if validator.is_supported(event_name):
                logger.info(f"🔍 Pre-validating event '{event_name}' before Cloud Custodian execution...")
                validation_result = validator.validate(event_name, event.get('detail', {}))
                
                if validation_result['action'] == 'skip':
                    # Resource is compliant - skip Cloud Custodian execution
                    logger.info(f"✅ Resource {validation_result.get('resource_id')} is compliant - skipping Cloud Custodian")
                    logger.info(f"   Reason: {validation_result.get('reason')}")
                    return {
                        'statusCode': 200,
                        'body': json.dumps({
                            'success': True,
                            'message': 'Resource is compliant - Cloud Custodian execution skipped',
                            'account_id': account_id,
                            'event_name': event_name,
                            'resource_id': validation_result.get('resource_id'),
                            'reason': validation_result.get('reason'),
                            'skipped': True
                        })
                    }
                else:
                    # Resource has violations - proceed with Cloud Custodian
                    logger.warning(f"⚠️  Resource {validation_result.get('resource_id')} has violations - proceeding to Cloud Custodian")
                    logger.warning(f"   Violations: {validation_result.get('violations')}")
        else:
            logger.debug(f"Pre-validation not available for event '{event_name}'")
        # ===== END PRE-VALIDATION =====
        
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
        # Extract environment from account mapping
        account_info = account_mapping.get('account_mapping', {}).get(account_id, {})
        environment = account_info.get('environment', 'unknown')
        
        executor = CrossAccountExecutor(
            account_id=account_id,
            region=region,
            environment=environment
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
        
        # Process SQS messages for real-time notifications ONLY if policies were executed
        # This sends immediate formatted notifications for event-driven policies
        # Periodic policies will use the native c7n-mailer Lambda instead
        sqs_stats = {'processed': 0, 'published': 0}
        if successful > 0:
            logger.info("📨 Processing real-time SQS messages for immediate notification...")
            sqs_stats = process_realtime_sqs_messages(invocation_id=invocation_id)
        else:
            logger.info("⏭️  Skipping SQS processing - no policies executed successfully")
        
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
                'realtime_notifications_sent': sqs_stats.get('published', 0),
                'sqs_messages_processed': sqs_stats.get('processed', 0),
                'results': results
            }, default=str)
        }
        
        logger.info(f"Execution complete: {successful}/{total} policies successful, {sqs_stats.get('published', 0)} real-time notifications sent")
        
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
