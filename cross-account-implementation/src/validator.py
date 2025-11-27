"""
Event Validator Module for Cross-Account Cloud Custodian Lambda

This module validates EventBridge events and determines which Cloud Custodian
policy should be executed based on the policy mapping configuration.
Handles events from multiple AWS accounts and extracts account-specific context.
"""

import json
import logging
import os
from typing import Dict, Any, Optional, List

logger = logging.getLogger()
logger.setLevel(logging.INFO)


class EventValidator:
    """Validates EventBridge events from multiple accounts and maps them to Cloud Custodian policies"""
    
    def __init__(self, policy_mapping: Dict[str, Any]):
        """
        Initialize the validator with policy mapping configuration
        
        Args:
            policy_mapping: Dictionary containing policy mapping configuration
        """
        self.policy_mapping = policy_mapping
        self.event_mapping = policy_mapping.get('event_mapping', {})
        self.account_mapping = policy_mapping.get('account_mapping', {})
        self.default_policy = policy_mapping.get('default_policy', {})
        
        logger.info(f"EventValidator initialized with {len(self.event_mapping)} event types")
        logger.info(f"Account mapping configured for {len(self.account_mapping)} accounts")
    
    def validate_event(self, event: Dict[str, Any]) -> Dict[str, Any]:
        """
        Validate and extract information from EventBridge event (cross-account aware)
        
        Args:
            event: EventBridge event data
            
        Returns:
            Dictionary with validation results and extracted event information
            
        Raises:
            ValueError: If event is invalid or missing required fields
        """
        logger.info(f"Validating cross-account event: {json.dumps(event, default=str)}")
        
        # Check if it's an EventBridge event
        if 'detail-type' not in event:
            raise ValueError("Invalid event: missing 'detail-type' field")
        
        detail_type = event.get('detail-type', '')
        
        # Extract source account ID
        source_account = event.get('account')
        if source_account:
            logger.info(f"Event from account: {source_account}")
        
        # Handle different event types
        if detail_type == 'AWS API Call via CloudTrail':
            # CloudTrail event processing
            return self._validate_cloudtrail_event(event)
        elif detail_type == 'Security Hub Findings - Imported':
            # Security Hub event processing
            return self._validate_securityhub_event(event)
        elif detail_type == 'GuardDuty Finding':
            # GuardDuty event processing
            return self._validate_guardduty_event(event)
        else:
            raise ValueError(f"Unsupported event type: {detail_type}")
    
    def _validate_cloudtrail_event(self, event: Dict[str, Any]) -> Dict[str, Any]:
        """Validate CloudTrail API call events (cross-account aware)"""
        # Extract event details
        detail = event.get('detail', {})
        if not detail:
            raise ValueError("Invalid event: missing 'detail' field")
        
        # Extract source account
        source_account = event.get('account')
        if not source_account:
            # Fallback: extract from userIdentity
            user_identity = detail.get('userIdentity', {})
            source_account = user_identity.get('accountId')
        
        # Extract key information
        event_info = {
            'event_name': detail.get('eventName', ''),
            'event_source': detail.get('eventSource', ''),
            'event_time': detail.get('eventTime', ''),
            'aws_region': detail.get('awsRegion', event.get('region', 'us-east-1')),
            'source_account': source_account,  # Cross-account context
            'source_ip': detail.get('sourceIPAddress', ''),
            'user_agent': detail.get('userAgent', ''),
            'request_parameters': detail.get('requestParameters', {}),
            'response_elements': detail.get('responseElements', {}),
            'user_identity': detail.get('userIdentity', {}),
            'raw_event': event,  # Include the complete raw event for policy context
        }
        
        # Validate event source
        event_source = event_info['event_source']
        
        # Support multiple AWS services
        supported_sources = [
            's3.amazonaws.com',
            'ec2.amazonaws.com',
            'iam.amazonaws.com',
            'securityhub.amazonaws.com',
            'guardduty.amazonaws.com',
            'macie.amazonaws.com',
            'config.amazonaws.com',
            'lambda.amazonaws.com',
            'rds.amazonaws.com',
            'dynamodb.amazonaws.com'
        ]
        
        if event_source not in supported_sources:
            logger.warning(f"Event source {event_source} not in typical supported list, proceeding anyway")
        
        # Extract resource identifiers based on service
        if event_source == 's3.amazonaws.com':
            bucket_name = self._extract_bucket_name(event_info)
            event_info['bucket_name'] = bucket_name
        elif event_source == 'ec2.amazonaws.com':
            instance_id = self._extract_instance_id(event_info)
            if instance_id:
                event_info['instance_id'] = instance_id
            group_id = self._extract_security_group_id(event_info)
            if group_id:
                event_info['group_id'] = group_id
        elif event_source == 'iam.amazonaws.com':
            username = self._extract_username(event_info)
            if username:
                event_info['username'] = username
        
        logger.info(f"Event validated from account {source_account}: {event_info['event_name']}")
        
        return {
            'valid': True,
            'event_info': event_info
        }
    
    def _validate_securityhub_event(self, event: Dict[str, Any]) -> Dict[str, Any]:
        """Validate Security Hub Findings events (cross-account aware)"""
        # Extract event details
        detail = event.get('detail', {})
        if not detail:
            raise ValueError("Invalid event: missing 'detail' field")
        
        # Extract source account
        source_account = event.get('account')
        if not source_account:
            # Fallback: extract from findings
            findings = detail.get('findings', [])
            if findings and len(findings) > 0:
                source_account = findings[0].get('AwsAccountId')
        
        # Security Hub events use 'detail-type' as the event name
        detail_type = event.get('detail-type', '')
        
        # Extract key information
        event_info = {
            'event_name': detail_type,  # Use the detail-type as event name
            'event_source': event.get('source', 'aws.securityhub'),
            'event_time': event.get('time', ''),
            'aws_region': event.get('region', 'us-east-1'),
            'source_account': source_account,  # Cross-account context
            'source_ip': '',  # Security Hub events don't have source IP
            'user_agent': '',  # Security Hub events don't have user agent
            'request_parameters': {},
            'response_elements': detail,  # The findings are in the detail
            'user_identity': {},
            'raw_event': event,  # Include the complete raw event for policy context
        }
        
        logger.info(f"Security Hub event validated from account {source_account}: {event_info['event_name']}")
        
        return {
            'valid': True,
            'event_info': event_info
        }
    
    def _validate_guardduty_event(self, event: Dict[str, Any]) -> Dict[str, Any]:
        """Validate GuardDuty Finding events (cross-account aware)"""
        # Extract event details
        detail = event.get('detail', {})
        if not detail:
            raise ValueError("Invalid event: missing 'detail' field")
        
        # Extract source account
        source_account = event.get('account')
        if not source_account:
            # Fallback: extract from detail
            source_account = detail.get('accountId')
        
        # GuardDuty events use 'detail-type' as the event name
        detail_type = event.get('detail-type', '')
        
        # Extract finding details
        finding_type = detail.get('type', '')
        severity = detail.get('severity', 0)
        finding_id = detail.get('id', '')
        
        # Extract key information
        event_info = {
            'event_name': detail_type,  # Use the detail-type as event name
            'event_source': event.get('source', 'aws.guardduty'),
            'event_time': event.get('time', ''),
            'aws_region': detail.get('region', event.get('region', 'us-east-1')),
            'source_account': source_account,  # Cross-account context
            'source_ip': '',  # GuardDuty events don't have source IP in event metadata
            'user_agent': '',  # GuardDuty events don't have user agent
            'request_parameters': {},
            'response_elements': detail,  # The finding details are in the detail
            'user_identity': {},
            'raw_event': event,  # Include the complete raw event for policy context
            'finding_type': finding_type,  # GuardDuty finding type (e.g., CryptoCurrency:EC2/BitcoinTool.B!DNS)
            'severity': severity,  # GuardDuty severity score (0-10)
            'finding_id': finding_id  # GuardDuty finding ID
        }
        
        logger.info(f"GuardDuty event validated from account {source_account}: {finding_type} (severity: {severity})")
        
        return {
            'valid': True,
            'event_info': event_info
        }
    
    def _extract_bucket_name(self, event_info: Dict[str, Any]) -> str:
        """Extract bucket name from event information"""
        request_params = event_info.get('request_parameters', {})
        
        # Method 1: bucketName in request parameters
        bucket_name = request_params.get('bucketName')
        if bucket_name:
            return bucket_name
        
        # Method 2: bucket in request parameters
        bucket_name = request_params.get('bucket')
        if bucket_name:
            return bucket_name
        
        # Method 3: Extract from response elements
        response_elements = event_info.get('response_elements', {})
        if isinstance(response_elements, dict):
            bucket_name = response_elements.get('bucketName')
            if bucket_name:
                return bucket_name
        
        raise ValueError("Could not extract bucket name from event")
    
    def _extract_instance_id(self, event_info: Dict[str, Any]) -> Optional[str]:
        """Extract EC2 instance ID from event information"""
        request_params = event_info.get('request_parameters', {})
        response_elements = event_info.get('response_elements', {})
        
        # Try response elements first (for RunInstances)
        if isinstance(response_elements, dict):
            instances_set = response_elements.get('instancesSet', {})
            if isinstance(instances_set, dict):
                items = instances_set.get('items', [])
                if items and len(items) > 0:
                    return items[0].get('instanceId')
        
        # Try request parameters
        instance_id = request_params.get('instanceId')
        if instance_id:
            return instance_id
        
        # Try instancesSet in request
        instances_set = request_params.get('instancesSet', {})
        if isinstance(instances_set, dict):
            items = instances_set.get('items', [])
            if items and len(items) > 0:
                return items[0].get('instanceId')
        
        return None
    
    def _extract_security_group_id(self, event_info: Dict[str, Any]) -> Optional[str]:
        """Extract security group ID from event information"""
        request_params = event_info.get('request_parameters', {})
        response_elements = event_info.get('response_elements', {})
        
        # Try request parameters
        group_id = request_params.get('groupId')
        if group_id:
            return group_id
        
        # Try response elements (for CreateSecurityGroup)
        if isinstance(response_elements, dict):
            group_id = response_elements.get('groupId')
            if group_id:
                return group_id
        
        return None
    
    def _extract_username(self, event_info: Dict[str, Any]) -> Optional[str]:
        """Extract IAM username from event information"""
        request_params = event_info.get('request_parameters', {})
        
        # Try userName in request parameters
        username = request_params.get('userName')
        if username:
            return username
        
        # Try user in request parameters
        username = request_params.get('user')
        if username:
            return username
        
        return None
    
    def get_policy_mappings_for_account(
        self,
        event_info: Dict[str, Any],
        account_id: str
    ) -> List[Dict[str, Any]]:
        """
        Get policy mappings for specific account
        
        Args:
            event_info: Validated event information
            account_id: AWS account ID
            
        Returns:
            List of policy mapping configurations for this event type and account
        """
        event_name = event_info.get('event_name', '')
        
        logger.info(f"Looking up policy mappings for event: {event_name} in account: {account_id}")
        
        # Check if account has custom policy mapping
        account_config = self.account_mapping.get(account_id, {})
        
        # Get policies from account-specific mapping first, fallback to global
        if account_config and 'event_mapping' in account_config:
            policies = account_config['event_mapping'].get(event_name, [])
            if policies:
                logger.info(f"Using account-specific policies for {account_id}: {len(policies)} policies")
                return policies
        
        # Fallback to global event mapping
        policies = self.event_mapping.get(event_name, [])
        
        if not policies:
            logger.warning(f"No policies found for event {event_name} in account {account_id}")
            return []
        
        logger.info(f"Found {len(policies)} policies for event {event_name}")
        
        return policies
    
    def get_policy_mappings(self, event_info: Dict[str, Any]) -> List[Dict[str, Any]]:
        """
        Get all policy mappings for the given event (legacy method for backward compatibility)
        
        Args:
            event_info: Validated event information
            
        Returns:
            List of policy mapping configurations for this event type
        """
        event_name = event_info.get('event_name', '')
        logger.info(f"Looking up policy mappings for event: {event_name}")
        
        policies = self.event_mapping.get(event_name, [])
        
        if not policies:
            logger.warning(f"No policies found for event {event_name}")
            return []
        
        logger.info(f"Found {len(policies)} policies for event {event_name}")
        return policies
    
    def get_policy_details(self, event: Dict[str, Any]) -> Dict[str, Any]:
        """
        Validate event and return policy execution details for all mapped policies (cross-account aware)
        
        Args:
            event: EventBridge event
            
        Returns:
            Dictionary containing event info and list of policies to execute
            
        Raises:
            ValueError: If event is invalid or no policy mapping found
        """
        # Validate event
        validation_result = self.validate_event(event)
        event_info = validation_result['event_info']
        
        # Extract source account
        source_account = event_info.get('source_account')
        if not source_account:
            logger.warning("No source account found in event, using global policy mapping")
        
        # Get policy mappings for this account and event
        if source_account:
            policy_mappings = self.get_policy_mappings_for_account(event_info, source_account)
        else:
            policy_mappings = self.get_policy_mappings(event_info)
        
        if not policy_mappings:
            raise ValueError(f"No policies found for event {event_info['event_name']}")
        
        # Extract S3 configuration from environment variables
        s3_bucket = os.environ.get('POLICY_BUCKET')
        s3_prefix = os.environ.get('POLICY_PREFIX', 'policies/')
        
        if not s3_bucket:
            raise ValueError("POLICY_BUCKET environment variable not set")
        
        # Build policy configs for all mapped policies
        policies_to_execute = []
        for policy_mapping in policy_mappings:
            source_file = policy_mapping.get('source_file')
            policy_name = policy_mapping.get('policy_name')
            
            if not source_file or not policy_name:
                logger.warning(f"Skipping invalid policy mapping: {policy_mapping}")
                continue
            
            # Construct S3 key
            s3_key = f"{s3_prefix}{source_file}".replace('//', '/')
            
            policies_to_execute.append({
                's3_bucket': s3_bucket,
                's3_key': s3_key,
                'source_file': source_file,
                'policy_name': policy_name,
                'resource': policy_mapping.get('resource', ''),
                'mode_type': policy_mapping.get('mode_type', 'cloudtrail'),
                'target_account': source_account  # Cross-account context
            })
        
        logger.info(f"Prepared {len(policies_to_execute)} policies for execution in account {source_account}")
        
        result = {
            'event_info': event_info,
            'policies': policies_to_execute,
            'source_account': source_account,
            'target_region': event_info.get('aws_region', 'us-east-1')
        }
        
        logger.info(f"Policy details: {json.dumps(result, default=str)}")
        
        return result


