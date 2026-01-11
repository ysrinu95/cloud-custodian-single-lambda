"""
Cross-Account Cloud Custodian Executor

This module handles cross-account policy execution by:
1. Extracting the source account ID from events
2. Assuming a role in the target account
3. Executing Cloud Custodian policies with temporary credentials
4. Downloading policies from S3
5. Filtering resources based on event context

The module uses event_filter_builder for flexible resource filtering across
all AWS services and event sources (CloudTrail, GuardDuty, SecurityHub, Config).
"""

import boto3
import json
import logging
import os
import tempfile
import yaml
from botocore.exceptions import ClientError
from typing import Dict, Any, Optional

# Import the event filter builder for resource filtering
import event_filter_builder

logger = logging.getLogger()
logger.setLevel(os.getenv('LOG_LEVEL', 'INFO'))

# Note: Cloud Custodian logger configuration moved to _execute_custodian_policy()
# (after c7n imports, since c7n resets logging configuration on import)


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
    
    def __init__(self, account_id: str, region: str, role_name: str = None, external_id_prefix: str = None, environment: str = None):
        """
        Initialize cross-account executor
        
        Args:
            account_id: Target AWS account ID
            region: AWS region for execution
            role_name: IAM role name to assume (default: CloudCustodianExecutionRole)
            external_id_prefix: Prefix for external ID (default: cloud-custodian)
            environment: Environment name (e.g., dev, prod) from account mapping
        """
        self.account_id = account_id
        self.region = region
        self.role_name = role_name or os.getenv('CROSS_ACCOUNT_ROLE_NAME', 'CloudCustodianExecutionRole')
        self.external_id_prefix = external_id_prefix or os.getenv('EXTERNAL_ID_PREFIX', 'cloud-custodian')
        self.environment = environment
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
            
            # Verify the assumed role identity
            try:
                sts_verify = self.session.client('sts')
                identity = sts_verify.get_caller_identity()
                logger.info(f"VERIFIED: Assumed role identity - Account: {identity['Account']}, ARN: {identity['Arn']}")
                if identity['Account'] != self.account_id:
                    logger.error(f"WARNING: Assumed role account {identity['Account']} does not match target account {self.account_id}")
            except Exception as e:
                logger.warning(f"Could not verify assumed role identity: {e}")
            
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
        
        This refactored version uses event_filter_builder for cleaner resource filtering
        and supports all AWS services consistently.
        
        Args:
            policy: Single policy configuration
            event_info: Event information (includes raw event and generic_resources)
            dryrun: Dry-run mode flag
            
        Returns:
            Execution results
        """
        from c7n.policy import PolicyCollection
        from c7n.config import Config
        from c7n import resources
        
        # CRITICAL: Configure Cloud Custodian loggers AFTER import (c7n resets logging on import)
        c7n_loggers = ['custodian', 'c7n', 'c7n.policy', 'c7n.policies', 'custodian.policy',
                       'custodian.filters', 'custodian.actions', 'custodian.resources', 'custodian.output']
        for logger_name in c7n_loggers:
            c7n_logger = logging.getLogger(logger_name)
            c7n_logger.setLevel(logging.DEBUG)
            c7n_logger.propagate = True
        logger.info("Cloud Custodian loggers configured to DEBUG level")
        
        # Load AWS Cloud Custodian resource providers
        try:
            resources.load_resources(['aws.*'])
        except Exception as e:
            logger.warning(f"Could not load specific AWS resources, falling back to default: {e}")
            import c7n.resources.aws
        
        logger.info(f"Executing Cloud Custodian policy: {policy.get('name')} in account {self.account_id}")
        
        # =======================================================================
        # STEP 1: BUILD FILTERS USING EVENT_FILTER_BUILDER
        # =======================================================================
        resource_type = policy.get('resource', '')
        generic_resources = event_info.get('generic_resources', {})
        
        if generic_resources and resource_type:
            logger.info(f"Building filters for resource type: {resource_type}")
            logger.info(f"Generic resources: arns={len(generic_resources.get('arns', []))}, "
                       f"ids={len(generic_resources.get('ids', []))}, "
                       f"names={len(generic_resources.get('names', []))}")
            
            # Use event_filter_builder to get filters and optionally prefetch resources
            filter_result = event_filter_builder.build_filters_and_resources(
                event_info=event_info,
                resource_type=resource_type,
                session=self.session,
                region=self.region
            )
            logger.info(f"Filter result: {filter_result}") 
            filters = filter_result.get('filters', [])
            logger.info(f"Built filters: {filters}")
            provided_resources = filter_result.get('provided_resources')
            logger.info(f"Provided resources: {provided_resources}")
            
            if filters:
                logger.info(f"Built {len(filters)} filters from event")
                if 'filters' not in policy:
                    policy['filters'] = []
                # Insert event-based filters at the beginning
                for f in reversed(filters):
                    policy['filters'].insert(0, f)
            
            if provided_resources:
                logger.info(f"Pre-fetched {len(provided_resources)} resources from AWS API")
        else:
            logger.info(f"No generic resources found in event, using policy filters as-is")
            provided_resources = None
        
        # =======================================================================
        # ENRICH PROVIDED RESOURCES WITH CREATOR INFO (before policy execution)
        # =======================================================================
        # This must happen BEFORE policy runs because Cloud Custodian writes to
        # SQS during execution, and we need creator_name in the message
        creator_name = event_info.get('creator_name')
        if provided_resources and creator_name:
            logger.info(f"Enriching {len(provided_resources)} pre-fetched resources with creator: {creator_name}")
            for idx, resource in enumerate(provided_resources):
                if isinstance(resource, dict):
                    # Always set c7n:CreatorName
                    resource['c7n:CreatorName'] = creator_name
                    logger.debug(f"Added c7n:CreatorName='{creator_name}' to resource {idx}: {resource.get('Name', resource.get('InstanceId', 'unknown'))}")
                    
                    # For EC2, also add to Tags for visibility
                    if policy.get('resource') == 'aws.ec2' and 'Tags' in resource:
                        # Check if tag already exists
                        has_creator_tag = any(tag.get('Key') == 'c7n:CreatorName' for tag in resource.get('Tags', []))
                        if not has_creator_tag:
                            resource['Tags'].append({'Key': 'c7n:CreatorName', 'Value': creator_name})
                            logger.debug(f"Added c7n:CreatorName tag to EC2 instance {resource.get('InstanceId')}")
        elif provided_resources:
            logger.warning(f"Pre-fetched {len(provided_resources)} resources but NO creator_name found in event_info!")
            logger.warning(f"event_info keys: {list(event_info.keys())}")
        
        # =======================================================================
        # STEP 2: LEGACY COMPATIBILITY - Support old event_info fields
        # =======================================================================
        # For backward compatibility with existing code that passes specific fields
        # These take precedence over generic filters if present
        
        legacy_fields_map = {
            'instance_id': ('aws.ec2', 'InstanceId'),
            'bucket_name': ('aws.s3', 'Name'),
            'username': ('aws.iam-user', 'UserName'),
            'group_id': ('aws.security-group', 'GroupId'),
            'load_balancer_arn': ('aws.app-elb', 'LoadBalancerArn'),
        }
        
        for field_name, (expected_resource, filter_key) in legacy_fields_map.items():
            field_value = event_info.get(field_name)
            if field_value and policy.get('resource') == expected_resource:
                logger.info(f"Applying legacy filter: {filter_key}={field_value}")
                if 'filters' not in policy:
                    policy['filters'] = []
                # Remove any existing filters for this key
                policy['filters'] = [f for f in policy['filters'] 
                                   if not (f.get('key') == filter_key)]
                # Add the legacy filter
                policy['filters'].insert(0, {
                    'type': 'value',
                    'key': filter_key,
                    'value': field_value
                })
        
        # Special handling for listener ARN -> load balancer ARN extraction
        listener_arn = event_info.get('listener_arn')
        if listener_arn and policy.get('resource') == 'aws.app-elb':
            try:
                # Extract load balancer ARN from listener ARN
                parts = listener_arn.split(':')
                resource_part = parts[5]
                resource_parts = resource_part.split('/')
                lb_arn = ':'.join(parts[:5]) + ':loadbalancer/' + '/'.join(resource_parts[1:4])
                logger.info(f"Extracted ALB ARN from listener: {lb_arn}")
                
                if 'filters' not in policy:
                    policy['filters'] = []
                policy['filters'].insert(0, {
                    'type': 'value',
                    'key': 'LoadBalancerArn',
                    'value': lb_arn
                })
            except Exception as e:
                logger.warning(f"Could not extract load balancer ARN from listener ARN: {e}")
        
        # =======================================================================
        # STEP 3: PREPARE AND EXECUTE POLICY
        # =======================================================================
        policy_config = {
            'policies': [policy]
        }
        
        # Create temporary file for policy
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yml', delete=False) as tmp_file:
            yaml.dump(policy_config, tmp_file)
            tmp_policy_path = tmp_file.name
        
        try:
            # Extract raw event data for policy context
            raw_event = event_info.get('raw_event', {})
            
            # Create policy collection with cross-account session
            # Enable verbose mode for detailed debug output from Cloud Custodian
            options = Config.empty(
                region=self.region,
                account_id=self.account_id,
                log_group=f'/c7n/lambda/cloud-custodian-cross-account',
                output_dir='/tmp/custodian-output',
                cache='/tmp/custodian-cache',
                dryrun=dryrun,
                verbose=True,  # Enable verbose mode for detailed filter/action execution logs
                variables={
                    'account_id': self.account_id,
                    'region': self.region,
                    'environment': self.environment or 'unknown'
                } if self.environment else None
            )
            
            # Load policies
            collection = PolicyCollection.from_data(policy_config, options)
            # Execute policies with cross-account session
            results = []
            
            for p in collection:
                logger.info(f"Running policy: {p.name} in account {self.account_id}")                
                # Store session references
                cross_account_session = self.session
                cross_account_region = self.region
                cross_account_id = self.account_id
                policy_resource_type = p.resource_type
                
                # Map Cloud Custodian resource types to AWS service names
                resource_type_to_service = {
                    'aws.ec2': 'ec2',
                    'aws.s3': 's3',
                    'aws.app-elb': 'elbv2',
                    'aws.elb': 'elb',
                    'aws.distribution': 'cloudfront',
                    'aws.security-group': 'ec2',
                    'aws.ami': 'ec2',
                    'aws.ebs': 'ec2',
                    'aws.ebs-snapshot': 'ec2',
                    'aws.rds': 'rds',
                    'aws.iam-user': 'iam',
                    'aws.ecr': 'ecr',
                    'aws.eks': 'eks',
                    'aws.cache-cluster': 'elasticache',
                    'aws.elasticache': 'elasticache',
                    'aws.efs': 'efs',
                    'aws.kinesis': 'kinesis',
                    'aws.sns': 'sns',
                }
                
                # Create cross-account client factory
                def get_client_with_session(*args):
                    service_name = args[-1] if args else resource_type_to_service.get(policy_resource_type, 'ec2')
                    logger.info(f"Creating {service_name} client with cross-account credentials for account {cross_account_id}")
                    return cross_account_session.client(service_name, region_name=cross_account_region)
                
                # Override resource manager to use cross-account session
                rm = None  # Initialize to avoid unbound variable warning
                try:
                    rm = p.resource_manager
                    if rm:
                        logger.info(f"Configuring cross-account session for {p.resource_type}")
                        rm.get_client = get_client_with_session
                        rm.session_factory = lambda *args, **kwargs: cross_account_session
                        rm._session = cross_account_session
                        
                        # Override action clients
                        for action in p.resource_manager.actions:
                            logger.info(f"Configuring action '{action.type}' for cross-account execution")
                            action.manager.get_client = get_client_with_session
                            action.manager.session_factory = lambda *args, **kwargs: cross_account_session
                            action.manager._session = cross_account_session
                except Exception as e:
                    logger.warning(f"Could not configure cross-account session: {e}")
                
                # Pass event context to policy
                # For Security Hub, GuardDuty, Config events - preserve full structure for template access
                if raw_event:
                    logger.info(f"Adding event context to policy for template rendering")
                    # Store the full raw event so templates can access {{ event.detail.findings[0]... }}
                    # Cloud Custodian will include p.data['event'] in the SQS notification message
                    p.data['event'] = raw_event
                
                # Monkey-patch SQS send_message to add invocation ID as message attribute
                # This ensures all messages published by Cloud Custodian include the invocation ID
                invocation_id = os.getenv('C7N_INVOCATION_ID')
                if invocation_id:
                    logger.info(f"Injecting invocation ID {invocation_id} into SQS messages")
                    import botocore.client
                    
                    # Store original make_api_call method if not already stored
                    if not hasattr(botocore.client.BaseClient, '_original_make_api_call'):
                        botocore.client.BaseClient._original_make_api_call = botocore.client.BaseClient._make_api_call
                    
                    def make_api_call_with_invocation_id(self, operation_name, api_params):
                        # Only modify SQS SendMessage operations
                        if operation_name == 'SendMessage' and self._service_model.service_name == 'sqs':
                            # CRITICAL: Get current invocation ID dynamically, not from closure
                            current_invocation_id = os.getenv('C7N_INVOCATION_ID')
                            if current_invocation_id:
                                logger.info(f"🔧 Intercepting SQS SendMessage - adding InvocationId: {current_invocation_id}")
                                if 'MessageAttributes' not in api_params:
                                    api_params['MessageAttributes'] = {}
                                api_params['MessageAttributes']['InvocationId'] = {
                                    'StringValue': current_invocation_id,
                                    'DataType': 'String'
                                }
                                logger.info(f"✅ MessageAttributes now includes: {list(api_params['MessageAttributes'].keys())}")
                        return botocore.client.BaseClient._original_make_api_call(self, operation_name, api_params)
                    
                    # Replace the method for this policy execution
                    botocore.client.BaseClient._make_api_call = make_api_call_with_invocation_id
                
                # Run the policy (resources already enriched with creator info if pre-fetched)
                # Cloud Custodian's Policy.run() doesn't accept arguments
                
                # ===================================================================
                # OLD CODE (COMMENTED OUT - bypassed filter execution):
                # ===================================================================
                # if provided_resources:
                #     logger.info(f"Evaluating policy against {len(provided_resources)} pre-fetched resources")
                #     # Override resources method to use pre-fetched resources
                #     original_resources = rm.resources
                #     rm.resources = lambda: provided_resources  # ← BYPASSED FILTERS!
                #     
                #     try:
                #         resources_matched = p.run()
                #     finally:
                #         rm.resources = original_resources
                # else:
                #     logger.info(f"Running policy with standard resource enumeration")
                #     resources_matched = p.run()
                # ===================================================================
                
                # NEW CODE (v83 - properly applies filters):
                if provided_resources:
                    logger.info(f"Evaluating policy against {len(provided_resources)} pre-fetched resources")
                    # Apply filters to pre-fetched resources (mimics CloudTrail mode behavior)
                    # This ensures filters are properly applied via filter_resources()
                    initial_count = len(provided_resources)
                    resources_matched = rm.filter_resources(provided_resources, event=raw_event)
                    logger.info(f"Filter results: {initial_count} resources → {len(resources_matched)} matched")
                    
                    # Execute actions on matched resources (if not dryrun)
                    if resources_matched and not dryrun:
                        logger.info(f"Executing {len(rm.actions)} actions on {len(resources_matched)} resources")
                        for action in rm.actions:
                            logger.info(f"Executing action: {action.type}")
                            action.process(resources_matched)
                else:
                    logger.info(f"Running policy with standard resource enumeration")
                    resources_matched = p.run()
                    
                    # If resources weren't pre-fetched, enrich them now
                    creator_name = event_info.get('creator_name')
                    if creator_name and resources_matched:
                        logger.info(f"Enriching {len(resources_matched)} enumerated resources with creator: {creator_name}")
                        for resource in resources_matched:
                            if isinstance(resource, dict):
                                resource['c7n:CreatorName'] = creator_name
                
                result = {
                    'policy': p.name,
                    'account_id': self.account_id,
                    'resource_type': p.resource_type,
                    'resources_matched': len(resources_matched) if resources_matched else 0,
                    'action_taken': not dryrun,
                    'dryrun': dryrun,
                    'event_context_provided': bool(raw_event),
                    'provided_resources': len(provided_resources) if provided_resources else 0,
                }
                
                logger.info(f"Policy {p.name} matched {result['resources_matched']} resources")
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
