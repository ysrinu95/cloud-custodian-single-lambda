"""
Event Filter Builder (lambda package copy)

This copy lives in the lambda function package so the executor can import
the logic locally using a relative import. Keep this file synchronized with
the canonical implementation in `c7n/src/event_filter_builder.py`.

This module provides comprehensive resource filtering for ALL AWS services
based on events from CloudTrail, GuardDuty, Security Hub, and AWS Config.
"""
import logging
from typing import Dict, Any, Optional, List
from enum import Enum

logger = logging.getLogger(__name__)


class EventSource(Enum):
    """Supported event sources"""
    CLOUDTRAIL = "cloudtrail"
    GUARDDUTY = "guardduty"
    SECURITY_HUB = "securityhub"
    CONFIG = "config"
    UNKNOWN = "unknown"


# ============================================================================
# COMPREHENSIVE AWS RESOURCE MAPPINGS
# ============================================================================

# ARN field mappings for AWS resources
ARN_FIELD_MAPPING = {
    # Compute
    'aws.ec2': 'Arn',
    'aws.lambda': 'FunctionArn',
    'aws.lambda-layer': 'LayerVersionArn',
    'aws.ecs-cluster': 'clusterArn',
    'aws.ecs-service': 'serviceArn',
    'aws.ecs-task': 'taskArn',
    'aws.ecs-task-definition': 'taskDefinitionArn',
    'aws.eks': 'arn',
    
    # Load Balancing
    'aws.app-elb': 'LoadBalancerArn',
    'aws.elb': 'LoadBalancerArn',
    
    # Storage
    'aws.s3': 'Arn',
    'aws.ebs': 'VolumeArn',
    'aws.ebs-snapshot': 'SnapshotArn',
    'aws.efs': 'FileSystemArn',
    'aws.dynamodb-table': 'TableArn',
    
    # Database
    'aws.rds': 'DBInstanceArn',
    'aws.rds-cluster': 'DBClusterArn',
    'aws.rds-snapshot': 'DBSnapshotArn',
    'aws.elasticache': 'ARN',
    'aws.elasticache-cluster': 'ARN',
    'aws.elasticache-snapshot': 'ARN',
    'aws.timestream-database': 'Arn',
    'aws.timestream-table': 'Arn',
    
    # Networking
    'aws.vpc': 'VpcArn',
    'aws.subnet': 'SubnetArn',
    'aws.security-group': 'GroupArn',
    'aws.network-acl': 'NetworkAclArn',
    'aws.internet-gateway': 'InternetGatewayArn',
    'aws.nat-gateway': 'NatGatewayArn',
    'aws.vpc-endpoint': 'VpcEndpointArn',
    'aws.network-interface': 'NetworkInterfaceArn',
    
    # Security & Identity
    'aws.iam-user': 'Arn',
    'aws.iam-role': 'Arn',
    'aws.iam-policy': 'Arn',
    'aws.iam-group': 'Arn',
    'aws.kms': 'Arn',
    'aws.kms-key': 'KeyArn',
    'aws.acm-certificate': 'CertificateArn',
    'aws.secretsmanager': 'ARN',
    'aws.secrets-manager': 'ARN',
    'aws.cognito-user-pool': 'Arn',
    'aws.cognito-identity-pool': 'IdentityPoolArn',
    
    # Application Integration
    'aws.sns': 'TopicArn',
    'aws.sqs': 'QueueArn',
    'aws.events': 'Arn',
    'aws.event-bus': 'Arn',
    'aws.event-rule': 'Arn',
    'aws.kinesis': 'StreamARN',
    'aws.kinesis-firehose': 'DeliveryStreamARN',
    
    # Analytics & Search
    'aws.elasticsearch': 'ARN',
    'aws.opensearch': 'ARN',
    'aws.glue-database': 'DatabaseArn',
    'aws.glue-table': 'TableArn',
    
    # Developer Tools
    'aws.codecommit': 'Arn',
    'aws.codebuild': 'Arn',
    'aws.codepipeline': 'Arn',
    
    # Containers & Registry
    'aws.ecr': 'repositoryArn',
    'aws.ecr-repository': 'repositoryArn',
    
    # CDN & Edge
    'aws.cloudfront': 'ARN',
    'aws.cloudfront-distribution': 'ARN',
    'aws.distribution': 'ARN',  # CloudFront distribution
    
    # Security Services
    'aws.waf': 'ARN',
    'aws.waf-regional': 'ARN',
    'aws.wafv2': 'ARN',
    'aws.shield-protection': 'ProtectionArn',
    'aws.guardduty-detector': 'DetectorArn',
    'aws.inspector-assessment-template': 'Arn',
    'aws.securityhub-hub': 'HubArn',
    'aws.config-rule': 'ConfigRuleArn',
    
    # Monitoring & Logging
    'aws.cloudwatch-alarm': 'AlarmArn',
    'aws.cloudwatch-log-group': 'arn',
    'aws.ses-identity': 'IdentityArn',
}