def validate_policy_mapping_config(config: Dict[str, Any]) -> bool:
    """
    Validate policy mapping configuration structure (cross-account aware)
    
    Args:
        config: Policy mapping configuration dictionary
        
    Returns:
        True if valid
        
    Raises:
        ValueError: If configuration is invalid
    """
    required_fields = ['version', 'event_mapping']
    for field in required_fields:
        if field not in config:
            raise ValueError(f"Missing required field: {field}")
    
    event_mapping = config.get('event_mapping', {})
    if not isinstance(event_mapping, dict):
        raise ValueError("'event_mapping' must be a dictionary")
    
    # Validate each event type has a list of policies
    for event_type, policies in event_mapping.items():
        if not isinstance(policies, list):
            raise ValueError(f"Event '{event_type}': policies must be a list")
        
        for idx, policy in enumerate(policies):
            required_policy_fields = ['policy_name', 'resource', 'source_file']
            for field in required_policy_fields:
                if field not in policy:
                    raise ValueError(f"Event '{event_type}', policy {idx}: missing required field '{field}'")
    
    # Validate account_mapping (optional)
    if 'account_mapping' in config:
        account_mapping = config['account_mapping']
        if not isinstance(account_mapping, dict):
            raise ValueError("'account_mapping' must be a dictionary")
        
        for account_id, account_config in account_mapping.items():
            if 'event_mapping' in account_config:
                if not isinstance(account_config['event_mapping'], dict):
                    raise ValueError(f"Account '{account_id}': event_mapping must be a dictionary")
    
    logger.info(f"Policy mapping configuration is valid with {len(event_mapping)} event types")
    return True


