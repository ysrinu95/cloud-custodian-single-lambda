"""
Event Validator Module for Cloud Custodian Lambda

This module validates EventBridge events and determines which Cloud Custodian
policy should be executed based on the policy mapping configuration.
"""

import json
import logging
import os
from typing import Dict, Any, Optional, List

logger = logging.getLogger()
logger.setLevel(logging.INFO)


class EventValidator:
    """Validates EventBridge events and maps them to Cloud Custodian policies"""
    
    def __init__(self, policy_mapping: Dict[str, Any]):
        """
        Initialize the validator with policy mapping configuration
        
        Args:
            policy_mapping: Dictionary containing policy mapping configuration
        """
        self.policy_mapping = policy_mapping
        self.event_mapping = policy_mapping.get('event_mapping', {})
        self.default_policy = policy_mapping.get('default_policy', {})
        
        logger.info(f"EventValidator initialized with {len(self.event_mapping)} event types")
    
    def validate_event(self, event: Dict[str, Any]) -> Dict[str, Any]:
        """
        Validate and extract information from EventBridge event
        
        Args:
            event: EventBridge event data
            
        Returns:
            Dictionary with validation results and extracted event information
            
        Raises:
            ValueError: If event is invalid or missing required fields
        """
        logger.info(f"Validating event: {json.dumps(event, default=str)}")
        
        # Check if it's an EventBridge event
        if 'detail-type' not in event:
            raise ValueError("Invalid event: missing 'detail-type' field")
        
        detail_type = event.get('detail-type', '')
        
        # Validate it's a CloudTrail API call
        if detail_type != 'AWS API Call via CloudTrail':
            raise ValueError(f"Unsupported event type: {detail_type}")
        
        # Extract event details
        detail = event.get('detail', {})
        if not detail:
            raise ValueError("Invalid event: missing 'detail' field")
        
        # Extract key information
        event_info = {
            'event_name': detail.get('eventName', ''),
            'event_source': detail.get('eventSource', ''),
            'event_time': detail.get('eventTime', ''),
            'aws_region': detail.get('awsRegion', event.get('region', 'us-east-1')),
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
            'guardduty.amazonaws.com'
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
        
        logger.info(f"Event validated: {event_info['event_name']}")
        
        return {
            'valid': True,
            'event_info': event_info
        }
    
    def _extract_bucket_name(self, event_info: Dict[str, Any]) -> str:
        """
        Extract bucket name from event information
        
        Args:
            event_info: Extracted event information
            
        Returns:
            Bucket name
            
        Raises:
            ValueError: If bucket name cannot be extracted
        """
        # Try different locations for bucket name
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
    
    def get_policy_mappings(self, event_info: Dict[str, Any]) -> List[Dict[str, Any]]:
        """
        Get all policy mappings for the given event
        
        Args:
            event_info: Validated event information
            
        Returns:
            List of policy mapping configurations for this event type
        """
        event_name = event_info.get('event_name', '')
        
        logger.info(f"Looking up policy mappings for event: {event_name}")
        
        # Get all policies mapped to this event type
        policies = self.event_mapping.get(event_name, [])
        
        if not policies:
            logger.warning(f"No policies found for event {event_name}")
            return []
        
        logger.info(f"Found {len(policies)} policies for event {event_name}")
        
        return policies
    
    def get_policy_details(self, event: Dict[str, Any]) -> Dict[str, Any]:
        """
        Validate event and return policy execution details for all mapped policies
        
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
        
        # Get all policy mappings for this event
        policy_mappings = self.get_policy_mappings(event_info)
        
        if not policy_mappings:
            raise ValueError(f"No policies found for event {event_info['event_name']}")
        
        # Extract S3 configuration from environment variables
        s3_bucket = os.environ.get('POLICY_MAPPING_BUCKET')
        s3_prefix = os.environ.get('POLICY_PREFIX', 'policies/')
        
        if not s3_bucket:
            raise ValueError("POLICY_MAPPING_BUCKET environment variable not set")
        
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
                'mode_type': policy_mapping.get('mode_type', 'cloudtrail')
            })
        
        logger.info(f"Prepared {len(policies_to_execute)} policies for execution")
        
        result = {
            'event_info': event_info,
            'policies': policies_to_execute
        }
        
        logger.info(f"Policy details: {json.dumps(result, default=str)}")
        
        return result


def validate_policy_mapping_config(config: Dict[str, Any]) -> bool:
    """
    Validate policy mapping configuration structure
    
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
    
    logger.info(f"Policy mapping configuration is valid with {len(event_mapping)} event types")
    return True
