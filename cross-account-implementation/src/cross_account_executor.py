"""
Cross-Account Cloud Custodian Executor

This module handles cross-account policy execution by:
1. Extracting the source account ID from events
2. Assuming a role in the target account
3. Executing Cloud Custodian policies with temporary credentials
4. Downloading policies from S3
5. Filtering resources based on event context
"""

import boto3
import json
import logging
import os
import tempfile
import yaml
from botocore.exceptions import ClientError
from typing import Dict, Any, Optional

logger = logging.getLogger()
logger.setLevel(os.getenv('LOG_LEVEL', 'INFO'))


class CrossAccountSessionFactory:
    """
    Session factory that returns a specific boto3 session for Cloud Custodian
    """
    def __init__(self, session):
        self.session = session
    
    def __call__(self, *args, **kwargs):
        """Return the pre-configured cross-account session"""
        return self.session


class CrossAccountExecutor:
    """
    Handles cross-account Cloud Custodian policy execution
    """
    
    def __init__(self, account_id: str, region: str, role_name: str = None, external_id_prefix: str = None):
        """
        Initialize cross-account executor
        
        Args:
            account_id: Target AWS account ID
            region: AWS region for execution
            role_name: IAM role name to assume (default: CloudCustodianExecutionRole)
            external_id_prefix: Prefix for external ID (default: cloud-custodian)
        """
        self.account_id = account_id
        self.region = region
        self.role_name = role_name or os.getenv('CROSS_ACCOUNT_ROLE_NAME', 'CloudCustodianExecutionRole')
        self.external_id_prefix = external_id_prefix or os.getenv('EXTERNAL_ID_PREFIX', 'cloud-custodian')
        self.session = None
        self.credentials = None
        
    @property
    def role_arn(self) -> str:
        """Construct the IAM role ARN"""
        return f"arn:aws:iam::{self.account_id}:role/{self.role_name}"
    
    @property
    def external_id(self) -> str:
        """Construct the external ID for AssumeRole"""
        return f"{self.external_id_prefix}-{self.account_id}"
    
    def assume_role(self, duration_seconds: int = 900) -> Dict[str, Any]:
        """
        Assume role in target account using STS
        
        Args:
            duration_seconds: Session duration (default: 900 seconds / 15 minutes)
            
        Returns:
            Dict containing temporary credentials
            
        Raises:
            ClientError: If role assumption fails
        """
        sts_client = boto3.client('sts')
        
        try:
            logger.info(f"Assuming role in account {self.account_id}: {self.role_arn}")
            
            response = sts_client.assume_role(
                RoleArn=self.role_arn,
                RoleSessionName=f"custodian-session-{self.account_id}",
                ExternalId=self.external_id,
                DurationSeconds=duration_seconds
            )
            
            self.credentials = response['Credentials']
            
            # Create boto3 session with temporary credentials
            self.session = boto3.Session(
                aws_access_key_id=self.credentials['AccessKeyId'],
                aws_secret_access_key=self.credentials['SecretAccessKey'],
                aws_session_token=self.credentials['SessionToken'],
                region_name=self.region
            )
            
            logger.info(f"Successfully assumed role in account {self.account_id}")
            logger.info(f"Session expires at: {self.credentials['Expiration']}")
            
            return {
                'account_id': self.account_id,
                'role_arn': self.role_arn,
                'session': self.session,
                'expiration': self.credentials['Expiration'].isoformat()
            }
            
        except ClientError as e:
            error_code = e.response['Error']['Code']
            error_message = e.response['Error']['Message']
            
            logger.error(f"Failed to assume role in account {self.account_id}: {error_code} - {error_message}")
            
            if error_code == 'AccessDenied':
                logger.error("Verify that the trust policy in the target account allows this Lambda's role to assume it")
                logger.error(f"Also verify that the External ID '{self.external_id}' is correct")
            
            raise
    
    def get_client(self, service_name: str):
        """
        Get boto3 client with cross-account credentials
        
        Args:
            service_name: AWS service name (e.g., 'ec2', 's3', 'iam')
            
        Returns:
            boto3 client for the specified service
        """
        if not self.session:
            raise ValueError("Must call assume_role() before getting clients")
        
        return self.session.client(service_name)
    
    def download_policy_file(self, bucket: str, key: str) -> str:
        """
        Download policy file from S3 using cross-account credentials
        
        Args:
            bucket: S3 bucket name
            key: S3 object key
            
        Returns:
            Policy file content as string
        """
        # Use central account credentials for S3 access (policies stored in central account)
        s3_client = boto3.client('s3', region_name=self.region)
        
        logger.info(f"Downloading policy file from s3://{bucket}/{key}")
        
        try:
            response = s3_client.get_object(Bucket=bucket, Key=key)
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
        Execute Cloud Custodian policy using assumed role credentials
        
        Args:
            policy_config: Policy configuration (the actual policy YAML dict)
            event_info: Event information from EventBridge
            dryrun: Whether to run in dry-run mode
            
        Returns:
            Dict containing execution results
        """
        if not self.session:
            raise ValueError("Must call assume_role() before executing policies")
        
        logger.info(f"Executing policy in account {self.account_id}")
        logger.info(f"Dry-run mode: {dryrun}")
        
        try:
            # policy_config is already the parsed policy dict
            policy = policy_config
            policy_name = policy.get('name', 'unknown')
            
            logger.info(f"Executing policy: {policy_name}")
            
            # Execute the policy using Cloud Custodian with cross-account session
            result = self._execute_custodian_policy(policy, event_info, dryrun)
            
            logger.info(f"Policy execution completed in account {self.account_id}")
            return result
            
        except Exception as e:
            logger.error(f"Policy execution failed: {str(e)}", exc_info=True)
            return {
                'success': False,
                'account_id': self.account_id,
                'policy_name': policy_config.get('name', 'unknown'),
                'error': str(e),
                'dryrun': dryrun
            }
    
    def _execute_custodian_policy(
        self,
        policy: Dict[str, Any],
        event_info: Dict[str, Any],
        dryrun: bool
    ) -> Dict[str, Any]:
        """
        Execute Cloud Custodian policy using the c7n library with cross-account session
        
        Args:
            policy: Single policy configuration
            event_info: Event information (includes raw CloudTrail event)
            dryrun: Dry-run mode flag
            
        Returns:
            Execution results
        """
        from c7n.policy import PolicyCollection
        from c7n.config import Config
        from c7n import resources
        
        # Load AWS Cloud Custodian resource providers
        try:
            resources.load_resources(['aws.*'])
        except Exception as e:
            logger.warning(f"Could not load specific AWS resources, falling back to default: {e}")
            import c7n.resources.aws
        
        logger.info(f"Executing Cloud Custodian policy: {policy.get('name')} in account {self.account_id}")
        
        # Add resource-specific filters based on event context
        if 'resource' in policy:
            # Filter by specific bucket if it's an S3 policy
            bucket_name = event_info.get('bucket_name')
            if bucket_name and policy.get('resource') == 's3':
                logger.info(f"Adding bucket filter for: {bucket_name}")
                
                if 'filters' not in policy:
                    policy['filters'] = []
                
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
        
        # Prepare policy configuration
        policy_config = {
            'policies': [policy]
        }
        
        # Create temporary file for policy
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yml', delete=False) as tmp_file:
            yaml.dump(policy_config, tmp_file)
            tmp_policy_path = tmp_file.name
        
        try:
            # Extract raw CloudTrail event data for policy context
            raw_event = event_info.get('raw_event', {})
            
            # Create policy collection with cross-account session
            options = Config.empty(
                region=self.region,
                account_id=self.account_id,
                log_group=f'/c7n/lambda/cloud-custodian-cross-account',
                output_dir='/tmp/custodian-output',
                cache='/tmp/custodian-cache',
                dryrun=dryrun,
            )
            
            # Load policies (don't set session_factory on options - it causes serialization errors)
            collection = PolicyCollection.from_data(policy_config, options)
            
            # Execute policies with cross-account session and event context
            results = []
            
            for p in collection:
                logger.info(f"Running policy: {p.name} in account {self.account_id}")
                
                # Access the resource manager property (it's lazy-loaded)
                # and override its get_client method to use our cross-account session
                try:
                    # The resource_manager property triggers lazy loading
                    rm = p.resource_manager
                    if rm:
                        logger.info(f"Overriding resource manager get_client for {p.resource_type}")
                        # Store reference to self.session in local variable to avoid closure issues
                        cross_account_session = self.session
                        cross_account_region = self.region
                        cross_account_id = self.account_id
                        
                        # Override get_client method to use our cross-account session
                        def get_client_with_session(service_name):
                            logger.info(f"Creating {service_name} client with cross-account credentials for account {cross_account_id}")
                            return cross_account_session.client(service_name, region_name=cross_account_region)
                        
                        rm.get_client = get_client_with_session
                except Exception as e:
                    logger.warning(f"Could not override resource manager get_client: {e}")
                
                # Set event context if available
                if raw_event:
                    logger.info(f"Passing CloudTrail event context to policy")
                    p.data['event'] = raw_event.get('detail', {})
                    logger.debug(f"Event context: {json.dumps(p.data.get('event', {}), default=str)}")
                
                # Run the policy with cross-account credentials
                resources_matched = p.run()
                
                result = {
                    'policy': p.name,
                    'account_id': self.account_id,
                    'resource_type': p.resource_type,
                    'resources_matched': len(resources_matched) if resources_matched else 0,
                    'action_taken': not dryrun,
                    'dryrun': dryrun,
                    'event_context_provided': bool(raw_event),
                }
                
                logger.info(f"Policy {p.name} matched {result['resources_matched']} resources in account {self.account_id}")
                results.append(result)
            
            return {
                'success': True,
                'account_id': self.account_id,
                'policy_name': policy.get('name'),
                'event_info': event_info,
                'results': results,
                'dryrun': dryrun,
            }
            
        except Exception as e:
            logger.error(f"Cloud Custodian execution failed in account {self.account_id}: {str(e)}")
            return {
                'success': False,
                'account_id': self.account_id,
                'policy_name': policy.get('name'),
                'event_info': event_info,
                'error': str(e),
                'dryrun': dryrun,
            }
        
        finally:
            # Cleanup temporary file
            try:
                os.unlink(tmp_policy_path)
            except:
                pass
    
    def test_connectivity(self) -> Dict[str, Any]:
        """
        Test connectivity and permissions in target account
        
        Returns:
            Dict with test results
        """
        if not self.session:
            raise ValueError("Must call assume_role() before testing connectivity")
        
        tests = {}
        
        # Test STS GetCallerIdentity
        try:
            sts = self.session.client('sts')
            identity = sts.get_caller_identity()
            tests['sts'] = {
                'success': True,
                'account': identity['Account'],
                'arn': identity['Arn']
            }
        except Exception as e:
            tests['sts'] = {'success': False, 'error': str(e)}
        
        # Test EC2 DescribeInstances
        try:
            ec2 = self.session.client('ec2')
            response = ec2.describe_instances(MaxResults=5)
            tests['ec2'] = {
                'success': True,
                'instance_count': sum(len(r['Instances']) for r in response['Reservations'])
            }
        except Exception as e:
            tests['ec2'] = {'success': False, 'error': str(e)}
        
        # Test S3 ListBuckets
        try:
            s3 = self.session.client('s3')
            response = s3.list_buckets()
            tests['s3'] = {
                'success': True,
                'bucket_count': len(response['Buckets'])
            }
        except Exception as e:
            tests['s3'] = {'success': False, 'error': str(e)}
        
        return {
            'account_id': self.account_id,
            'tests': tests
        }


def extract_account_from_event(event: Dict[str, Any]) -> Optional[str]:
    """
    Extract AWS account ID from EventBridge event
    
    Args:
        event: EventBridge event payload
        
    Returns:
        AWS account ID or None if not found
    """
    # Direct account field (most common)
    if 'account' in event:
        return event['account']
    
    # From detail object
    if 'detail' in event and isinstance(event['detail'], dict):
        detail = event['detail']
        
        # CloudTrail events
        if 'userIdentity' in detail and 'accountId' in detail['userIdentity']:
            return detail['userIdentity']['accountId']
        
        # Security Hub findings
        if 'AwsAccountId' in detail:
            return detail['AwsAccountId']
        
        # GuardDuty findings
        if 'accountId' in detail:
            return detail['accountId']
    
    logger.warning("Could not extract account ID from event")
    return None


def extract_region_from_event(event: Dict[str, Any]) -> str:
    """
    Extract AWS region from EventBridge event
    
    Args:
        event: EventBridge event payload
        
    Returns:
        AWS region (defaults to us-east-1 if not found)
    """
    # Direct region field
    if 'region' in event:
        return event['region']
    
    # From detail object
    if 'detail' in event and isinstance(event['detail'], dict):
        detail = event['detail']
        
        # CloudTrail events
        if 'awsRegion' in detail:
            return detail['awsRegion']
        
        # Security Hub findings
        if 'Region' in detail:
            return detail['Region']
    
    # Default to us-east-1
    default_region = 'us-east-1'
    logger.warning(f"Could not extract region from event, using default: {default_region}")
    return default_region