# Legacy functions for backward compatibility
def validate_event(event: Dict[str, Any]) -> Dict[str, bool]:
    """Legacy validate_event function for backward compatibility"""
    try:
        validator = EventValidator({'event_mapping': {}})
        result = validator.validate_event(event)
        return {
            'valid': result['valid'],
            'event_info': result.get('event_info', {})
        }
    except Exception as e:
        return {
            'valid': False,
            'error': str(e)
        }


def validate_policy_config(policy_config: Dict[str, Any]) -> Dict[str, bool]:
    """Validate Cloud Custodian policy configuration"""
    if not isinstance(policy_config, dict):
        return {'valid': False, 'error': 'Policy config must be a dictionary'}
    
    required_fields = ['name', 'resource']
    for field in required_fields:
        if field not in policy_config:
            return {'valid': False, 'error': f'Missing required field: {field}'}
    
    if not isinstance(policy_config['name'], str) or not policy_config['name']:
        return {'valid': False, 'error': 'Policy name must be a non-empty string'}
    
    if not isinstance(policy_config['resource'], str) or not policy_config['resource']:
        return {'valid': False, 'error': 'Resource type must be a non-empty string'}
    
    if 'filters' in policy_config:
        if not isinstance(policy_config['filters'], list):
            return {'valid': False, 'error': 'Filters must be a list'}
    
    if 'actions' in policy_config:
        if not isinstance(policy_config['actions'], list):
            return {'valid': False, 'error': 'Actions must be a list'}
    
    return {'valid': True}