# ID field mappings for AWS resources
ID_FIELD_MAPPING = {
    # Compute
    'aws.ec2': 'InstanceId',
    'aws.ami': 'ImageId',
    'aws.lambda': 'FunctionName',  # Lambda can use name as ID
    'aws.ecs-cluster': 'clusterArn',  # ECS uses ARN as ID
    'aws.eks': 'name',
    
    # Storage
    'aws.ebs': 'VolumeId',
    'aws.ebs-snapshot': 'SnapshotId',
    'aws.efs': 'FileSystemId',
    
    # Database
    'aws.rds': 'DBInstanceIdentifier',
    'aws.rds-cluster': 'DBClusterIdentifier',
    'aws.rds-snapshot': 'DBSnapshotIdentifier',
    'aws.elasticache': 'CacheClusterId',
    'aws.elasticache-cluster': 'CacheClusterId',
    'aws.dynamodb-table': 'TableName',
    
    # Networking
    'aws.vpc': 'VpcId',
    'aws.subnet': 'SubnetId',
    'aws.security-group': 'GroupId',
    'aws.network-acl': 'NetworkAclId',
    'aws.internet-gateway': 'InternetGatewayId',
    'aws.nat-gateway': 'NatGatewayId',
    'aws.vpc-endpoint': 'VpcEndpointId',
    'aws.network-interface': 'NetworkInterfaceId',
    
    # Security
    'aws.kms': 'KeyId',
    'aws.kms-key': 'KeyId',
    'aws.acm-certificate': 'CertificateArn',  # ACM uses ARN
    
    # CDN
    'aws.cloudfront': 'Id',
    'aws.cloudfront-distribution': 'Id',
    'aws.distribution': 'Id',  # CloudFront distribution
    
    # Monitoring
    'aws.cloudwatch-alarm': 'AlarmName',
    'aws.cloudwatch-log-group': 'logGroupName',
}

# Name field mappings for AWS resources
NAME_FIELD_MAPPING = {
    # Storage
    'aws.s3': 'Name',
    
    # Identity
    'aws.iam-user': 'UserName',
    'aws.iam-role': 'RoleName',
    'aws.iam-policy': 'PolicyName',
    'aws.iam-group': 'GroupName',
    
    # Compute
    'aws.lambda': 'FunctionName',
    'aws.eks': 'name',
    
    # Database
    'aws.dynamodb-table': 'TableName',
    'aws.rds': 'DBInstanceIdentifier',
    'aws.rds-cluster': 'DBClusterIdentifier',
    
    # Application Integration
    'aws.sns': 'TopicName',
    'aws.sqs': 'QueueName',
    'aws.kinesis': 'StreamName',
    'aws.kinesis-firehose': 'DeliveryStreamName',
    
    # Search & Analytics
    'aws.elasticsearch': 'DomainName',
    'aws.opensearch': 'DomainName',
    
    # Developer Tools
    'aws.codecommit': 'repositoryName',
    'aws.ecr': 'repositoryName',
    
    # Security
    'aws.cognito-user-pool': 'Name',
    'aws.secretsmanager': 'Name',
    'aws.secrets-manager': 'Name',
    'aws.kms': 'KeyId',
    
    # Monitoring
    'aws.cloudwatch-alarm': 'AlarmName',
    'aws.cloudwatch-log-group': 'logGroupName',
    'aws.ses-identity': 'Identity',
    
    # Events
    'aws.event-bus': 'Name',
    'aws.event-rule': 'Name',
}


# ============================================================================
# EVENT SOURCE PARSERS
# ============================================================================

