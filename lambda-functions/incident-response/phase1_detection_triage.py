"""
Phase 1: Detection & Triage Lambda
Validates and enriches the security incident, gathers initial context
"""
import json
import boto3
import os
from datetime import datetime
from typing import Dict, Any

s3 = boto3.client('s3')
guardduty = boto3.client('guardduty')
cloudwatch = boto3.client('cloudwatch')
logs = boto3.client('logs')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Detection and Triage Phase
    - Validate the incident
    - Gather S3 bucket metadata
    - Collect CloudWatch metrics
    - Fetch GuardDuty findings
    - Create incident ID and initial assessment
    """
    print(f"Detection & Triage Phase - Event: {json.dumps(event)}")
    
    try:
        # Extract bucket information from the event
        bucket_name = extract_bucket_name(event)
        if not bucket_name:
            return {
                'statusCode': 400,
                'phase': 'detection',
                'status': 'failed',
                'error': 'No bucket name found in event'
            }
        
        # Generate incident ID
        incident_id = f"IR-{datetime.utcnow().strftime('%Y%m%d-%H%M%S')}-{bucket_name[:20]}"
        
        # Gather S3 bucket information
        bucket_info = gather_bucket_info(bucket_name)
        
        # Get CloudWatch metrics for unusual activity
        metrics = get_bucket_metrics(bucket_name)
        
        # Check for related GuardDuty findings
        guardduty_findings = get_guardduty_findings(bucket_name)
        
        # Get recent CloudTrail events
        cloudtrail_events = get_recent_cloudtrail_events(bucket_name)
        
        # Assess severity
        severity = assess_severity(metrics, guardduty_findings, cloudtrail_events)
        
        # Create incident context
        incident_context = {
            'incidentId': incident_id,
            'timestamp': datetime.utcnow().isoformat(),
            'phase': 'detection',
            'status': 'completed',
            'bucketName': bucket_name,
            'bucketInfo': bucket_info,
            'metrics': metrics,
            'guardDutyFindings': guardduty_findings,
            'cloudTrailEvents': cloudtrail_events[:10],  # Last 10 events
            'severity': severity,
            'triggerEvent': event,
            'recommendation': get_recommendation(severity, guardduty_findings)
        }
        
        # Log to CloudWatch
        log_incident(incident_id, 'detection', incident_context)
        
        print(f"Incident {incident_id} triaged with severity: {severity}")
        
        return incident_context
        
    except Exception as e:
        print(f"Error in detection phase: {str(e)}")
        return {
            'statusCode': 500,
            'phase': 'detection',
            'status': 'failed',
            'error': str(e)
        }

def extract_bucket_name(event: Dict[str, Any]) -> str:
    """Extract bucket name from various event sources"""
    # From CloudTrail event
    if 'detail' in event and 'requestParameters' in event['detail']:
        return event['detail']['requestParameters'].get('bucketName', '')
    
    # From GuardDuty finding
    if 'detail' in event and 'resource' in event['detail']:
        resources = event['detail'].get('resource', {}).get('s3BucketDetails', [])
        if resources:
            return resources[0].get('name', '')
    
    # From custom event
    if 'bucketName' in event:
        return event['bucketName']
    
    # From Cloud Custodian resource
    if 'resources' in event and event['resources']:
        return event['resources'][0].get('Name', '')
    
    return ''

def gather_bucket_info(bucket_name: str) -> Dict[str, Any]:
    """Gather comprehensive S3 bucket information"""
    try:
        bucket_info = {
            'name': bucket_name,
            'versioning': 'Unknown',
            'encryption': 'Unknown',
            'publicAccess': 'Unknown',
            'objectLock': 'Unknown',
            'logging': 'Unknown',
            'replication': 'Unknown'
        }
        
        # Get versioning status
        try:
            versioning = s3.get_bucket_versioning(Bucket=bucket_name)
            bucket_info['versioning'] = versioning.get('Status', 'Disabled')
        except Exception as e:
            print(f"Error getting versioning: {e}")
        
        # Get encryption
        try:
            encryption = s3.get_bucket_encryption(Bucket=bucket_name)
            bucket_info['encryption'] = 'Enabled'
        except s3.exceptions.ClientError as e:
            if e.response['Error']['Code'] == 'ServerSideEncryptionConfigurationNotFoundError':
                bucket_info['encryption'] = 'Disabled'
        
        # Get public access block
        try:
            public_access = s3.get_public_access_block(Bucket=bucket_name)
            config = public_access['PublicAccessBlockConfiguration']
            bucket_info['publicAccess'] = 'Blocked' if all(config.values()) else 'Allowed'
        except Exception as e:
            print(f"Error getting public access: {e}")
        
        # Get object lock
        try:
            object_lock = s3.get_object_lock_configuration(Bucket=bucket_name)
            bucket_info['objectLock'] = 'Enabled'
        except s3.exceptions.ClientError as e:
            if e.response['Error']['Code'] == 'ObjectLockConfigurationNotFoundError':
                bucket_info['objectLock'] = 'Disabled'
        
        # Get logging
        try:
            logging = s3.get_bucket_logging(Bucket=bucket_name)
            bucket_info['logging'] = 'Enabled' if 'LoggingEnabled' in logging else 'Disabled'
        except Exception as e:
            print(f"Error getting logging: {e}")
        
        return bucket_info
        
    except Exception as e:
        print(f"Error gathering bucket info: {e}")
        return {'name': bucket_name, 'error': str(e)}

def get_bucket_metrics(bucket_name: str) -> Dict[str, Any]:
    """Get CloudWatch metrics for the bucket"""
    try:
        now = datetime.utcnow()
        
        metrics = {
            'numberOfObjects': None,
            'bucketSizeBytes': None,
            'unusualActivity': False
        }
        
        # Get number of objects (last 24 hours)
        try:
            response = cloudwatch.get_metric_statistics(
                Namespace='AWS/S3',
                MetricName='NumberOfObjects',
                Dimensions=[
                    {'Name': 'BucketName', 'Value': bucket_name},
                    {'Name': 'StorageType', 'Value': 'AllStorageTypes'}
                ],
                StartTime=now.replace(hour=0, minute=0, second=0),
                EndTime=now,
                Period=86400,
                Statistics=['Average']
            )
            if response['Datapoints']:
                metrics['numberOfObjects'] = int(response['Datapoints'][0]['Average'])
        except Exception as e:
            print(f"Error getting object count: {e}")
        
        # Get bucket size
        try:
            response = cloudwatch.get_metric_statistics(
                Namespace='AWS/S3',
                MetricName='BucketSizeBytes',
                Dimensions=[
                    {'Name': 'BucketName', 'Value': bucket_name},
                    {'Name': 'StorageType', 'Value': 'StandardStorage'}
                ],
                StartTime=now.replace(hour=0, minute=0, second=0),
                EndTime=now,
                Period=86400,
                Statistics=['Average']
            )
            if response['Datapoints']:
                metrics['bucketSizeBytes'] = int(response['Datapoints'][0]['Average'])
        except Exception as e:
            print(f"Error getting bucket size: {e}")
        
        return metrics
        
    except Exception as e:
        print(f"Error getting metrics: {e}")
        return {'error': str(e)}

def get_guardduty_findings(bucket_name: str) -> list:
    """Get related GuardDuty findings"""
    try:
        # List all detectors
        detectors_response = guardduty.list_detectors()
        if not detectors_response['DetectorIds']:
            return []
        
        detector_id = detectors_response['DetectorIds'][0]
        
        # List findings
        findings_response = guardduty.list_findings(
            DetectorId=detector_id,
            FindingCriteria={
                'Criterion': {
                    'resource.s3BucketDetails.name': {
                        'Eq': [bucket_name]
                    },
                    'severity': {
                        'Gte': 7
                    }
                }
            },
            MaxResults=10
        )
        
        if not findings_response['FindingIds']:
            return []
        
        # Get finding details
        findings_details = guardduty.get_findings(
            DetectorId=detector_id,
            FindingIds=findings_response['FindingIds']
        )
        
        return [
            {
                'id': f['Id'],
                'type': f['Type'],
                'severity': f['Severity'],
                'description': f['Description'],
                'createdAt': f['CreatedAt']
            }
            for f in findings_details['Findings']
        ]
        
    except Exception as e:
        print(f"Error getting GuardDuty findings: {e}")
        return []

def get_recent_cloudtrail_events(bucket_name: str) -> list:
    """Get recent CloudTrail events for the bucket (simulated)"""
    # In production, query CloudTrail Insights or S3 access logs
    # For now, return placeholder
    return [
        {
            'eventName': 'PutObject',
            'eventTime': datetime.utcnow().isoformat(),
            'userIdentity': {'type': 'Unknown'}
        }
    ]

def assess_severity(metrics: Dict, guardduty_findings: list, cloudtrail_events: list) -> str:
    """Assess incident severity"""
    if guardduty_findings:
        max_severity = max([f['severity'] for f in guardduty_findings])
        if max_severity >= 8:
            return 'CRITICAL'
        elif max_severity >= 7:
            return 'HIGH'
    
    # Check metrics for unusual patterns
    if metrics.get('unusualActivity'):
        return 'HIGH'
    
    return 'MEDIUM'

def get_recommendation(severity: str, guardduty_findings: list) -> str:
    """Get response recommendation based on severity"""
    if severity == 'CRITICAL':
        return 'IMMEDIATE_CONTAINMENT_REQUIRED'
    elif severity == 'HIGH':
        return 'CONTAINMENT_RECOMMENDED'
    else:
        return 'MONITOR_AND_INVESTIGATE'

def log_incident(incident_id: str, phase: str, context: Dict) -> None:
    """Log incident details to CloudWatch Logs"""
    log_group = '/aws/lambda/incident-response'
    log_stream = f'{incident_id}'
    
    try:
        # Create log stream if it doesn't exist
        try:
            logs.create_log_stream(logGroupName=log_group, logStreamName=log_stream)
        except logs.exceptions.ResourceAlreadyExistsException:
            pass
        
        # Put log event
        logs.put_log_events(
            logGroupName=log_group,
            logStreamName=log_stream,
            logEvents=[
                {
                    'timestamp': int(datetime.utcnow().timestamp() * 1000),
                    'message': json.dumps({
                        'phase': phase,
                        'context': context
                    })
                }
            ]
        )
    except Exception as e:
        print(f"Error logging to CloudWatch: {e}")
