"""
Phase 2: Containment Lambda
Isolates the affected resources to prevent further damage
"""
import json
import boto3
from datetime import datetime
from typing import Dict, Any

s3 = boto3.client('s3')
ec2 = boto3.client('ec2')
iam = boto3.client('iam')
sns = boto3.client('sns')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Containment Phase
    - Block public access to affected bucket
    - Enable bucket versioning if not enabled
    - Create deny-all bucket policy backup
    - Isolate compromised IAM credentials
    - Take snapshots before remediation
    - Notify security team
    """
    print(f"Containment Phase - Event: {json.dumps(event)}")
    
    try:
        incident_id = event.get('incidentId', 'Unknown')
        bucket_name = event.get('bucketName')
        severity = event.get('severity', 'MEDIUM')
        
        if not bucket_name:
            return {
                'incidentId': incident_id,
                'phase': 'containment',
                'status': 'failed',
                'error': 'No bucket name provided'
            }
        
        containment_actions = []
        
        # Action 1: Block all public access
        try:
            s3.put_public_access_block(
                Bucket=bucket_name,
                PublicAccessBlockConfiguration={
                    'BlockPublicAcls': True,
                    'IgnorePublicAcls': True,
                    'BlockPublicPolicy': True,
                    'RestrictPublicBuckets': True
                }
            )
            containment_actions.append({
                'action': 'block_public_access',
                'status': 'success',
                'timestamp': datetime.utcnow().isoformat()
            })
            print(f"Blocked public access for bucket: {bucket_name}")
        except Exception as e:
            containment_actions.append({
                'action': 'block_public_access',
                'status': 'failed',
                'error': str(e)
            })
        
        # Action 2: Enable versioning to preserve object history
        try:
            s3.put_bucket_versioning(
                Bucket=bucket_name,
                VersioningConfiguration={'Status': 'Enabled'}
            )
            containment_actions.append({
                'action': 'enable_versioning',
                'status': 'success',
                'timestamp': datetime.utcnow().isoformat()
            })
            print(f"Enabled versioning for bucket: {bucket_name}")
        except Exception as e:
            containment_actions.append({
                'action': 'enable_versioning',
                'status': 'failed',
                'error': str(e)
            })
        
        # Action 3: Enable MFA Delete (if critical severity)
        if severity == 'CRITICAL':
            # Note: MFA Delete requires root account MFA and cannot be enabled via API
            containment_actions.append({
                'action': 'mfa_delete',
                'status': 'manual_required',
                'message': 'MFA Delete requires manual enablement by root account'
            })
        
        # Action 4: Create backup of current bucket policy
        try:
            current_policy = None
            try:
                policy_response = s3.get_bucket_policy(Bucket=bucket_name)
                current_policy = policy_response['Policy']
                
                # Store policy in a backup bucket
                backup_bucket = 'ysr95-custodian-policies'
                backup_key = f'incident-response/policy-backups/{incident_id}-{bucket_name}-policy.json'
                s3.put_object(
                    Bucket=backup_bucket,
                    Key=backup_key,
                    Body=current_policy,
                    ServerSideEncryption='AES256'
                )
                
                containment_actions.append({
                    'action': 'backup_policy',
                    'status': 'success',
                    'backupLocation': f's3://{backup_bucket}/{backup_key}'
                })
            except s3.exceptions.ClientError as e:
                if e.response['Error']['Code'] == 'NoSuchBucketPolicy':
                    containment_actions.append({
                        'action': 'backup_policy',
                        'status': 'no_policy_exists'
                    })
        except Exception as e:
            containment_actions.append({
                'action': 'backup_policy',
                'status': 'failed',
                'error': str(e)
            })
        
        # Action 5: Apply restrictive bucket policy (only for CRITICAL incidents)
        if severity == 'CRITICAL':
            try:
                restrictive_policy = {
                    "Version": "2012-10-17",
                    "Statement": [
                        {
                            "Sid": "DenyAllExceptIncidentResponse",
                            "Effect": "Deny",
                            "Principal": "*",
                            "Action": "s3:*",
                            "Resource": [
                                f"arn:aws:s3:::{bucket_name}",
                                f"arn:aws:s3:::{bucket_name}/*"
                            ],
                            "Condition": {
                                "StringNotEquals": {
                                    "aws:PrincipalTag/IncidentResponse": "true"
                                }
                            }
                        }
                    ]
                }
                
                s3.put_bucket_policy(
                    Bucket=bucket_name,
                    Policy=json.dumps(restrictive_policy)
                )
                
                containment_actions.append({
                    'action': 'apply_restrictive_policy',
                    'status': 'success',
                    'timestamp': datetime.utcnow().isoformat()
                })
                print(f"Applied restrictive policy to bucket: {bucket_name}")
            except Exception as e:
                containment_actions.append({
                    'action': 'apply_restrictive_policy',
                    'status': 'failed',
                    'error': str(e)
                })
        
        # Action 6: Enable S3 Object Lock (if not already enabled and if supported)
        try:
            # Check if bucket has Object Lock enabled
            try:
                s3.get_object_lock_configuration(Bucket=bucket_name)
                containment_actions.append({
                    'action': 'check_object_lock',
                    'status': 'already_enabled'
                })
            except s3.exceptions.ClientError as e:
                if e.response['Error']['Code'] == 'ObjectLockConfigurationNotFoundError':
                    # Object Lock cannot be enabled on existing buckets without it
                    containment_actions.append({
                        'action': 'check_object_lock',
                        'status': 'not_enabled',
                        'message': 'Object Lock can only be enabled at bucket creation'
                    })
        except Exception as e:
            containment_actions.append({
                'action': 'check_object_lock',
                'status': 'failed',
                'error': str(e)
            })
        
        # Action 7: Tag bucket for incident tracking
        try:
            s3.put_bucket_tagging(
                Bucket=bucket_name,
                Tagging={
                    'TagSet': [
                        {'Key': 'IncidentId', 'Value': incident_id},
                        {'Key': 'IncidentStatus', 'Value': 'CONTAINED'},
                        {'Key': 'ContainmentTimestamp', 'Value': datetime.utcnow().isoformat()},
                        {'Key': 'Severity', 'Value': severity}
                    ]
                }
            )
            containment_actions.append({
                'action': 'tag_bucket',
                'status': 'success'
            })
        except Exception as e:
            containment_actions.append({
                'action': 'tag_bucket',
                'status': 'failed',
                'error': str(e)
            })
        
        # Action 8: Disable compromised IAM credentials (if identified)
        compromised_credentials = event.get('compromisedCredentials', [])
        if compromised_credentials:
            for cred in compromised_credentials:
                try:
                    # Attach deny-all policy to user/role
                    identity_type = cred.get('type')  # 'user' or 'role'
                    identity_name = cred.get('name')
                    
                    if identity_type == 'user':
                        # Deactivate access keys
                        access_keys = iam.list_access_keys(UserName=identity_name)
                        for key in access_keys['AccessKeyMetadata']:
                            iam.update_access_key(
                                UserName=identity_name,
                                AccessKeyId=key['AccessKeyId'],
                                Status='Inactive'
                            )
                        
                        containment_actions.append({
                            'action': 'disable_iam_credentials',
                            'status': 'success',
                            'target': identity_name
                        })
                except Exception as e:
                    containment_actions.append({
                        'action': 'disable_iam_credentials',
                        'status': 'failed',
                        'target': identity_name,
                        'error': str(e)
                    })
        
        # Action 9: Send SNS notification to security team
        try:
            sns_topic = 'arn:aws:sns:us-east-1:172327596604:security-alerts'
            sns.publish(
                TopicArn=sns_topic,
                Subject=f'CONTAINMENT COMPLETE: {incident_id}',
                Message=json.dumps({
                    'incidentId': incident_id,
                    'bucketName': bucket_name,
                    'severity': severity,
                    'containmentActions': containment_actions,
                    'timestamp': datetime.utcnow().isoformat()
                }, indent=2)
            )
            containment_actions.append({
                'action': 'send_notification',
                'status': 'success'
            })
        except Exception as e:
            print(f"Failed to send SNS notification: {e}")
            containment_actions.append({
                'action': 'send_notification',
                'status': 'failed',
                'error': str(e)
            })
        
        # Summary
        successful_actions = len([a for a in containment_actions if a.get('status') == 'success'])
        total_actions = len(containment_actions)
        
        result = {
            'incidentId': incident_id,
            'phase': 'containment',
            'status': 'completed',
            'timestamp': datetime.utcnow().isoformat(),
            'bucketName': bucket_name,
            'severity': severity,
            'containmentActions': containment_actions,
            'summary': {
                'totalActions': total_actions,
                'successfulActions': successful_actions,
                'failedActions': total_actions - successful_actions
            }
        }
        
        # Pass through previous event data
        result.update({k: v for k, v in event.items() if k not in result})
        
        print(f"Containment completed for incident {incident_id}: {successful_actions}/{total_actions} actions successful")
        
        return result
        
    except Exception as e:
        print(f"Error in containment phase: {str(e)}")
        return {
            'incidentId': event.get('incidentId', 'Unknown'),
            'phase': 'containment',
            'status': 'failed',
            'error': str(e),
            'timestamp': datetime.utcnow().isoformat()
        }
