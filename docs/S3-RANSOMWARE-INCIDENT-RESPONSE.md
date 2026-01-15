# S3 Ransomware Detection and Incident Response

This solution provides comprehensive ransomware detection and automated incident response for S3 buckets using Cloud Custodian, AWS Step Functions, and Lambda.

## Architecture Overview

### Components

1. **Cloud Custodian Policies** - Real-time detection using:
   - CloudWatch Metrics (unusual delete operations, rapid modifications)
   - GuardDuty findings (S3 exfiltration, malicious IPs)
   - CloudTrail events (encryption tampering, policy changes)

2. **Step Functions State Machine** - Orchestrates 5-phase incident response
3. **Lambda Functions** - One per incident response phase
4. **SNS Topics** - Security alerts and notifications
5. **S3 Buckets** - Policy storage and incident archives

### Incident Response Phases

```
Detection → Containment → Eradication → Recovery → Post-Incident Analysis
```

#### Phase 1: Detection & Triage
- Validates and enriches security incidents
- Gathers S3 bucket metadata and CloudWatch metrics
- Fetches related GuardDuty findings
- Assesses severity and creates incident ID
- **Lambda**: `ir-phase1-detection-triage`

#### Phase 2: Containment
- Blocks public access to affected buckets
- Enables versioning to preserve object history
- Applies restrictive bucket policies (CRITICAL incidents)
- Tags bucket for incident tracking
- Disables compromised IAM credentials
- **Lambda**: `ir-phase2-containment`

#### Phase 3: Eradication
- Identifies and removes malicious objects
- Restores objects from previous versions
- Cleans bucket policies and ACLs
- Rotates compromised credentials
- Removes backdoor access mechanisms
- **Lambda**: `ir-phase3-eradication`

#### Phase 4: Recovery
- Verifies threat elimination
- Restores normal bucket configuration
- Re-enables legitimate access
- Validates data integrity
- Creates CloudWatch alarms for future detection
- **Lambda**: `ir-phase4-recovery`

#### Phase 5: Post-Incident Analysis
- Generates comprehensive incident report
- Performs root cause analysis
- Documents security recommendations
- Creates Security Hub findings
- Archives incident data for compliance
- **Lambda**: `ir-phase5-post-incident`

## Cloud Custodian Policies

### Real-Time Detection Policies

Located in: `policies/aws-s3-ransomware-detection.yml`

1. **s3-unusual-delete-operations** - Detects 20%+ decrease in objects/size
2. **s3-mass-deletion-detected** - Alerts on >100 objects deleted in 5 minutes
3. **s3-encryption-tampering** - Detects unauthorized encryption changes
4. **guardduty-s3-exfiltration-detected** - Processes GuardDuty S3 findings
5. **s3-bucket-policy-tampering** - Detects and removes malicious policies
6. **s3-rapid-object-modifications** - Detects >50 PutObject ops in 5 min
7. **s3-access-from-suspicious-ips** - Blocks known malicious IPs
8. **s3-replication-tampering** - Monitors replication config changes
9. **s3-object-lock-not-enabled** - Identifies unprotected critical buckets
10. **s3-versioning-disabled** - Auto-re-enables disabled versioning

### Policy Integration with Step Functions

Each policy includes an `invoke-sfn` action to trigger the incident response workflow:

```yaml
actions:
  - type: invoke-sfn
    state-machine: arn:aws:states:us-east-1:ACCOUNT_ID:stateMachine:s3-ransomware-incident-response
    async: true
```

## Deployment

### Prerequisites

1. AWS CLI configured with appropriate credentials
2. Terraform >= 1.0
3. Python 3.12
4. Cloud Custodian installed

### Steps

1. **Deploy Infrastructure** (Terraform):
```bash
cd terraform/central
terraform init
terraform plan
terraform apply
```

This creates:
- 5 Lambda functions (one per IR phase)
- Step Functions state machine
- IAM roles and policies
- SNS topic for security alerts
- CloudWatch log groups

2. **Deploy Cloud Custodian Policies**:

The policies are automatically deployed via GitHub Actions workflow `run-periodic-policies.yml`.

Manual deployment:
```bash
cd c7n
custodian run -s output/ransomware policies/aws-s3-ransomware-detection.yml
```

3. **Verify Deployment**:
```bash
# Check Step Functions
aws stepfunctions list-state-machines --query 'stateMachines[?contains(name, `incident-response`)]'

# Check Lambda functions
aws lambda list-functions --query 'Functions[?contains(FunctionName, `ir-phase`)]'

# Test policy execution
custodian run --dryrun -s output/test policies/aws-s3-ransomware-detection.yml
```

### Configuration

Edit `terraform/central/incident-response.tf`:

```hcl
variable "enable_incident_response" {
  default = true  # Set to false to disable IR infrastructure
}
```

Update SNS email subscription:
```hcl
resource "aws_sns_topic_subscription" "security_alerts_email" {
  endpoint = "your-email@example.com"  # Change this
}
```

## Testing the Workflow

### Manual Test

