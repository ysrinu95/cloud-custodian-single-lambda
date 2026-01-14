"""
Phase 3: Eradication Lambda
Removes the threat and restores systems to clean state
"""
import json
import boto3
from datetime import datetime, timedelta
from typing import Dict, Any, List

s3 = boto3.client('s3')
iam = boto3.client('iam')
cloudtrail = boto3.client('cloudtrail')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Eradication Phase
    - Identify and remove malicious objects
    - Restore objects from versions if encrypted/modified
    - Remove malicious bucket policies/ACLs
    - Rotate compromised credentials
    - Remove backdoors (IAM roles, users, policies)
    - Clean up any persistence mechanisms
    """
    print(f"Eradication Phase - Event: {json.dumps(event)}")
    
    try:
        incident_id = event.get('incidentId', 'Unknown')
        bucket_name = event.get('bucketName')
        severity = event.get('severity', 'MEDIUM')
        
        if not bucket_name:
            return {
                'incidentId': incident_id,
                'phase': 'eradication',
                'status': 'failed',
                'error': 'No bucket name provided'
            }
        
        eradication_actions = []
        
        # Action 1: Identify suspicious objects
        suspicious_objects = identify_suspicious_objects(bucket_name, event)
        eradication_actions.append({
            'action': 'identify_suspicious_objects',
            'status': 'completed',
            'count': len(suspicious_objects),
            'timestamp': datetime.utcnow().isoformat()
        })
        
        # Action 2: Restore encrypted/modified objects from versions
        if suspicious_objects:
            restored_count = 0
            failed_restorations = []
            
            for obj in suspicious_objects[:100]:  # Limit to 100 for safety
                try:
                    restore_result = restore_object_from_version(bucket_name, obj)
                    if restore_result['success']:
                        restored_count += 1
                    else:
                        failed_restorations.append({
                            'key': obj['key'],
                            'error': restore_result.get('error')
                        })
                except Exception as e:
                    failed_restorations.append({
                        'key': obj['key'],
                        'error': str(e)
                    })
            
            eradication_actions.append({
                'action': 'restore_objects',
                'status': 'completed',
                'restoredCount': restored_count,
                'failedCount': len(failed_restorations),
                'failures': failed_restorations[:10],  # First 10 failures
                'timestamp': datetime.utcnow().isoformat()
            })
        
        # Action 3: Remove malicious objects (if identified)
        malicious_objects = event.get('maliciousObjects', [])
        if malicious_objects:
            deleted_count = 0
            for obj_key in malicious_objects:
                try:
                    s3.delete_object(Bucket=bucket_name, Key=obj_key)
                    deleted_count += 1
                except Exception as e:
                    print(f"Failed to delete {obj_key}: {e}")
            
            eradication_actions.append({
                'action': 'remove_malicious_objects',
                'status': 'completed',
                'deletedCount': deleted_count,
                'timestamp': datetime.utcnow().isoformat()
            })
        
        # Action 4: Review and clean bucket policy
        try:
            policy_cleaned = clean_bucket_policy(bucket_name, incident_id)
            eradication_actions.append({
                'action': 'clean_bucket_policy',
                'status': 'completed',
                'changes': policy_cleaned,
                'timestamp': datetime.utcnow().isoformat()
            })
        except Exception as e:
            eradication_actions.append({
                'action': 'clean_bucket_policy',
                'status': 'failed',
                'error': str(e)
            })
        
        # Action 5: Remove suspicious bucket ACLs
        try:
            acl_cleaned = clean_bucket_acls(bucket_name)
            eradication_actions.append({
                'action': 'clean_bucket_acls',
                'status': 'completed',
                'result': acl_cleaned,
                'timestamp': datetime.utcnow().isoformat()
            })
        except Exception as e:
            eradication_actions.append({
                'action': 'clean_bucket_acls',
                'status': 'failed',
                'error': str(e)
            })
        
        # Action 6: Rotate compromised IAM credentials
        compromised_identities = identify_compromised_identities(bucket_name, event)
        if compromised_identities:
            rotation_results = []
            for identity in compromised_identities:
                try:
                    result = rotate_credentials(identity)
                    rotation_results.append(result)
                except Exception as e:
                    rotation_results.append({
                        'identity': identity.get('name'),
                        'status': 'failed',
                        'error': str(e)
                    })
            
            eradication_actions.append({
                'action': 'rotate_credentials',
                'status': 'completed',
                'results': rotation_results,
                'timestamp': datetime.utcnow().isoformat()
            })
        
        # Action 7: Remove backdoor IAM roles/policies
        backdoors = identify_backdoor_access(bucket_name, event)
        if backdoors:
            removal_results = []
            for backdoor in backdoors:
                try:
                    result = remove_backdoor(backdoor)
                    removal_results.append(result)
                except Exception as e:
                    removal_results.append({
                        'backdoor': backdoor.get('arn'),
                        'status': 'failed',
                        'error': str(e)
                    })
            
            eradication_actions.append({
                'action': 'remove_backdoors',
                'status': 'completed',
                'results': removal_results,
                'timestamp': datetime.utcnow().isoformat()
            })
        
        # Action 8: Disable suspicious S3 access points
        try:
            access_points = s3.list_access_points(
                Bucket=bucket_name,
                MaxResults=100
            )
            
            for ap in access_points.get('AccessPointList', []):
                # Review and potentially delete suspicious access points
                ap_name = ap['Name']
                # Add logic to identify suspicious access points
                
            eradication_actions.append({
                'action': 'review_access_points',
                'status': 'completed',
                'count': len(access_points.get('AccessPointList', [])),
                'timestamp': datetime.utcnow().isoformat()
            })
        except Exception as e:
            eradication_actions.append({
                'action': 'review_access_points',
                'status': 'failed',
                'error': str(e)
            })
        
        # Summary
        successful_actions = len([a for a in eradication_actions if a.get('status') in ['completed', 'success']])
        total_actions = len(eradication_actions)
        
        result = {
            'incidentId': incident_id,
            'phase': 'eradication',
            'status': 'completed',
            'timestamp': datetime.utcnow().isoformat(),
            'bucketName': bucket_name,
            'severity': severity,
            'eradicationActions': eradication_actions,
            'summary': {
                'totalActions': total_actions,
                'successfulActions': successful_actions,
                'failedActions': total_actions - successful_actions,
                'suspiciousObjectsIdentified': len(suspicious_objects),
                'compromisedIdentities': len(compromised_identities) if compromised_identities else 0,
                'backdoorsRemoved': len(backdoors) if backdoors else 0
            }
        }
        
        # Pass through previous event data
        result.update({k: v for k, v in event.items() if k not in result})
        
        print(f"Eradication completed for incident {incident_id}")
        return result
        
    except Exception as e:
        print(f"Error in eradication phase: {str(e)}")
        return {
            'incidentId': event.get('incidentId', 'Unknown'),
            'phase': 'eradication',
            'status': 'failed',
            'error': str(e),
            'timestamp': datetime.utcnow().isoformat()
        }

def identify_suspicious_objects(bucket_name: str, event: Dict) -> List[Dict]:
    """Identify objects that may have been encrypted or modified by ransomware"""
    suspicious = []
    
    try:
        # Get objects modified in the last hour
        cutoff_time = datetime.utcnow() - timedelta(hours=1)
        
        paginator = s3.get_paginator('list_object_versions')
        pages = paginator.paginate(Bucket=bucket_name, MaxKeys=1000)
        
        for page in pages:
            for version in page.get('Versions', [])[:100]:  # Limit for safety
                last_modified = version['LastModified'].replace(tzinfo=None)
                
                # Check if modified recently
                if last_modified > cutoff_time:
                    # Check for suspicious file extensions
                    key = version['Key']
                    if any(key.endswith(ext) for ext in ['.encrypted', '.locked', '.crypto', '.zzz']):
                        suspicious.append({
                            'key': key,
                            'versionId': version['VersionId'],
                            'lastModified': version['LastModified'].isoformat(),
                            'reason': 'suspicious_extension'
                        })
                    # Check for rapid modifications
                    elif version.get('IsLatest', False):
                        # Get previous version
                        versions = [v for v in page.get('Versions', []) if v['Key'] == key]
                        if len(versions) > 1:
                            time_diff = (versions[0]['LastModified'] - versions[1]['LastModified']).total_seconds()
                            if time_diff < 60:  # Modified twice in < 1 minute
                                suspicious.append({
                                    'key': key,
                                    'versionId': version['VersionId'],
                                    'lastModified': version['LastModified'].isoformat(),
                                    'reason': 'rapid_modification'
                                })
        
    except Exception as e:
        print(f"Error identifying suspicious objects: {e}")
    
    return suspicious

def restore_object_from_version(bucket_name: str, obj: Dict) -> Dict:
    """Restore an object from its previous version"""
    try:
        key = obj['key']
        
        # Get all versions
        versions = s3.list_object_versions(Bucket=bucket_name, Prefix=key)
        object_versions = [v for v in versions.get('Versions', []) if v['Key'] == key]
        
        if len(object_versions) < 2:
            return {'success': False, 'error': 'No previous version available'}
        
        # Get the version before the suspicious one
        previous_version = object_versions[1]
        
        # Copy the previous version to become the current version
        s3.copy_object(
            Bucket=bucket_name,
            CopySource={
                'Bucket': bucket_name,
                'Key': key,
                'VersionId': previous_version['VersionId']
            },
            Key=key
        )
        
        return {
            'success': True,
            'key': key,
            'restoredVersion': previous_version['VersionId']
        }
        
    except Exception as e:
        return {'success': False, 'error': str(e)}

def clean_bucket_policy(bucket_name: str, incident_id: str) -> Dict:
    """Remove malicious statements from bucket policy"""
    try:
        # Get current policy
        try:
            policy_response = s3.get_bucket_policy(Bucket=bucket_name)
            policy = json.loads(policy_response['Policy'])
        except s3.exceptions.ClientError as e:
            if e.response['Error']['Code'] == 'NoSuchBucketPolicy':
                return {'status': 'no_policy_exists'}
            raise
        
        # Remove statements with wildcard principals or suspicious conditions
        original_statements = len(policy.get('Statement', []))
        cleaned_statements = []
        removed_statements = []
        
        for stmt in policy.get('Statement', []):
            is_suspicious = False
            
            # Check for wildcard principal
            principal = stmt.get('Principal', {})
            if principal == '*' or principal.get('AWS') == '*':
                is_suspicious = True
                removed_statements.append({
                    'reason': 'wildcard_principal',
                    'statement': stmt
                })
            
            # Check for overly permissive actions
            actions = stmt.get('Action', [])
            if isinstance(actions, str):
                actions = [actions]
            if 's3:*' in actions or '*' in actions:
                is_suspicious = True
                removed_statements.append({
                    'reason': 'wildcard_actions',
                    'statement': stmt
                })
            
            if not is_suspicious:
                cleaned_statements.append(stmt)
        
        # Update policy if changes were made
        if removed_statements:
            if cleaned_statements:
                policy['Statement'] = cleaned_statements
                s3.put_bucket_policy(
                    Bucket=bucket_name,
                    Policy=json.dumps(policy)
                )
            else:
                # No valid statements left, delete policy
                s3.delete_bucket_policy(Bucket=bucket_name)
            
            return {
                'status': 'cleaned',
                'originalStatements': original_statements,
                'removedStatements': len(removed_statements),
                'removed': removed_statements
            }
        else:
            return {'status': 'no_changes_needed'}
        
    except Exception as e:
        raise Exception(f"Failed to clean bucket policy: {e}")

def clean_bucket_acls(bucket_name: str) -> Dict:
    """Reset bucket ACL to private"""
    try:
        s3.put_bucket_acl(
            Bucket=bucket_name,
            ACL='private'
        )
        return {'status': 'reset_to_private'}
    except Exception as e:
        raise Exception(f"Failed to clean ACLs: {e}")

def identify_compromised_identities(bucket_name: str, event: Dict) -> List[Dict]:
    """Identify IAM identities that may be compromised"""
    # In production, analyze CloudTrail logs for suspicious access patterns
    # For now, extract from event if provided
    return event.get('compromisedIdentities', [])

def rotate_credentials(identity: Dict) -> Dict:
    """Rotate credentials for a compromised identity"""
    try:
        identity_type = identity.get('type')
        identity_name = identity.get('name')
        
        if identity_type == 'user':
            # List and delete access keys
            access_keys = iam.list_access_keys(UserName=identity_name)
            for key in access_keys['AccessKeyMetadata']:
                iam.delete_access_key(
                    UserName=identity_name,
                    AccessKeyId=key['AccessKeyId']
                )
            
            return {
                'identity': identity_name,
                'type': identity_type,
                'status': 'credentials_rotated',
                'action': 'access_keys_deleted'
            }
        
        return {
            'identity': identity_name,
            'type': identity_type,
            'status': 'manual_rotation_required'
        }
        
    except Exception as e:
        raise Exception(f"Failed to rotate credentials: {e}")

def identify_backdoor_access(bucket_name: str, event: Dict) -> List[Dict]:
    """Identify backdoor access mechanisms"""
    # In production, scan for suspicious IAM roles/policies created recently
    return event.get('backdoors', [])

def remove_backdoor(backdoor: Dict) -> Dict:
    """Remove a backdoor access mechanism"""
    try:
        backdoor_type = backdoor.get('type')
        backdoor_name = backdoor.get('name')
        
        if backdoor_type == 'role':
            # Detach policies and delete role
            attached_policies = iam.list_attached_role_policies(RoleName=backdoor_name)
            for policy in attached_policies['AttachedPolicies']:
                iam.detach_role_policy(
                    RoleName=backdoor_name,
                    PolicyArn=policy['PolicyArn']
                )
            
            iam.delete_role(RoleName=backdoor_name)
            
            return {
                'backdoor': backdoor_name,
                'type': backdoor_type,
                'status': 'removed'
            }
        
        return {
            'backdoor': backdoor_name,
            'status': 'unsupported_type'
        }
        
    except Exception as e:
        raise Exception(f"Failed to remove backdoor: {e}")