def parse_cloudtrail_event(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Parse CloudTrail event to extract generic resources
    
    Args:
        event: CloudTrail event from EventBridge
        
    Returns:
        Dict with arns, ids, names lists
    """
    detail = event.get('detail', {})
    
    resources = {
        'arns': [],
        'ids': [],
        'names': [],
        'event_name': detail.get('eventName', ''),
        'event_source': detail.get('eventSource', ''),
        'user_identity': detail.get('userIdentity', {}),
    }
    
    # Extract from CloudTrail resources field
    for resource in detail.get('resources', []):
        arn = resource.get('ARN')
        if arn:
            resources['arns'].append(arn)
    
    # Extract from request/response parameters
    request_params = detail.get('requestParameters', {}) or {}
    response_elements = detail.get('responseElements', {}) or {}
    
    # Common ARN patterns in responses
    for key in ['arn', 'Arn', 'ARN', 'resourceArn', 'ResourceArn']:
        if key in response_elements and response_elements[key]:
            resources['arns'].append(response_elements[key])
        if key in request_params and request_params[key]:
            resources['arns'].append(request_params[key])
    
    # Common ID patterns
    id_keys = ['instanceId', 'volumeId', 'snapshotId', 'imageId', 'groupId', 
               'vpcId', 'subnetId', 'keyId', 'clusterId', 'clusterName']
    for key in id_keys:
        if key in response_elements and response_elements[key]:
            resources['ids'].append(response_elements[key])
        if key in request_params and request_params[key]:
            resources['ids'].append(request_params[key])
    
    # Common name patterns
    name_keys = ['bucketName', 'functionName', 'userName', 'roleName', 
                 'streamName', 'topicName', 'queueName', 'repositoryName']
    for key in name_keys:
        if key in response_elements and response_elements[key]:
            resources['names'].append(response_elements[key])
        if key in request_params and request_params[key]:
            resources['names'].append(request_params[key])
    
    return resources


def parse_guardduty_finding(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Parse GuardDuty finding to extract generic resources
    
    Args:
        event: GuardDuty finding event from EventBridge
        
    Returns:
        Dict with arns, ids, names lists
    """
    detail = event.get('detail', {})
    
    resources = {
        'arns': [],
        'ids': [],
        'names': [],
        'finding_type': detail.get('type', ''),
        'severity': detail.get('severity', 0),
    }
    
    # Extract from resource field
    resource = detail.get('resource', {})
    
    # EC2 Instance
    if 'instanceDetails' in resource:
        instance = resource['instanceDetails']
        instance_id = instance.get('instanceId')
        if instance_id:
            resources['ids'].append(instance_id)
    
    # Access Key
    if 'accessKeyDetails' in resource:
        access_key = resource['accessKeyDetails']
        user_name = access_key.get('userName')
        if user_name:
            resources['names'].append(user_name)
    
    # S3 Bucket
    if 's3BucketDetails' in resource:
        for bucket in resource.get('s3BucketDetails', []):
            bucket_name = bucket.get('name')
            bucket_arn = bucket.get('arn')
            if bucket_name:
                resources['names'].append(bucket_name)
            if bucket_arn:
                resources['arns'].append(bucket_arn)
    
    # EKS Cluster
    if 'eksClusterDetails' in resource:
        cluster = resource['eksClusterDetails']
        cluster_name = cluster.get('name')
        cluster_arn = cluster.get('arn')
        if cluster_name:
            resources['names'].append(cluster_name)
        if cluster_arn:
            resources['arns'].append(cluster_arn)
    
    return resources


def parse_securityhub_finding(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Parse Security Hub finding to extract generic resources
    
    Args:
        event: Security Hub finding event from EventBridge
        
    Returns:
        Dict with arns, ids, names lists
    """
    detail = event.get('detail', {})
    findings = detail.get('findings', [])
    
    resources = {
        'arns': [],
        'ids': [],
        'names': [],
        'finding_types': [],
    }
    
    for finding in findings:
        # Extract resource identifiers
        for resource in finding.get('Resources', []):
            resource_id = resource.get('Id')
            resource_type = resource.get('Type', '')
            
            if resource_id:
                # Determine if it's an ARN, ID, or name
                if resource_id.startswith('arn:'):
                    resources['arns'].append(resource_id)
                elif '/' in resource_id or ':' in resource_id:
                    resources['ids'].append(resource_id)
                else:
                    resources['names'].append(resource_id)
        
        # Extract finding type
        finding_type = finding.get('Type', '')
        if finding_type:
            resources['finding_types'].append(finding_type)
    
    return resources


def parse_config_event(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Parse AWS Config event to extract generic resources
    
    Args:
        event: Config event from EventBridge
        
    Returns:
        Dict with arns, ids, names lists
    """
    detail = event.get('detail', {})
    
    resources = {
        'arns': [],
        'ids': [],
        'names': [],
        'resource_type': detail.get('resourceType', ''),
        'compliance_type': detail.get('newEvaluationResult', {}).get('complianceType', ''),
    }
    
    # Extract resource ID and ARN
    resource_id = detail.get('resourceId')
    if resource_id:
        if resource_id.startswith('arn:'):
            resources['arns'].append(resource_id)
        else:
            resources['ids'].append(resource_id)
    
    # Extract from configuration item
    config_item = detail.get('configurationItem', {})
    if config_item:
        arn = config_item.get('ARN') or config_item.get('arn')
        resource_name = config_item.get('resourceName')
        
        if arn:
            resources['arns'].append(arn)
        if resource_name:
            resources['names'].append(resource_name)
    
    return resources


def detect_event_source(event: Dict[str, Any]) -> EventSource:
    """
    Detect the source of the event
    
    Args:
        event: Event dict
        
    Returns:
        EventSource enum value
    """
    source = event.get('source', '')
    detail_type = event.get('detail-type', '')
    
    if source == 'aws.cloudtrail' or 'cloudtrail' in source.lower():
        return EventSource.CLOUDTRAIL
    elif source == 'aws.guardduty' or detail_type == 'GuardDuty Finding':
        return EventSource.GUARDDUTY
    elif source == 'aws.securityhub' or detail_type == 'Security Hub Findings - Imported':
        return EventSource.SECURITY_HUB
    elif source == 'aws.config' or detail_type.startswith('Config'):
        return EventSource.CONFIG
    else:
        # Check detail for clues
        detail = event.get('detail', {})
        if 'eventName' in detail and 'eventSource' in detail:
            return EventSource.CLOUDTRAIL
        elif 'type' in detail and 'severity' in detail and 'resource' in detail:
            return EventSource.GUARDDUTY
        elif 'findings' in detail:
            return EventSource.SECURITY_HUB
        elif 'configRuleName' in detail or 'resourceType' in detail:
            return EventSource.CONFIG
    
    return EventSource.UNKNOWN


def parse_event_by_source(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Parse event based on detected source
    
    Args:
        event: Raw event dict
        
    Returns:
        Parsed resources dict
    """
    event_source = detect_event_source(event)
    
    logger.info(f"Detected event source: {event_source.value}")
    
    if event_source == EventSource.CLOUDTRAIL:
        return parse_cloudtrail_event(event)
    elif event_source == EventSource.GUARDDUTY:
        return parse_guardduty_finding(event)
    elif event_source == EventSource.SECURITY_HUB:
        return parse_securityhub_finding(event)
    elif event_source == EventSource.CONFIG:
        return parse_config_event(event)
    else:
        logger.warning(f"Unknown event source, returning empty resources")
        return {'arns': [], 'ids': [], 'names': []}


# ============================================================================
# FILTER BUILDER
# ============================================================================

def build_filters_and_resources(event_info: Dict[str, Any], resource_type: str, session=None, region: Optional[str]=None) -> Dict[str, Any]:
    """Build filters and optionally prefetch resources (best-effort).

    This implementation is intentionally conservative to avoid heavy list
    operations inside a Lambda.
    
    Args:
        event_info: Event information containing generic_resources
        resource_type: Cloud Custodian resource type (e.g., 'aws.ec2')
        session: Optional boto3 session for prefetching
        region: Optional AWS region
        
    Returns:
        Dict with 'filters' list and 'provided_resources' (optional)
    """
    result = {
        'filters': [],
        'provided_resources': None
    }

    generic = event_info.get('generic_resources', {}) or {}
    arns = generic.get('arns', [])
    ids = generic.get('ids', [])
    names = generic.get('names', [])

    # Strategy 1: Filter by ARN (most reliable, works for many services)
    if arns:
        arn_field = ARN_FIELD_MAPPING.get(resource_type, 'Arn')
        for arn in arns:
            result['filters'].append({'type': 'value', 'key': arn_field, 'value': arn})
            break  # Use first matching ARN

    # Strategy 2: Filter by ID (for resources that don't use ARNs in filters)
    elif ids:
        id_field = ID_FIELD_MAPPING.get(resource_type)
        if id_field and ids:
            # Filter IDs by resource-specific patterns to avoid mismatches
            filtered_ids = ids
            if resource_type == 'aws.ec2':
                # EC2 instances: only use instance IDs (i-*), not AMI IDs (ami-*) or other IDs
                filtered_ids = [id for id in ids if id.startswith('i-')]
            elif resource_type == 'aws.ami':
                # AMIs: only use AMI IDs (ami-*), not instance IDs
                filtered_ids = [id for id in ids if id.startswith('ami-')]
            elif resource_type == 'aws.ebs':
                # EBS volumes: only use volume IDs (vol-*)
                filtered_ids = [id for id in ids if id.startswith('vol-')]
            elif resource_type == 'aws.ebs-snapshot':
                # EBS snapshots: only use snapshot IDs (snap-*)
                filtered_ids = [id for id in ids if id.startswith('snap-')]
            
            if filtered_ids:
                result['filters'].append({'type': 'value', 'key': id_field, 'value': filtered_ids[0]})

    # Strategy 3: Filter by name (for S3, IAM, Lambda, etc.)
    elif names:
        name_field = NAME_FIELD_MAPPING.get(resource_type)
        if name_field and names:
            result['filters'].append({'type': 'value', 'key': name_field, 'value': names[0]})

    # ==========================================================================
    # PREFETCH RESOURCES (best-effort for specific services)
    # ==========================================================================
    # This section attempts to prefetch actual resource objects from AWS APIs
    # to avoid Cloud Custodian having to list all resources. This is especially
    # useful for event-driven policies where we know the exact resource.
    
    # Extract creator information for resource enrichment
    creator_name = event_info.get('creator_name')
    
    try:
        # -------------------- LOAD BALANCING --------------------
        if session and resource_type == 'aws.app-elb' and arns:
            client = session.client('elbv2', region_name=region)
            lb_arns = [a for a in arns if ':loadbalancer/' in a]
            if lb_arns:
                resp = client.describe_load_balancers(LoadBalancerArns=lb_arns)
                lbs = resp.get('LoadBalancers', [])
                # Enrich with creator info
                for lb in lbs:
                    lb['c7n:MatchedFilters'] = ['event-filter']
                    if creator_name:
                        lb['c7n:CreatorName'] = creator_name
                result['provided_resources'] = lbs

        # -------------------- CDN --------------------
        # For CloudFront CreateDistribution/UpdateDistribution events,
        # synthesize resource from CloudTrail responseElements transforming camelCase to PascalCase
        elif resource_type == 'aws.distribution':
            raw_event = event_info.get('raw_event', {})
            event_name = raw_event.get('detail', {}).get('eventName')
            
            if event_name in ('CreateDistribution', 'UpdateDistribution'):
                logger.info(f"Synthesizing CloudFront distribution from CloudTrail event: {event_name}")
                response_elements = raw_event.get('detail', {}).get('responseElements', {})
                cloudtrail_dist = response_elements.get('distribution', {})
                
                if cloudtrail_dist:
                    # Transform CloudTrail camelCase to API PascalCase format
                    # CloudTrail uses: id, domainName, distributionConfig, etc.
                    # API uses: Id, DomainName, DistributionConfig, etc.
                    
                    def camel_to_pascal(obj):
                        """Recursively convert camelCase keys to PascalCase"""
                        if isinstance(obj, dict):
                            new_dict = {}
                            for key, value in obj.items():
                                # Convert first letter to uppercase for PascalCase
                                pascal_key = key[0].upper() + key[1:] if key else key
                                new_dict[pascal_key] = camel_to_pascal(value)
                            return new_dict
                        elif isinstance(obj, list):
                            return [camel_to_pascal(item) for item in obj]
                        else:
                            return obj
                    
                    distribution_data = camel_to_pascal(cloudtrail_dist)
                    distribution_data['c7n:MatchedFilters'] = ['event-filter']
                    if creator_name:
                        distribution_data['c7n:CreatorName'] = creator_name
                    result['provided_resources'] = [distribution_data]
                    
                    tls_version = (distribution_data.get('DistributionConfig', {})
                                 .get('ViewerCertificate', {})
                                 .get('MinimumProtocolVersion'))
                    logger.info(f"Synthesized CloudFront distribution: {distribution_data.get('Id')}, TLS={tls_version}")
            
            # Fallback to API query for other events or if synthesis fails
            elif session and ids:
                # Filter to get only CloudFront distribution IDs (exclude S3 origin IDs like "S3-...")
                distribution_ids = [id for id in ids if not id.startswith('S3-') and len(id) < 20]
                if distribution_ids:
                    logger.info(f"Fetching CloudFront distributions: {distribution_ids}")
                    client = session.client('cloudfront', region_name=region)  # CloudFront is global but use provided region
                    distributions = []
                    for dist_id in distribution_ids:
                        try:
                            resp = client.get_distribution(Id=dist_id)
                            if resp.get('Distribution'):
                                dist = resp['Distribution']
                                dist['c7n:MatchedFilters'] = ['event-filter']
                                if creator_name:
                                    dist['c7n:CreatorName'] = creator_name
                                distributions.append(dist)
                                logger.info(f"Fetched CloudFront distribution: {dist_id}")
                        except Exception as e:
                            logger.error(f"Failed to fetch distribution {dist_id}: {e}")
                            continue
                    if distributions:
                        result['provided_resources'] = distributions
                        logger.info(f"Successfully fetched {len(distributions)} CloudFront distribution(s)")

        # -------------------- STORAGE --------------------
        elif session and resource_type == 'aws.s3' and names:
            buckets = []
            for b in names:
                bucket = {'Name': b, 'c7n:MatchedFilters': ['event-filter']}
                if creator_name:
                    bucket['c7n:CreatorName'] = creator_name
                buckets.append(bucket)
            if buckets:
                result['provided_resources'] = buckets
        
        elif session and resource_type == 'aws.efs' and ids:
            client = session.client('efs', region_name=region)
            filesystems = []
            for fs_id in ids:
                try:
                    resp = client.describe_file_systems(FileSystemId=fs_id)
                    for fs in resp.get('FileSystems', []):
                        fs['c7n:MatchedFilters'] = ['event-filter']
                        filesystems.append(fs)
                except Exception:
                    continue
            if filesystems:
                result['provided_resources'] = filesystems

        # -------------------- COMPUTE --------------------
        elif session and resource_type == 'aws.ec2' and ids:
            client = session.client('ec2', region_name=region)
            # Filter to only EC2 instance IDs (i-*), not AMI IDs (ami-*) or other IDs
            instance_ids = [id for id in ids if id.startswith('i-')]
            if instance_ids:
                instances = []
                resp = client.describe_instances(InstanceIds=instance_ids)
                for r in resp.get('Reservations', []):
                    for i in r.get('Instances', []):
                        i['c7n:MatchedFilters'] = ['event-filter']
                        # Add creator information if available
                        if creator_name:
                            # Add to Tags if not already present
                            if 'Tags' not in i:
                                i['Tags'] = []
                            i['Tags'].append({'Key': 'c7n:CreatorName', 'Value': creator_name})
                            i['c7n:CreatorName'] = creator_name
                        instances.append(i)
                if instances:
                    result['provided_resources'] = instances

        elif session and resource_type == 'aws.ami' and ids:
            client = session.client('ec2', region_name=region)
            # Filter to only AMI IDs (ami-*), not instance IDs (i-*) or other IDs
            ami_ids = [id for id in ids if id.startswith('ami-')]
            if ami_ids:
                images = []
                resp = client.describe_images(ImageIds=ami_ids)
                for img in resp.get('Images', []):
                    img['c7n:MatchedFilters'] = ['event-filter']
                    if creator_name:
                        img['c7n:CreatorName'] = creator_name
                    images.append(img)
                if images:
                    result['provided_resources'] = images

        # -------------------- LAMBDA --------------------
        elif session and resource_type == 'aws.lambda' and names:
            client = session.client('lambda', region_name=region)
            functions = []
            for fn_name in names:
                try:
                    resp = client.get_function(FunctionName=fn_name)
                    fn = resp.get('Configuration', {})
                    fn['c7n:MatchedFilters'] = ['event-filter']
                    functions.append(fn)
                except Exception:
                    continue
            if functions:
                result['provided_resources'] = functions
        
        # -------------------- DATABASE --------------------
        elif session and resource_type in ('aws.rds', 'aws.rds-cluster') and ids:
            client = session.client('rds', region_name=region)
            provided = []
            for db in ids:
                try:
                    resp = client.describe_db_instances(DBInstanceIdentifier=db)
                    for inst in resp.get('DBInstances', []):
                        inst['c7n:MatchedFilters'] = ['event-filter']
                        provided.append(inst)
                except Exception:
                    try:
                        resp = client.describe_db_clusters(DBClusterIdentifier=db)
                        for c in resp.get('DBClusters', []):
                            c['c7n:MatchedFilters'] = ['event-filter']
                            provided.append(c)
                    except Exception:
                        pass
            if provided:
                result['provided_resources'] = provided

        elif session and resource_type == 'aws.dynamodb-table' and names:
            client = session.client('dynamodb', region_name=region)
            tables = []
            for table_name in names:
                try:
                    resp = client.describe_table(TableName=table_name)
                    table = resp.get('Table', {})
                    table['c7n:MatchedFilters'] = ['event-filter']
                    tables.append(table)
                except Exception:
                    continue
            if tables:
                result['provided_resources'] = tables
        
        # -------------------- CACHE --------------------
        # For ElastiCache CreateCacheCluster/CreateReplicationGroup events,
        # synthesize resource from CloudTrail responseElements to avoid API query timing issues
        # (clusters in "creating" state may not be queryable immediately)
        elif resource_type in ('aws.cache-cluster', 'aws.elasticache', 'aws.elasticache-cluster'):
            raw_event = event_info.get('raw_event', {})
            event_name = raw_event.get('detail', {}).get('eventName')
            
            if event_name in ('CreateCacheCluster', 'CreateReplicationGroup'):
                logger.info(f"Synthesizing ElastiCache resource from CloudTrail event: {event_name}")
                response_elements = raw_event.get('detail', {}).get('responseElements', {})
                
                if response_elements:
                    # Convert CloudTrail responseElements to Cloud Custodian resource format
                    # Match the structure from describe_cache_clusters API response
                    cluster_resource = {
                        'CacheClusterId': response_elements.get('cacheClusterId'),
                        'Engine': response_elements.get('engine'),
                        'EngineVersion': response_elements.get('engineVersion'),
                        'CacheNodeType': response_elements.get('cacheNodeType'),
                        'CacheClusterStatus': response_elements.get('cacheClusterStatus'),
                        'NumCacheNodes': response_elements.get('numCacheNodes'),
                        'AtRestEncryptionEnabled': response_elements.get('atRestEncryptionEnabled', False),
                        'TransitEncryptionEnabled': response_elements.get('transitEncryptionEnabled', False),
                        'ReplicationGroupId': response_elements.get('replicationGroupId'),
                        'ARN': response_elements.get('aRN'),
                        'CacheSubnetGroupName': response_elements.get('cacheSubnetGroupName'),
                        'AutoMinorVersionUpgrade': response_elements.get('autoMinorVersionUpgrade'),
                        'SnapshotRetentionLimit': response_elements.get('snapshotRetentionLimit'),
                        'c7n:MatchedFilters': ['event-filter']
                    }
                    result['provided_resources'] = [cluster_resource]
                    logger.info(f"Synthesized ElastiCache resource: {cluster_resource['CacheClusterId']}, "
                               f"AtRestEncryption={cluster_resource['AtRestEncryptionEnabled']}, "
                               f"TransitEncryption={cluster_resource['TransitEncryptionEnabled']}")
            
            # Fallback to API query for other events or if synthesis fails
            elif session and (arns or ids):
                client = session.client('elasticache', region_name=region)
                cache_ids = ids or [a.split(':')[-1] for a in arns]
                clusters = []
                for cache_id in cache_ids:
                    try:
                        resp = client.describe_cache_clusters(CacheClusterId=cache_id, ShowCacheNodeInfo=False)
                        for cluster in resp.get('CacheClusters', []):
                            cluster['c7n:MatchedFilters'] = ['event-filter']
                            clusters.append(cluster)
                    except Exception:
                        continue
                if clusters:
                    result['provided_resources'] = clusters
        
        # -------------------- CONTAINERS & ORCHESTRATION --------------------
        elif session and resource_type == 'aws.eks' and names:
            client = session.client('eks', region_name=region)
            clusters = []
            for name in names:
                try:
                    resp = client.describe_cluster(name=name)
                    cluster = resp.get('cluster', {})
                    cluster['c7n:MatchedFilters'] = ['event-filter']
                    clusters.append(cluster)
                except Exception:
                    continue
            if clusters:
                result['provided_resources'] = clusters
        
        elif session and resource_type in ('aws.ecs-cluster', 'aws.ecs') and (arns or names):
            client = session.client('ecs', region_name=region)
            cluster_names = names or [a.split('/')[-1] for a in arns]
            if cluster_names:
                try:
                    resp = client.describe_clusters(clusters=cluster_names)
                    result['provided_resources'] = resp.get('clusters', [])
                except Exception:
                    pass
        
        elif session and resource_type == 'aws.ecr' and names:
            client = session.client('ecr', region_name=region)
            repos = []
            for repo_name in names:
                try:
                    resp = client.describe_repositories(repositoryNames=[repo_name])
                    for repo in resp.get('repositories', []):
                        repo['c7n:MatchedFilters'] = ['event-filter']
                        repos.append(repo)
                except Exception:
                    continue
            if repos:
                result['provided_resources'] = repos
        
        # -------------------- SECURITY & IDENTITY --------------------
        elif session and resource_type in ('aws.secretsmanager', 'aws.secrets-manager') and (ids or names):
            client = session.client('secretsmanager', region_name=region)
            secrets = []
            secret_ids = ids or names
            for sid in secret_ids:
                try:
                    resp = client.describe_secret(SecretId=sid)
                    resp['c7n:MatchedFilters'] = ['event-filter']
                    secrets.append(resp)
                except Exception:
                    continue
            if secrets:
                result['provided_resources'] = secrets
        
        elif session and resource_type in ('aws.acm', 'aws.acm-certificate') and (arns or ids):
            client = session.client('acm', region_name=region)
            certs = []
            cert_arns = arns or ids
            for cert_arn in cert_arns:
                try:
                    resp = client.describe_certificate(CertificateArn=cert_arn)
                    cert = resp.get('Certificate', {})
                    cert['c7n:MatchedFilters'] = ['event-filter']
                    certs.append(cert)
                except Exception:
                    continue
            if certs:
                result['provided_resources'] = certs
        
        elif session and resource_type == 'aws.kms' and (ids or arns):
            client = session.client('kms', region_name=region)
            keys = []
            key_ids = ids or arns
            for key_id in key_ids:
                try:
                    resp = client.describe_key(KeyId=key_id)
                    key = resp.get('KeyMetadata', {})
                    key['c7n:MatchedFilters'] = ['event-filter']
                    keys.append(key)
                except Exception:
                    continue
            if keys:
                result['provided_resources'] = keys
        
        elif session and resource_type.startswith('aws.cognito') and names:
            client = session.client('cognito-idp', region_name=region)
            pools = []
            for pool_id in names:
                try:
                    resp = client.describe_user_pool(UserPoolId=pool_id)
                    pool = resp.get('UserPool', {})
                    pool['c7n:MatchedFilters'] = ['event-filter']
                    pools.append(pool)
                except Exception:
                    continue
            if pools:
                result['provided_resources'] = pools
        
        # -------------------- CDN & EDGE --------------------
        elif session and resource_type in ('aws.cloudfront', 'aws.cloudfront-distribution') and ids:
            client = session.client('cloudfront')
            distributions = []
            for dist_id in ids:
                try:
                    resp = client.get_distribution(Id=dist_id)
                    dist = resp.get('Distribution', {})
                    dist['c7n:MatchedFilters'] = ['event-filter']
                    distributions.append(dist)
                except Exception:
                    continue
            if distributions:
                result['provided_resources'] = distributions
        
        # -------------------- APPLICATION INTEGRATION --------------------
        elif session and resource_type == 'aws.sns' and (arns or names):
            client = session.client('sns', region_name=region)
            topics = []
            topic_arns = arns or [f"arn:aws:sns:{region}:*:{n}" for n in names]
            for topic_arn in topic_arns:
                try:
                    resp = client.get_topic_attributes(TopicArn=topic_arn)
                    attrs = resp.get('Attributes', {})
                    attrs['c7n:MatchedFilters'] = ['event-filter']
                    topics.append(attrs)
                except Exception:
                    continue
            if topics:
                result['provided_resources'] = topics
        
        elif session and resource_type == 'aws.sqs' and (arns or names):
            client = session.client('sqs', region_name=region)
            queues = []
            # For SQS, we need queue URLs
            if names:
                for queue_name in names:
                    try:
                        resp = client.get_queue_url(QueueName=queue_name)
                        queue_url = resp.get('QueueUrl')
                        attrs_resp = client.get_queue_attributes(QueueUrl=queue_url, AttributeNames=['All'])
                        attrs = attrs_resp.get('Attributes', {})
                        attrs['QueueUrl'] = queue_url
                        attrs['c7n:MatchedFilters'] = ['event-filter']
                        queues.append(attrs)
                    except Exception:
                        continue
            if queues:
                result['provided_resources'] = queues
        
        elif session and resource_type == 'aws.kinesis' and names:
            client = session.client('kinesis', region_name=region)
            streams = []
            for stream_name in names:
                try:
                    resp = client.describe_stream(StreamName=stream_name)
                    stream = resp.get('StreamDescription', {})
                    stream['c7n:MatchedFilters'] = ['event-filter']
                    streams.append(stream)
                except Exception:
                    continue
            if streams:
                result['provided_resources'] = streams
        
        elif session and resource_type in ('aws.kinesis-firehose', 'aws.firehose') and names:
            client = session.client('firehose', region_name=region)
            delivery_streams = []
            for stream_name in names:
                try:
                    resp = client.describe_delivery_stream(DeliveryStreamName=stream_name)
                    stream = resp.get('DeliveryStreamDescription', {})
                    stream['c7n:MatchedFilters'] = ['event-filter']
                    delivery_streams.append(stream)
                except Exception:
                    continue
            if delivery_streams:
                result['provided_resources'] = delivery_streams
        
        elif session and resource_type in ('aws.events', 'aws.event-bus') and names:
            client = session.client('events', region_name=region)
            buses = []
            for bus_name in names:
                try:
                    resp = client.describe_event_bus(Name=bus_name)
                    resp['c7n:MatchedFilters'] = ['event-filter']
                    buses.append(resp)
                except Exception:
                    continue
            if buses:
                result['provided_resources'] = buses
        
        # -------------------- ANALYTICS & SEARCH --------------------
        elif session and resource_type in ('aws.elasticsearch', 'aws.opensearch') and names:
            client = session.client('opensearch', region_name=region)
            domains = []
            for domain_name in names:
                try:
                    resp = client.describe_domains(DomainNames=[domain_name])
                    for domain in resp.get('DomainStatusList', []):
                        domain['c7n:MatchedFilters'] = ['event-filter']
                        domains.append(domain)
                except Exception:
                    continue
            if domains:
                result['provided_resources'] = domains
        
        elif session and resource_type == 'aws.timestream-database' and names:
            client = session.client('timestream-write', region_name=region)
            databases = []
            for db_name in names:
                try:
                    resp = client.describe_database(DatabaseName=db_name)
                    db = resp.get('Database', {})
                    db['c7n:MatchedFilters'] = ['event-filter']
                    databases.append(db)
                except Exception:
                    continue
            if databases:
                result['provided_resources'] = databases
        
        # -------------------- NETWORKING (VPC, Subnets, Gateways, etc.) --------------------
        elif session and resource_type in ('aws.vpc', 'aws.subnet', 'aws.internet-gateway', 
                                            'aws.nat-gateway', 'aws.network-acl', 
                                            'aws.security-group', 'aws.network-interface') and ids:
            ec2 = session.client('ec2', region_name=region)
            try:
                if resource_type == 'aws.vpc':
                    resp = ec2.describe_vpcs(VpcIds=ids)
                    result['provided_resources'] = resp.get('Vpcs', [])
                elif resource_type == 'aws.subnet':
                    resp = ec2.describe_subnets(SubnetIds=ids)
                    result['provided_resources'] = resp.get('Subnets', [])
                elif resource_type == 'aws.internet-gateway':
                    resp = ec2.describe_internet_gateways(InternetGatewayIds=ids)
                    result['provided_resources'] = resp.get('InternetGateways', [])
                elif resource_type == 'aws.nat-gateway':
                    resp = ec2.describe_nat_gateways(NatGatewayIds=ids)
                    result['provided_resources'] = resp.get('NatGateways', [])
                elif resource_type == 'aws.network-acl':
                    resp = ec2.describe_network_acls(NetworkAclIds=ids)
                    result['provided_resources'] = resp.get('NetworkAcls', [])
                elif resource_type == 'aws.security-group':
                    resp = ec2.describe_security_groups(GroupIds=ids)
                    result['provided_resources'] = resp.get('SecurityGroups', [])
                elif resource_type == 'aws.network-interface':
                    resp = ec2.describe_network_interfaces(NetworkInterfaceIds=ids)
                    result['provided_resources'] = resp.get('NetworkInterfaces', [])
            except Exception:
                pass
        
        # -------------------- MONITORING & LOGGING --------------------
        elif session and resource_type == 'aws.cloudwatch-alarm' and names:
            client = session.client('cloudwatch', region_name=region)
            try:
                resp = client.describe_alarms(AlarmNames=names)
                result['provided_resources'] = resp.get('MetricAlarms', [])
            except Exception:
                pass
        
        elif session and resource_type == 'aws.cloudwatch-log-group' and names:
            client = session.client('logs', region_name=region)
            log_groups = []
            for log_group_name in names:
                try:
                    resp = client.describe_log_groups(logGroupNamePrefix=log_group_name, limit=1)
                    for lg in resp.get('logGroups', []):
                        if lg.get('logGroupName') == log_group_name:
                            lg['c7n:MatchedFilters'] = ['event-filter']
                            log_groups.append(lg)
                except Exception:
                    continue
            if log_groups:
                result['provided_resources'] = log_groups
        
        elif session and resource_type == 'aws.ses-identity' and names:
            client = session.client('ses', region_name=region)
            identities = []
            for identity in names:
                try:
                    resp = client.get_identity_verification_attributes(Identities=[identity])
                    attrs = resp.get('VerificationAttributes', {}).get(identity, {})
                    attrs['Identity'] = identity
                    attrs['c7n:MatchedFilters'] = ['event-filter']
                    identities.append(attrs)
                except Exception:
                    continue
            if identities:
                result['provided_resources'] = identities
        
        # -------------------- SECURITY SERVICES --------------------
        elif session and resource_type == 'aws.wafv2' and (arns or ids):
            client = session.client('wafv2', region_name=region)
            web_acls = []
            # WAFv2 requires scope (REGIONAL or CLOUDFRONT)
            # Try REGIONAL first
            for waf_id in (ids or arns):
                try:
                    resp = client.get_web_acl(Scope='REGIONAL', Id=waf_id, Name=waf_id)
                    web_acl = resp.get('WebACL', {})
                    web_acl['c7n:MatchedFilters'] = ['event-filter']
                    web_acls.append(web_acl)
                except Exception:
                    # Try CLOUDFRONT scope
                    try:
                        resp = client.get_web_acl(Scope='CLOUDFRONT', Id=waf_id, Name=waf_id)
                        web_acl = resp.get('WebACL', {})
                        web_acl['c7n:MatchedFilters'] = ['event-filter']
                        web_acls.append(web_acl)
                    except Exception:
                        continue
            if web_acls:
                result['provided_resources'] = web_acls
        
        elif session and resource_type == 'aws.config-rule' and names:
            client = session.client('config', region_name=region)
            rules = []
            for rule_name in names:
                try:
                    resp = client.describe_config_rules(ConfigRuleNames=[rule_name])
                    for rule in resp.get('ConfigRules', []):
                        rule['c7n:MatchedFilters'] = ['event-filter']
                        rules.append(rule)
                except Exception:
                    continue
            if rules:
                result['provided_resources'] = rules

    except Exception as e:
        logger.debug(f"Prefetch failed for {resource_type}: {e}")

    # ==========================================================================
    # FALLBACK LOGIC
    # ==========================================================================
    # If we provided resources directly, don't add filters - they're not needed
    # and can cause issues if field names don't match (e.g., 'ARN' vs 'Arn')
    if result['provided_resources']:
        logger.info(f"Skipping filter generation because {len(result['provided_resources'])} resources were provided directly")
        result['filters'] = []  # Clear any filters - provided_resources is sufficient
        return result
    
    # Ensure we always return a list for filters. If we didn't create any
    # resource-specific filters above, but generic ids/names/arns were present,
    # build simple equality filters so callers have something to operate on.
    if not result['filters']:
        if ids:
            for resource_id in ids:
                result['filters'].append({'type': 'value', 'key': 'Id', 'value': resource_id})
        if names:
            for name in names:
                result['filters'].append({'type': 'value', 'key': 'Name', 'value': name})
        if arns:
            for arn in arns:
                result['filters'].append({'type': 'value', 'key': 'Arn', 'value': arn})

    return result


def arn_matches_resource(arn: str, resource_type: str) -> bool:
    """
    Check if an ARN matches the expected resource type
    
    Args:
        arn: AWS ARN string
        resource_type: Cloud Custodian resource type (e.g., 'aws.ec2')
        
    Returns:
        True if ARN matches resource type
    """
    arn_lower = arn.lower()
    
    # Map Cloud Custodian resource types to ARN service names
    type_mapping = {
        'aws.ec2': ['ec2'],
        'aws.app-elb': ['elasticloadbalancing'],
        'aws.elb': ['elasticloadbalancing'],
        'aws.rds': ['rds'],
        'aws.rds-cluster': ['rds'],
        'aws.s3': ['s3'],
        'aws.lambda': ['lambda'],
        'aws.iam-role': ['iam'],
        'aws.iam-user': ['iam'],
        'aws.iam-policy': ['iam'],
        'aws.dynamodb-table': ['dynamodb'],
        'aws.kinesis': ['kinesis'],
        'aws.kinesis-firehose': ['firehose'],
        'aws.sns': ['sns'],
        'aws.sqs': ['sqs'],
        'aws.kms': ['kms'],
        'aws.cloudfront': ['cloudfront'],
        'aws.elasticache': ['elasticache'],
        'aws.elasticsearch': ['es', 'elasticsearch'],
        'aws.opensearch': ['es', 'opensearch'],
        'aws.efs': ['elasticfilesystem'],
        'aws.ecr': ['ecr'],
        'aws.ecs': ['ecs'],
        'aws.eks': ['eks'],
        'aws.secretsmanager': ['secretsmanager'],
        'aws.acm': ['acm'],
        'aws.wafv2': ['wafv2'],
        'aws.cognito-user-pool': ['cognito-idp'],
        'aws.codecommit': ['codecommit'],
        'aws.codebuild': ['codebuild'],
        'aws.config-rule': ['config'],
    }
    
    expected_services = type_mapping.get(resource_type, [])
    
    # Check if any expected service appears in the ARN
    for service in expected_services:
        if f':{service}:' in arn_lower or f'::{service}/' in arn_lower:
            return True
    
    # If no specific mapping found, assume it matches (conservative approach)
    return len(expected_services) == 0


def get_filter_field_for_resource(resource_type: str, filter_strategy: str = 'arn') -> Optional[str]:
    """
    Get the appropriate filter field for a resource type
    
    Args:
        resource_type: Cloud Custodian resource type
        filter_strategy: Type of filter - 'arn', 'id', or 'name'
        
    Returns:
        Field name to use in filter, or None if not found
    """
    if filter_strategy == 'arn':
        return ARN_FIELD_MAPPING.get(resource_type)
    elif filter_strategy == 'id':
        return ID_FIELD_MAPPING.get(resource_type)
    elif filter_strategy == 'name':
        return NAME_FIELD_MAPPING.get(resource_type)
    return None