1. **Trigger Step Functions directly**:
```bash
aws stepfunctions start-execution \
  --state-machine-arn arn:aws:states:us-east-1:ACCOUNT_ID:stateMachine:s3-ransomware-incident-response \
  --input '{
    "bucketName": "test-bucket",
    "severity": "HIGH",
    "triggerEvent": {
      "detail": {
        "eventName": "DeleteObject"
      }
    }
  }'
```

2. **Simulate ransomware activity** (in test environment):
```bash
# Create test bucket
aws s3 mb s3://test-ransomware-bucket

# Rapid deletions (triggers detection)
for i in {1..150}; do
  aws s3 rm s3://test-ransomware-bucket/file-$i.txt
done
```

3. **Monitor execution**:
```bash
aws stepfunctions list-executions \
  --state-machine-arn arn:aws:states:us-east-1:ACCOUNT_ID:stateMachine:s3-ransomware-incident-response \
  --max-results 1
```

### Expected Behavior

1. **Detection**: Policy triggers and invokes Step Functions
2. **Containment**: Bucket public access blocked, versioning enabled
3. **Eradication**: Malicious objects removed/restored
4. **Recovery**: Normal operations restored, alarms created
5. **Post-Incident**: Report generated, Security Hub finding created

### Notifications

You'll receive SNS emails at each major milestone:
- Manual review required (MEDIUM severity)
- Containment complete
- Recovery complete (or manual intervention needed)
- Incident closed with full report

## Monitoring

### CloudWatch Dashboards

View execution metrics:
- Step Functions executions (success/failure rate)
- Lambda duration and errors
- CloudWatch Logs for detailed traces

### Security Hub

Incident findings appear in Security Hub:
- Filter by compliance status: PASSED
- Generator ID: `cloud-custodian-incident-response`

### Incident Reports

Stored in S3:
```
s3://ysr95-custodian-policies/incident-response/
├── reports/
│   └── IR-YYYYMMDD-HHMMSS-bucketname-report.json
├── policy-backups/
│   └── IR-YYYYMMDD-HHMMSS-bucketname-policy.json
└── archives/
    └── IR-YYYYMMDD-HHMMSS-bucketname-complete-data.json
```

## Customization

### Adjusting Detection Thresholds

Edit `policies/aws-s3-ransomware-detection.yml`:

```yaml
# Change delete threshold from 20% to 30%
- type: metrics
  name: NumberOfObjects
  op: percent-change
  value: -30  # Changed from -20
```

### Adding Custom Response Actions

Create new Lambda in Phase 2 (Containment):

```python
# Add to phase2_containment.py
containment_actions.append({
    'action': 'send_to_slack',
    'status': 'success'
})
```

### Modifying State Machine Flow

Edit `lambda-functions/incident-response/state-machine-definition.json`:

```json
{
  "NewState": {
    "Type": "Task",
    "Resource": "...",
    "Next": "Phase2_Containment"
  }
}
```

## Cost Estimation

### Monthly Costs (approximate)

- **Lambda**: $5-20 (5 functions, avg 10 executions/month)
- **Step Functions**: $1-5 (state transitions)
- **CloudWatch Logs**: $2-10 (90-day retention)
- **SNS**: <$1 (email notifications)
- **S3**: <$1 (incident reports)
- **Total**: ~$10-40/month

## Security Best Practices

1. **Enable GuardDuty S3 Protection** in all accounts
2. **Configure S3 Object Lock** on critical buckets
3. **Enable S3 versioning** on all production buckets
4. **Test incident response** quarterly
5. **Review and update** threat intelligence lists monthly
6. **Rotate credentials** regularly
7. **Monitor Step Functions** execution metrics

## Troubleshooting

### Common Issues

**Issue**: Step Functions not triggered by Cloud Custodian
- **Solution**: Check IAM permissions for Lambda to invoke Step Functions
- Verify state machine ARN in policy is correct

**Issue**: Lambda timeout during eradication
- **Solution**: Increase timeout in `incident-response.tf` (currently 600s)
- Reduce batch size in `phase3_eradication.py`

**Issue**: SNS emails not received
- **Solution**: Confirm subscription in SNS console
- Check email spam folder

**Issue**: Bucket policy restoration fails
- **Solution**: Check if backup exists in S3
- Verify IAM permissions for S3:GetObject on backup bucket

### Debug Commands

```bash
# View Lambda logs
aws logs tail /aws/lambda/incident-response --follow

# Check Step Functions execution
aws stepfunctions describe-execution \
  --execution-arn arn:aws:states:...

# List recent GuardDuty findings
aws guardduty list-findings --detector-id <id> --max-results 10
```

## Compliance and Audit

### Incident Data Retention

- **CloudWatch Logs**: 90 days
- **Incident Reports**: Indefinite (S3)
- **Step Functions History**: 90 days

### Audit Trail

Every incident includes:
1. Complete timeline of events
2. All actions taken (automated and manual)
3. Root cause analysis
4. Recommendations for improvement
5. Security Hub finding

## Contributing

To add new detection patterns:

1. Create policy in `policies/aws-s3-ransomware-detection.yml`
2. Test with `--dryrun` flag
3. Deploy via GitHub Actions or manual `custodian run`

## Support

For issues or questions:
- Review CloudWatch Logs first
- Check incident reports in S3
- Consult Security Hub findings

## License

This is proprietary security infrastructure for internal use.
