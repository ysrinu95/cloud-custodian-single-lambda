"""
Policy Executor Module for Cloud Custodian Lambda

This module downloads policy files from S3 and executes specific
Cloud Custodian policies.
"""

import boto3
import json
import logging
import tempfile
import yaml
from typing import Dict, Any, Optional
from io import StringIO

logger = logging.getLogger()
logger.setLevel(logging.INFO)


class PolicyExecutor:
    """Downloads and executes Cloud Custodian policies from S3"""
    
    def __init__(self, region: str = 'us-east-1'):
        """
        Initialize the policy executor
        
        Args:
            region: AWS region
        """
        self.region = region
        self.s3_client = boto3.client('s3', region_name=region)
        logger.info(f"PolicyExecutor initialized for region {region}")
    
    def download_policy_file(self, bucket: str, key: str) -> str:
        """
        Download policy file from S3
        
        Args:
            bucket: S3 bucket name
            key: S3 object key
            
        Returns:
            Policy file content as string
            
        Raises:
            Exception: If download fails
        """
        logger.info(f"Downloading policy file from s3://{bucket}/{key}")
        
        try:
            response = self.s3_client.get_object(Bucket=bucket, Key=key)
            policy_content = response['Body'].read().decode('utf-8')
            
            logger.info(f"Successfully downloaded policy file ({len(policy_content)} bytes)")
            return policy_content
            
        except Exception as e:
            logger.error(f"Failed to download policy file: {str(e)}")
            raise
    
    def parse_policy_file(self, policy_content: str) -> Dict[str, Any]:
        """
        Parse YAML policy file content
        
        Args:
            policy_content: Policy file content as string
            
        Returns:
            Parsed policy dictionary
            
        Raises:
            Exception: If parsing fails
        """
        logger.info("Parsing policy file")
        
        try:
            policy_data = yaml.safe_load(policy_content)
            
            if not isinstance(policy_data, dict):
                raise ValueError("Invalid policy file: root must be a dictionary")
            
            if 'policies' not in policy_data:
                raise ValueError("Invalid policy file: missing 'policies' key")
            
            logger.info(f"Successfully parsed policy file with {len(policy_data['policies'])} policies")
            return policy_data
            
        except Exception as e:
            logger.error(f"Failed to parse policy file: {str(e)}")
            raise
    
    def find_policy(self, policy_data: Dict[str, Any], policy_name: str) -> Optional[Dict[str, Any]]:
        """
        Find a specific policy by name in the policy file
        
        Args:
            policy_data: Parsed policy data
            policy_name: Name of the policy to find
            
        Returns:
            Policy configuration or None if not found
        """
        logger.info(f"Looking for policy: {policy_name}")
        
        policies = policy_data.get('policies', [])
        
        for policy in policies:
            if policy.get('name') == policy_name:
                logger.info(f"Found policy: {policy_name}")
                return policy
        
        logger.warning(f"Policy not found: {policy_name}")
        return None
    
    def execute_policy(
        self,
        policy_config: Dict[str, Any],
        event_info: Dict[str, Any],
        dryrun: bool = False
    ) -> Dict[str, Any]:
        """
        Execute a Cloud Custodian policy
        
        Args:
            policy_config: Policy configuration containing S3 location and policy name
            event_info: Event information from EventBridge
            dryrun: Whether to run in dry-run mode
            
        Returns:
            Execution results
            
        Raises:
            Exception: If execution fails
        """
        logger.info(f"Executing policy: {policy_config.get('policy_name')}")
        logger.info(f"Dry-run mode: {dryrun}")
        
        try:
            # Download policy file from S3
            s3_bucket = policy_config['s3_bucket']
            s3_key = policy_config['s3_key']
            policy_name = policy_config['policy_name']
            
            policy_content = self.download_policy_file(s3_bucket, s3_key)
            
            # Parse policy file
            policy_data = self.parse_policy_file(policy_content)
            
            # Find specific policy
            policy = self.find_policy(policy_data, policy_name)
            
            if not policy:
                raise ValueError(f"Policy '{policy_name}' not found in file")
            
            # Execute the policy using Cloud Custodian
            result = self._execute_custodian_policy(policy, event_info, dryrun)
            
            logger.info(f"Policy execution completed: {policy_name}")
            return result
            
        except Exception as e:
            logger.error(f"Policy execution failed: {str(e)}")
            raise
    
    def _execute_custodian_policy(
        self,
        policy: Dict[str, Any],
        event_info: Dict[str, Any],
        dryrun: bool
    ) -> Dict[str, Any]:
        """
        Execute Cloud Custodian policy using the c7n library
        
        Args:
            policy: Single policy configuration
            event_info: Event information (includes raw CloudTrail event)
            dryrun: Dry-run mode flag
            
        Returns:
            Execution results
        """
        from c7n.policy import PolicyCollection
        from c7n import resources
        
        logger.info(f"Executing Cloud Custodian policy: {policy.get('name')}")
        
        # Prepare policy configuration
        policy_config = {
            'policies': [policy]
        }
        
        # Add context information from event
        if 'resource' in policy:
            # Filter by specific bucket if it's an S3 policy
            bucket_name = event_info.get('bucket_name')
            if bucket_name and policy.get('resource') == 's3':
                logger.info(f"Adding bucket filter for: {bucket_name}")
                
                # Add filter to target specific bucket
                if 'filters' not in policy:
                    policy['filters'] = []
                
                # Insert bucket name filter at the beginning
                policy['filters'].insert(0, {
                    'type': 'value',
                    'key': 'Name',
                    'value': bucket_name
                })
            
            # For EC2 resources, filter by instance ID if available
            instance_id = event_info.get('instance_id')
            if instance_id and policy.get('resource') == 'aws.ec2':
                logger.info(f"Adding instance filter for: {instance_id}")
                
                if 'filters' not in policy:
                    policy['filters'] = []
                
                policy['filters'].insert(0, {
                    'type': 'value',
                    'key': 'InstanceId',
                    'value': instance_id
                })
            
            # For IAM users, filter by username if available
            username = event_info.get('username')
            if username and policy.get('resource') == 'aws.iam-user':
                logger.info(f"Adding user filter for: {username}")
                
                if 'filters' not in policy:
                    policy['filters'] = []
                
                policy['filters'].insert(0, {
                    'type': 'value',
                    'key': 'UserName',
                    'value': username
                })
            
            # For security groups, filter by group ID if available
            group_id = event_info.get('group_id')
            if group_id and policy.get('resource') == 'aws.security-group':
                logger.info(f"Adding security group filter for: {group_id}")
                
                if 'filters' not in policy:
                    policy['filters'] = []
                
                policy['filters'].insert(0, {
                    'type': 'value',
                    'key': 'GroupId',
                    'value': group_id
                })
        
        # Create temporary file for policy
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yml', delete=False) as tmp_file:
            yaml.dump(policy_config, tmp_file)
            tmp_policy_path = tmp_file.name
        
        try:
            # Extract raw CloudTrail event data for policy context
            raw_event = event_info.get('raw_event', {})
            
            # Create policy collection with event context using Config class
            from c7n.config import Config
            
            options = Config.empty(
                region=self.region,
                log_group=f'/aws/lambda/cloud-custodian',
                output_dir='/tmp/custodian-output',
                cache='/tmp/custodian-cache',
                dryrun=dryrun,
            )
            
            # Load policies
            collection = PolicyCollection.from_data(policy_config, options)
            
            # Execute policies with event context
            results = []
            for p in collection:
                logger.info(f"Running policy: {p.name}")
                
                # Set event context if available
                # This allows policies to access event data via {event.userIdentity.principalId}, etc.
                if raw_event:
                    logger.info(f"Passing CloudTrail event context to policy")
                    p.data['event'] = raw_event.get('detail', {})
                    logger.debug(f"Event context: {json.dumps(p.data.get('event', {}), default=str)}")
                
                # Run the policy
                resources_matched = p.run()
                
                result = {
                    'policy': p.name,
                    'resource_type': p.resource_type,
                    'resources_matched': len(resources_matched) if resources_matched else 0,
                    'action_taken': not dryrun,
                    'dryrun': dryrun,
                    'event_context_provided': bool(raw_event),
                }
                
                logger.info(f"Policy {p.name} matched {result['resources_matched']} resources")
                results.append(result)
            
            return {
                'success': True,
                'policy_name': policy.get('name'),
                'event_info': event_info,
                'results': results,
                'dryrun': dryrun,
            }
            
        except Exception as e:
            logger.error(f"Cloud Custodian execution failed: {str(e)}")
            return {
                'success': False,
                'policy_name': policy.get('name'),
                'event_info': event_info,
                'error': str(e),
                'dryrun': dryrun,
            }
        
        finally:
            # Cleanup temporary file
            import os
            try:
                os.unlink(tmp_policy_path)
            except:
                pass
    
    def download_policy_mapping(self, bucket: str, key: str) -> Dict[str, Any]:
        """
        Download and parse policy mapping configuration from S3
        
        Args:
            bucket: S3 bucket name
            key: S3 object key
            
        Returns:
            Policy mapping configuration
            
        Raises:
            Exception: If download or parsing fails
        """
        logger.info(f"Downloading policy mapping from s3://{bucket}/{key}")
        
        try:
            response = self.s3_client.get_object(Bucket=bucket, Key=key)
            mapping_content = response['Body'].read().decode('utf-8')
            
            mapping_data = json.loads(mapping_content)
            
            logger.info(f"Successfully downloaded and parsed policy mapping")
            return mapping_data
            
        except Exception as e:
            logger.error(f"Failed to download policy mapping: {str(e)}")
            raise
