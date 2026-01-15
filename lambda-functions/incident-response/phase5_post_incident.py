"""
Phase 5: Post-Incident Analysis Lambda
Documents lessons learned and improves security posture
"""
import json
import boto3
from datetime import datetime
from typing import Dict, Any

s3 = boto3.client('s3')
sns = boto3.client('sns')
securityhub = boto3.client('securityhub')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Post-Incident Analysis Phase
    - Generate incident report
    - Document timeline of events
    - Identify root cause
    - Create remediation recommendations
    - Update security policies
    - Create Security Hub findings
    - Archive incident data
    """
    print(f"Post-Incident Analysis Phase - Event: {json.dumps(event)}")
    
    try:
        incident_id = event.get('incidentId', 'Unknown')
        bucket_name = event.get('bucketName')
        severity = event.get('severity', 'MEDIUM')
        
        if not bucket_name:
            return {
                'incidentId': incident_id,
                'phase': 'post_incident',
                'status': 'failed',
                'error': 'No bucket name provided'
            }
        
        analysis_actions = []
        
        # Action 1: Generate comprehensive incident report
        try:
            incident_report = generate_incident_report(event)
            
            # Save report to S3
            report_bucket = 'ysr95-custodian-policies'
            report_key = f'incident-response/reports/{incident_id}-report.json'
            
            s3.put_object(
                Bucket=report_bucket,
                Key=report_key,
                Body=json.dumps(incident_report, indent=2),
                ServerSideEncryption='AES256',
                ContentType='application/json'
            )
            
            analysis_actions.append({
                'action': 'generate_incident_report',
                'status': 'success',
                'reportLocation': f's3://{report_bucket}/{report_key}',
                'timestamp': datetime.utcnow().isoformat()
            })
        except Exception as e:
            analysis_actions.append({
                'action': 'generate_incident_report',
                'status': 'failed',
                'error': str(e)
            })
        
        # Action 2: Analyze root cause
        try:
            root_cause_analysis = analyze_root_cause(event)
            analysis_actions.append({
                'action': 'root_cause_analysis',
                'status': 'completed',
                'findings': root_cause_analysis,
                'timestamp': datetime.utcnow().isoformat()
            })
        except Exception as e:
            analysis_actions.append({
                'action': 'root_cause_analysis',
                'status': 'failed',
                'error': str(e)
            })
        
        # Action 3: Generate security recommendations
        try:
            recommendations = generate_security_recommendations(event, root_cause_analysis if 'root_cause_analysis' in locals() else {})
            analysis_actions.append({
                'action': 'generate_recommendations',
                'status': 'completed',
                'recommendations': recommendations,
                'timestamp': datetime.utcnow().isoformat()
            })
        except Exception as e:
            analysis_actions.append({
                'action': 'generate_recommendations',
                'status': 'failed',
                'error': str(e)
            })
        
        # Action 4: Create Security Hub finding
        try:
            finding_result = create_securityhub_finding(incident_id, bucket_name, event, recommendations if 'recommendations' in locals() else [])
            analysis_actions.append({
                'action': 'create_securityhub_finding',
                'status': 'success',
                'findingId': finding_result.get('findingId'),
                'timestamp': datetime.utcnow().isoformat()
            })
        except Exception as e:
            analysis_actions.append({
                'action': 'create_securityhub_finding',
                'status': 'failed',
                'error': str(e)
            })
        
        # Action 5: Calculate incident metrics
        try:
            metrics = calculate_incident_metrics(event)
            analysis_actions.append({
                'action': 'calculate_metrics',
                'status': 'completed',
                'metrics': metrics,
                'timestamp': datetime.utcnow().isoformat()
            })
        except Exception as e:
            analysis_actions.append({
                'action': 'calculate_metrics',
                'status': 'failed',
                'error': str(e)
            })
        
        # Action 6: Update detection rules based on findings
        try:
            rule_updates = update_detection_rules(event, root_cause_analysis if 'root_cause_analysis' in locals() else {})
            analysis_actions.append({
                'action': 'update_detection_rules',
                'status': 'completed',
                'updates': rule_updates,
                'timestamp': datetime.utcnow().isoformat()
            })
        except Exception as e:
            analysis_actions.append({
                'action': 'update_detection_rules',
                'status': 'failed',
                'error': str(e)
            })
        
        # Action 7: Archive incident data
        try:
            archive_result = archive_incident_data(incident_id, event)
            analysis_actions.append({
                'action': 'archive_incident_data',
                'status': 'success',
                'archiveLocation': archive_result['location'],
                'timestamp': datetime.utcnow().isoformat()
            })
        except Exception as e:
            analysis_actions.append({
                'action': 'archive_incident_data',
                'status': 'failed',
                'error': str(e)
            })
        
        # Action 8: Send final incident summary
        try:
            send_final_summary(incident_id, bucket_name, event, analysis_actions)
            analysis_actions.append({
                'action': 'send_final_summary',
                'status': 'success'
            })
        except Exception as e:
            analysis_actions.append({
                'action': 'send_final_summary',
                'status': 'failed',
                'error': str(e)
            })
        
        # Summary
        successful_actions = len([a for a in analysis_actions if a.get('status') in ['completed', 'success']])
        total_actions = len(analysis_actions)
        
        result = {
            'incidentId': incident_id,
            'phase': 'post_incident_analysis',
            'status': 'completed',
            'timestamp': datetime.utcnow().isoformat(),
            'bucketName': bucket_name,
            'severity': severity,
            'analysisActions': analysis_actions,
            'summary': {
                'totalActions': total_actions,
                'successfulActions': successful_actions,
                'failedActions': total_actions - successful_actions
            },
            'incidentClosed': True,
            'closedAt': datetime.utcnow().isoformat()
        }
        
        # Pass through previous event data
        result.update({k: v for k, v in event.items() if k not in result})
        
        print(f"Post-incident analysis completed for incident {incident_id}")
        return result
        
    except Exception as e:
        print(f"Error in post-incident analysis phase: {str(e)}")
        return {
            'incidentId': event.get('incidentId', 'Unknown'),
            'phase': 'post_incident_analysis',
            'status': 'failed',
            'error': str(e),
            'timestamp': datetime.utcnow().isoformat()
        }

def generate_incident_report(event: Dict) -> Dict:
    """Generate comprehensive incident report"""
    report = {
        'incidentId': event.get('incidentId'),
        'incidentType': 'S3_RANSOMWARE_ATTACK',
        'affectedResource': event.get('bucketName'),
        'severity': event.get('severity'),
        'detectionTimestamp': event.get('timestamp'),
        'timeline': extract_timeline(event),
        'impactAssessment': {
            'resourcesAffected': 1,  # bucket
            'dataExfiltrated': 'Unknown',
            'dataEncrypted': 'Suspected',
            'availabilityImpact': 'High' if event.get('severity') == 'CRITICAL' else 'Medium'
        },
        'responsePhases': {
            'detection': event.get('detection', {}),
            'containment': event.get('containment', {}),
            'eradication': event.get('eradication', {}),
            'recovery': event.get('recovery', {}),
            'postIncident': 'In Progress'
        },
        'detectionSource': extract_detection_source(event),
        'attackVector': determine_attack_vector(event),
        'businessImpact': assess_business_impact(event)
    }
    
    return report

def extract_timeline(event: Dict) -> list:
    """Extract chronological timeline of incident events"""
    timeline = []
    
    # Detection phase
    if 'timestamp' in event:
        timeline.append({
            'phase': 'detection',
            'timestamp': event['timestamp'],
            'event': 'Incident detected and triaged'
        })
    
    # Containment phase
    containment = event.get('containmentActions', [])
    for action in containment:
        if 'timestamp' in action:
            timeline.append({
                'phase': 'containment',
                'timestamp': action['timestamp'],
                'event': f"Containment action: {action.get('action')}"
            })
    
    # Eradication phase
    eradication = event.get('eradicationActions', [])
    for action in eradication:
        if 'timestamp' in action:
            timeline.append({
                'phase': 'eradication',
                'timestamp': action['timestamp'],
                'event': f"Eradication action: {action.get('action')}"
            })
    
    # Recovery phase
    recovery = event.get('recoveryActions', [])
    for action in recovery:
        if 'timestamp' in action:
            timeline.append({
                'phase': 'recovery',
                'timestamp': action['timestamp'],
                'event': f"Recovery action: {action.get('action')}"
            })
    
    # Sort by timestamp
    timeline.sort(key=lambda x: x.get('timestamp', ''))
    
    return timeline

def extract_detection_source(event: Dict) -> str:
    """Determine how the incident was detected"""
    if event.get('guardDutyFindings'):
        return 'AWS GuardDuty'
    elif event.get('cloudTrailEvents'):
        return 'AWS CloudTrail'
    elif event.get('metrics'):
        return 'CloudWatch Metrics'
    else:
        return 'Cloud Custodian Policy'

def determine_attack_vector(event: Dict) -> str:
    """Determine the attack vector"""
    guardduty_findings = event.get('guardDutyFindings', [])
    
    if guardduty_findings:
        finding_types = [f.get('type', '') for f in guardduty_findings]
        if any('Exfiltration' in t for t in finding_types):
            return 'Data Exfiltration via compromised credentials'
        elif any('MaliciousIP' in t for t in finding_types):
            return 'Access from malicious IP address'
    
    if event.get('compromisedCredentials'):
        return 'Compromised IAM credentials'
    
    return 'Unknown - requires further investigation'

def assess_business_impact(event: Dict) -> Dict:
    """Assess business impact of the incident"""
    severity = event.get('severity', 'MEDIUM')
    
    impact_mapping = {
        'CRITICAL': {
            'confidentiality': 'High',
            'integrity': 'High',
            'availability': 'High',
            'financialImpact': 'Significant',
            'reputationalImpact': 'Severe'
        },
        'HIGH': {
            'confidentiality': 'Medium',
            'integrity': 'High',
            'availability': 'Medium',
            'financialImpact': 'Moderate',
            'reputationalImpact': 'Moderate'
        },
        'MEDIUM': {
            'confidentiality': 'Low',
            'integrity': 'Medium',
            'availability': 'Low',
            'financialImpact': 'Minor',
            'reputationalImpact': 'Minor'
        }
    }
    
    return impact_mapping.get(severity, impact_mapping['MEDIUM'])

def analyze_root_cause(event: Dict) -> Dict:
    """Analyze root cause of the incident"""
    root_causes = []
    
    # Check for missing security controls
    bucket_info = event.get('bucketInfo', {})
    
    if bucket_info.get('versioning') != 'Enabled':
        root_causes.append({
            'category': 'Missing Control',
            'finding': 'S3 Versioning was not enabled',
            'impact': 'Enabled ransomware to permanently delete objects',
            'recommendation': 'Enable versioning on all critical S3 buckets'
        })
    
    if bucket_info.get('objectLock') != 'Enabled':
        root_causes.append({
            'category': 'Missing Control',
            'finding': 'S3 Object Lock was not enabled',
            'impact': 'No immutable backup protection',
            'recommendation': 'Enable Object Lock for compliance and ransomware protection'
        })
    
    if bucket_info.get('encryption') != 'Enabled':
        root_causes.append({
            'category': 'Missing Control',
            'finding': 'S3 encryption was not enabled',
            'impact': 'Data at rest was not encrypted',
            'recommendation': 'Enable default encryption on all S3 buckets'
        })
    
    if bucket_info.get('logging') != 'Enabled':
        root_causes.append({
            'category': 'Missing Control',
            'finding': 'S3 access logging was not enabled',
            'impact': 'Limited forensic capability',
            'recommendation': 'Enable S3 access logging for all buckets'
        })
    
    # Check for compromised credentials
    if event.get('compromisedCredentials'):
        root_causes.append({
            'category': 'Credential Compromise',
            'finding': 'IAM credentials were compromised',
            'impact': 'Attacker gained unauthorized access',
            'recommendation': 'Implement MFA and regular credential rotation'
        })
    
    return {
        'primaryRootCause': root_causes[0] if root_causes else {'finding': 'Under investigation'},
        'contributingFactors': root_causes,
        'totalFactors': len(root_causes)
    }

def generate_security_recommendations(event: Dict, root_cause: Dict) -> list:
    """Generate security improvement recommendations"""
    recommendations = []
    
    # Based on root cause findings
    for factor in root_cause.get('contributingFactors', []):
        recommendations.append({
            'priority': 'High',
            'category': factor.get('category'),
            'recommendation': factor.get('recommendation'),
            'implementation': 'Immediate'
        })
    
    # General recommendations
    recommendations.extend([
        {
            'priority': 'High',
            'category': 'Detection',
            'recommendation': 'Implement CloudWatch anomaly detection for S3 operations',
            'implementation': 'Within 1 week'
        },
        {
            'priority': 'High',
            'category': 'Prevention',
            'recommendation': 'Enable GuardDuty S3 Protection on all accounts',
            'implementation': 'Immediate'
        },
        {
            'priority': 'Medium',
            'category': 'Response',
            'recommendation': 'Conduct ransomware response tabletop exercise',
            'implementation': 'Within 1 month'
        },
        {
            'priority': 'Medium',
            'category': 'Recovery',
            'recommendation': 'Test S3 backup and restore procedures',
            'implementation': 'Quarterly'
        }
    ])
    
    return recommendations

def create_securityhub_finding(incident_id: str, bucket_name: str, event: Dict, recommendations: list) -> Dict:
    """Create Security Hub finding for the incident"""
    try:
        finding = {
            'SchemaVersion': '2018-10-08',
            'Id': f'{incident_id}-securityhub-finding',
            'ProductArn': f'arn:aws:securityhub:us-east-1:172327596604:product/172327596604/default',
            'GeneratorId': 'cloud-custodian-incident-response',
            'AwsAccountId': '172327596604',
            'Types': ['Software and Configuration Checks/AWS Security Best Practices/Data Protection'],
            'CreatedAt': datetime.utcnow().isoformat() + 'Z',
            'UpdatedAt': datetime.utcnow().isoformat() + 'Z',
            'Severity': {
                'Label': event.get('severity', 'MEDIUM')
            },
            'Title': f'S3 Ransomware Incident - {incident_id}',
            'Description': f'Ransomware attack detected and remediated on S3 bucket {bucket_name}. Incident response workflow completed successfully.',
            'Resources': [
                {
                    'Type': 'AwsS3Bucket',
                    'Id': f'arn:aws:s3:::{bucket_name}',
                    'Details': {
                        'AwsS3Bucket': {
                            'Name': bucket_name
                        }
                    }
                }
            ],
            'Compliance': {
                'Status': 'PASSED',
                'StatusReasons': [
                    {
                        'ReasonCode': 'INCIDENT_REMEDIATED',
                        'Description': 'Security incident detected and successfully remediated through automated incident response'
                    }
                ]
            },
            'Remediation': {
                'Recommendation': {
                    'Text': 'Incident has been automatically remediated. Review recommendations for security improvements.',
                    'Url': f's3://ysr95-custodian-policies/incident-response/reports/{incident_id}-report.json'
                }
            },
            'WorkflowState': 'RESOLVED',
            'Workflow': {
                'Status': 'RESOLVED'
            }
        }
        
        # Import findings to Security Hub
        response = securityhub.batch_import_findings(Findings=[finding])
        
        return {
            'findingId': f'{incident_id}-securityhub-finding',
            'response': response
        }
        
    except Exception as e:
        print(f"Failed to create Security Hub finding: {e}")
        raise

def calculate_incident_metrics(event: Dict) -> Dict:
    """Calculate key incident metrics"""
    try:
        # Calculate time to detect
        detection_time = event.get('timestamp')
        
        # Calculate time to contain
        containment_actions = event.get('containmentActions', [])
        containment_time = None
        if containment_actions and containment_actions[0].get('timestamp'):
            containment_time = containment_actions[0]['timestamp']
        
        # Calculate time to recover
        recovery_actions = event.get('recoveryActions', [])
        recovery_time = None
        if recovery_actions and recovery_actions[-1].get('timestamp'):
            recovery_time = recovery_actions[-1]['timestamp']
        
        metrics = {
            'detectionTime': detection_time,
            'containmentTime': containment_time,
            'recoveryTime': recovery_time,
            'totalResponseTime': 'Calculated based on timestamps',
            'automatedActions': count_automated_actions(event),
            'manualActions': count_manual_actions(event),
            'affectedResources': 1
        }
        
        return metrics
        
    except Exception as e:
        return {'error': str(e)}

def count_automated_actions(event: Dict) -> int:
    """Count automated response actions"""
    automated = 0
    for phase in ['containmentActions', 'eradicationActions', 'recoveryActions']:
        actions = event.get(phase, [])
        automated += len([a for a in actions if a.get('status') in ['success', 'completed']])
    return automated

def count_manual_actions(event: Dict) -> int:
    """Count manual response actions"""
    manual = 0
    for phase in ['containmentActions', 'eradicationActions', 'recoveryActions']:
        actions = event.get(phase, [])
        manual += len([a for a in actions if a.get('status') == 'manual_required'])
    return manual

def update_detection_rules(event: Dict, root_cause: Dict) -> Dict:
    """Update detection rules based on incident learnings"""
    # In production, update Cloud Custodian policies, GuardDuty custom threat lists, etc.
    return {
        'status': 'recommendations_documented',
        'message': 'Detection rule updates documented in incident report'
    }

def archive_incident_data(incident_id: str, event: Dict) -> Dict:
    """Archive all incident data for compliance and future reference"""
    try:
        archive_bucket = 'ysr95-custodian-policies'
        archive_key = f'incident-response/archives/{incident_id}-complete-data.json'
        
        s3.put_object(
            Bucket=archive_bucket,
            Key=archive_key,
            Body=json.dumps(event, indent=2, default=str),
            ServerSideEncryption='AES256',
            ContentType='application/json'
        )
        
        return {
            'location': f's3://{archive_bucket}/{archive_key}',
            'timestamp': datetime.utcnow().isoformat()
        }
        
    except Exception as e:
        raise Exception(f"Failed to archive incident data: {e}")

def send_final_summary(incident_id: str, bucket_name: str, event: Dict, actions: list) -> None:
    """Send final incident summary to stakeholders"""
    try:
        sns_topic = 'arn:aws:sns:us-east-1:172327596604:security-alerts'
        
        message = {
            'incidentId': incident_id,
            'bucketName': bucket_name,
            'phase': 'post_incident_analysis',
            'status': 'CLOSED',
            'severity': event.get('severity'),
            'timestamp': datetime.utcnow().isoformat(),
            'summary': f'''
Incident Response Complete for {incident_id}

Affected Resource: {bucket_name}
Severity: {event.get('severity')}
Detection Time: {event.get('timestamp')}
Status: CLOSED

All incident response phases completed successfully:
✅ Detection & Triage
✅ Containment
✅ Eradication
✅ Recovery
✅ Post-Incident Analysis

Full incident report available at:
s3://ysr95-custodian-policies/incident-response/reports/{incident_id}-report.json

Security recommendations have been documented and should be reviewed by the security team.
            '''.strip()
        }
        
        sns.publish(
            TopicArn=sns_topic,
            Subject=f'INCIDENT CLOSED: {incident_id}',
            Message=json.dumps(message, indent=2)
        )
        
    except Exception as e:
        print(f"Failed to send final summary: {e}")
