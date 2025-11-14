"""
Event Validator Module for Cloud Custodian Lambda

This module validates EventBridge events and determines which Cloud Custodian
policy should be executed based on the policy mapping configuration.
"""

import json
import logging
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
        self.mappings = policy_mapping.get('mappings', [])
        self.default_policy = policy_mapping.get('default_policy', {})
        
        logger.info(f"EventValidator initialized with {len(self.mappings)} mappings")
    
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
    
    def get_policy_mapping(self, event_info: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """
        Get policy mapping for the given event
        
        Args:
            event_info: Validated event information
            
        Returns:
            Policy mapping configuration or None if not found
        """
        event_name = event_info.get('event_name', '')
        
        logger.info(f"Looking up policy mapping for event: {event_name}")
        
        # Find matching mapping
        matching_mappings = [
            mapping for mapping in self.mappings
            if mapping.get('event_type') == event_name and mapping.get('enabled', True)
        ]
        
        if not matching_mappings:
            logger.warning(f"No mapping found for event {event_name}, using default policy")
            return self.default_policy if self.default_policy.get('enabled', True) else None
        
        # Sort by priority (lower number = higher priority)
        matching_mappings.sort(key=lambda x: x.get('priority', 999))
        
        selected_mapping = matching_mappings[0]
        logger.info(f"Selected mapping: {selected_mapping}")
        
        return selected_mapping
    
    def get_policy_details(self, event: Dict[str, Any]) -> Dict[str, Any]:
        """
        Validate event and return policy execution details
        
        Args:
            event: EventBridge event
            
        Returns:
            Dictionary containing policy execution details
            
        Raises:
            ValueError: If event is invalid or no policy mapping found
        """
        # Validate event
        validation_result = self.validate_event(event)
        event_info = validation_result['event_info']
        
        # Get policy mapping
        policy_mapping = self.get_policy_mapping(event_info)
        
        if not policy_mapping:
            raise ValueError(f"No enabled policy found for event {event_info['event_name']}")
        
        # Extract S3 configuration
        s3_bucket = self.policy_mapping.get('s3_policy_bucket')
        s3_prefix = self.policy_mapping.get('s3_policy_prefix', '')
        
        if not s3_bucket:
            raise ValueError("S3 policy bucket not configured in policy mapping")
        
        policy_file = policy_mapping.get('policy_file')
        policy_name = policy_mapping.get('policy_name')
        
        if not policy_file or not policy_name:
            raise ValueError("Invalid policy mapping: missing policy_file or policy_name")
        
        # Construct S3 key
        s3_key = f"{s3_prefix}{policy_file}".replace('//', '/')
        
        result = {
            'event_info': event_info,
            'policy_config': {
                's3_bucket': s3_bucket,
                's3_key': s3_key,
                'policy_file': policy_file,
                'policy_name': policy_name,
                'mapping_description': policy_mapping.get('description', ''),
            }
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
    required_fields = ['version', 'mappings']
    for field in required_fields:
        if field not in config:
            raise ValueError(f"Missing required field: {field}")
    
    mappings = config.get('mappings', [])
    if not isinstance(mappings, list):
        raise ValueError("'mappings' must be a list")
    
    for idx, mapping in enumerate(mappings):
        required_mapping_fields = ['event_type', 'policy_file', 'policy_name']
        for field in required_mapping_fields:
            if field not in mapping:
                raise ValueError(f"Mapping {idx}: missing required field '{field}'")
    
    logger.info("Policy mapping configuration is valid")
    return True
