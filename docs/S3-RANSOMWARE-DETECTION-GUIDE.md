# S3 Ransomware Detection and Prevention - Complete Guide

## 🎯 Overview

This solution provides comprehensive, production-ready S3 ransomware detection and automated response using Cloud Custodian. It combines:

- **Event-driven policies** for real-time detection
- **CloudWatch metrics monitoring** for anomaly detection  
- **Automated remediation** for known attack patterns
- **Simulation workflows** for testing and validation

## 📋 Table of Contents

1. [Attack Patterns Detected](#attack-patterns-detected)
2. [Architecture](#architecture)
3. [Policies Overview](#policies-overview)
4. [Deployment](#deployment)
5. [Testing with Simulation](#testing-with-simulation)
6. [Incident Response](#incident-response)
7. [Best Practices](#best-practices)

## 🔍 Attack Patterns Detected

### 1. **Mass Deletion**
- Rapid deletion of objects (>50 in 5 minutes)
- >20% decrease in object count within 1 hour
- Sudden drop in bucket size

### 2. **Mass Encryption/Overwriting**
- Abnormal PUT request spike (>100 in 10 minutes)
- Objects replaced with encrypted content
- Ransom note files (RANSOM_NOTE.txt, READ_ME.txt, etc.)

### 3. **Configuration Tampering**
- Versioning disabled/suspended
- Bucket encryption removed
- Replication configuration deleted
- Public Access Block disabled

### 4. **Data Exfiltration**
- 200%+ increase in bytes downloaded
- Suspicious cross-account access
- Malicious bucket policies allowing external access

### 5. **Reconnaissance**
- Spike in 4xx errors (failed access attempts)
- Unusual access patterns
- Requests from known malicious IPs

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        CloudTrail Events                         │
│  DeleteObject, PutBucketPolicy, PutBucketVersioning, etc.       │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│                      EventBridge Rules                           │
│  Filter ransomware-related S3 events                            │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│                   Cloud Custodian Lambda                         │
│  • Pre-validation                                               │
│  • Policy evaluation                                            │
│  • Automated remediation                                        │
└───────────────┬─────────────────────────┬───────────────────────┘
                │                         │
                ↓                         ↓
┌───────────────────────────┐   ┌─────────────────────────────────┐
│   SQS → SNS → Email       │   │      Security Hub Findings      │
│   Immediate Alerts        │   │      Centralized Tracking       │
└───────────────────────────┘   └─────────────────────────────────┘

PLUS

┌─────────────────────────────────────────────────────────────────┐
│                    CloudWatch S3 Metrics                         │
│  NumberOfObjects, BucketSizeBytes, BytesDownloaded              │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│              Cloud Custodian Periodic Policies                   │
│  Run every 10-15 minutes to detect anomalies                    │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ↓
                    Same Alert Flow ↑
```

## 📜 Policies Overview

### Event-Driven Policies (`aws-s3-ransomware-protection.yml`)

| Policy Name | Trigger | Action | Severity |
|------------|---------|--------|----------|
| `s3-mass-deletion-realtime` | DeleteObject events | Notify + Security Hub | CRITICAL |
| `s3-encryption-tampering` | DeleteBucketEncryption | Auto-remediate + Notify | CRITICAL |
| `s3-versioning-suspended` | PutBucketVersioning | Auto-remediate + Notify | HIGH |
| `s3-malicious-bucket-policy` | PutBucketPolicy | Remove policy + Notify | CRITICAL |
| `s3-public-access-block-disabled` | DeletePublicAccessBlock | Auto-remediate + Notify | HIGH |
| `s3-replication-tampering` | DeleteBucketReplication | Notify | HIGH |
| `s3-ransom-note-detection` | Object pattern match | Isolate bucket + Notify | CRITICAL |
| `s3-object-lock-not-enabled` | Periodic scan | Notify | MEDIUM |

### Metrics-Based Policies (`aws-s3-ransomware-metrics.yml`)

| Policy Name | Metric | Threshold | Check Frequency |
|------------|--------|-----------|-----------------|
| `s3-object-count-rapid-decrease` | NumberOfObjects | -20% in 1 hour | 15 minutes |
| `s3-bucket-size-rapid-decrease` | BucketSizeBytes | -20% in 1 hour | 15 minutes |
| `s3-abnormal-put-spike` | AllRequests (PUT) | >100 in 10 min | 10 minutes |
| `s3-error-rate-spike` | 4xxErrors | >50 in 10 min | 10 minutes |
| `s3-data-exfiltration-spike` | BytesDownloaded | +200% | 15 minutes |
| `s3-performance-degradation` | FirstByteLatency | +100% | 15 minutes |

## 🚀 Deployment

### Prerequisites

1. **Enable CloudWatch S3 Metrics**
   ```bash
   # Enable Storage Metrics (required)
   aws s3api put-bucket-metrics-configuration \
     --bucket <BUCKET_NAME> \
     --id EntireBucket \
     --metrics-configuration '{
       "Id": "EntireBucket",
       "Filter": {
         "Prefix": ""
       }
     }'
   ```

2. **Ensure CloudTrail Logging**
   ```bash
   aws cloudtrail describe-trails \
     --query 'trailList[*].[Name,S3BucketName,IsMultiRegionTrail]'
   ```

3. **Enable S3 Versioning on Critical Buckets**
   ```bash
   aws s3api put-bucket-versioning \
     --bucket <BUCKET_NAME> \
     --versioning-configuration Status=Enabled
   ```

### Step 1: Deploy Infrastructure

```bash
# Deploy central account
cd terraform/central
terraform init
terraform plan
terraform apply

# Deploy member account
cd terraform/member
terraform init
terraform plan
terraform apply
```

### Step 2: Upload Policies to S3

```bash
cd c7n

# Upload ransomware protection policies
aws s3 cp policies/aws-s3-ransomware-protection.yml \
  s3://cloud-custodian-policies-<ACCOUNT>/

aws s3 cp policies/aws-s3-ransomware-metrics.yml \
  s3://cloud-custodian-policies-<ACCOUNT>/

# Upload account-policy-mapping.json
aws s3 cp config/account-policy-mapping.json \
  s3://cloud-custodian-policies-<ACCOUNT>/config/
```

### Step 3: Verify Deployment

```bash
# Check Lambda function
aws lambda get-function --function-name cloud-custodian

# Check EventBridge rules
aws events list-rules --name-prefix "cloud-custodian"

# Check CloudWatch Logs
aws logs tail /aws/lambda/cloud-custodian --since 5m --follow
```

## 🧪 Testing with Simulation

### Run Ransomware Simulation Workflow

1. **Navigate to GitHub Actions**:
   - Go to: `.github/workflows/simulate-s3-ransomware.yml`
   - Click "Run workflow"

2. **Choose Attack Type**:
   - `mass-deletion` - Simulates rapid object deletion
   - `mass-encryption` - Simulates file encryption/overwriting
   - `policy-tampering` - Simulates malicious bucket policy changes
   - `versioning-disable` - Simulates versioning suspension
   - `replication-tampering` - Simulates replication config deletion
   - `all-attacks` - Runs all attack simulations sequentially

3. **Configure Parameters**:
   - `target_bucket_prefix`: Prefix for test bucket (default: `ransomware-test`)
   - `object_count`: Number of test objects to create (default: `100`)
   - `cleanup_after_test`: Auto-cleanup resources (default: `true`)

4. **Monitor Detection**:
   - Check CloudWatch Logs: `/aws/lambda/cloud-custodian`
   - Check Security Hub findings
   - Check email notifications

### Manual Simulation

```bash
# 1. Create test bucket
BUCKET_NAME="ransomware-test-$(date +%s)"
aws s3 mb s3://$BUCKET_NAME
aws s3api put-bucket-versioning --bucket $BUCKET_NAME \
  --versioning-configuration Status=Enabled

# 2. Create test objects
for i in {1..100}; do
  echo "Test file $i" | aws s3 cp - s3://$BUCKET_NAME/file-$i.txt
done

# 3. Simulate mass deletion (triggers alert)
aws s3 rm s3://$BUCKET_NAME --recursive

# 4. Simulate versioning suspension (triggers auto-remediation)
aws s3api put-bucket-versioning --bucket $BUCKET_NAME \
  --versioning-configuration Status=Suspended

# 5. Check for alerts
aws logs tail /aws/lambda/cloud-custodian --since 5m
```

## 🚨 Incident Response

### Immediate Actions When Alert Received

1. **Verify the Alert**
   ```bash
   # Check CloudTrail for the event
   aws cloudtrail lookup-events \
     --lookup-attributes AttributeKey=EventName,AttributeValue=DeleteObject \
     --max-results 50
   ```

2. **Identify the Actor**
   ```bash
   # Get the IAM identity behind the events
   aws cloudtrail lookup-events \
     --lookup-attributes AttributeKey=EventName,AttributeValue=DeleteObject \
     --query 'Events[*].{User:Username,IP:SourceIPAddress,Time:EventTime}' \
     --output table
   ```

3. **Disable Compromised Credentials**
   ```bash
   # Disable access key
   aws iam update-access-key \
     --access-key-id <KEY_ID> \
     --status Inactive \
     --user-name <USERNAME>
   
   # Force session revocation
   aws iam delete-login-profile --user-name <USERNAME>
   ```

4. **Isolate the Bucket**
   ```bash
   # Apply restrictive bucket policy
   aws s3api put-bucket-policy --bucket <BUCKET> --policy '{
     "Version": "2012-10-17",
     "Statement": [{
       "Effect": "Deny",
       "Principal": "*",
       "Action": "s3:*",
       "Resource": ["arn:aws:s3:::<BUCKET>", "arn:aws:s3:::<BUCKET>/*"],
       "Condition": {
         "StringNotEquals": {
           "aws:PrincipalArn": "arn:aws:iam::<ACCOUNT>:role/IncidentResponseRole"
         }
       }
     }]
   }'
   ```

5. **Assess Damage**
   ```bash
   # List deleted objects
   aws s3api list-object-versions --bucket <BUCKET> \
     --query 'DeleteMarkers[*].[Key,VersionId,LastModified]' \
     --output table
   
   # Check versioning status
   aws s3api get-bucket-versioning --bucket <BUCKET>
   ```

### Recovery Steps

#### Recover Deleted Objects

```bash
# Remove delete markers to restore objects
aws s3api list-object-versions --bucket <BUCKET> \
  --query 'DeleteMarkers[*].[Key,VersionId]' --output text | \
  while read key versionId; do
    echo "Restoring $key"
    aws s3api delete-object --bucket <BUCKET> \
      --key "$key" --version-id "$versionId"
  done
```

#### Recover from Encryption Attack

```bash
# List object versions
aws s3api list-object-versions --bucket <BUCKET> \
  --query 'Versions[*].[Key,VersionId,LastModified]' \
  --output table

# Restore specific version
aws s3api copy-object \
  --copy-source <BUCKET>/<KEY>?versionId=<VERSION_ID> \
  --bucket <BUCKET> \
  --key <KEY>
```

## 🛡️ Best Practices

### Prevention

1. **Enable Versioning** on all critical buckets
   ```bash
   aws s3api put-bucket-versioning --bucket <BUCKET> \
     --versioning-configuration Status=Enabled
   ```

2. **Enable Object Lock** for immutable storage
   ```bash
   # Must be enabled at bucket creation
   aws s3api create-bucket --bucket <BUCKET> \
     --object-lock-enabled-for-bucket
   
   aws s3api put-object-lock-configuration --bucket <BUCKET> \
     --object-lock-configuration '{
       "ObjectLockEnabled": "Enabled",
       "Rule": {
         "DefaultRetention": {
           "Mode": "COMPLIANCE",
           "Days": 30
         }
       }
     }'
   ```

3. **Enable MFA Delete**
   ```bash
   aws s3api put-bucket-versioning --bucket <BUCKET> \
     --versioning-configuration Status=Enabled,MFADelete=Enabled \
     --mfa "arn:aws:iam::<ACCOUNT>:mfa/<USER> <MFA_CODE>"
   ```

4. **Enable GuardDuty S3 Protection**
   ```bash
   aws guardduty update-detector \
     --detector-id <DETECTOR_ID> \
     --data-sources S3Logs={Enable=true}
   ```

5. **Implement Least Privilege IAM**
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Effect": "Allow",
       "Action": [
         "s3:GetObject",
         "s3:PutObject"
       ],
       "Resource": "arn:aws:s3:::my-bucket/allowed-prefix/*"
     },
     {
       "Effect": "Deny",
       "Action": [
         "s3:DeleteObject",
         "s3:DeleteBucket",
         "s3:PutBucketPolicy"
       ],
       "Resource": "*"
     }]
   }
   ```

### Detection Enhancement

1. **Enable S3 Server Access Logging**
   ```bash
   aws s3api put-bucket-logging --bucket <BUCKET> --bucket-logging-status '{
     "LoggingEnabled": {
       "TargetBucket": "<LOG_BUCKET>",
       "TargetPrefix": "s3-access-logs/"
     }
   }'
   ```

2. **Set up CloudWatch Alarms**
   ```bash
   aws cloudwatch put-metric-alarm \
     --alarm-name s3-object-count-decrease \
     --alarm-description "Alert on rapid object count decrease" \
     --metric-name NumberOfObjects \
     --namespace AWS/S3 \
     --statistic Average \
     --period 3600 \
     --evaluation-periods 1 \
     --threshold 100 \
     --comparison-operator LessThanThreshold
   ```

3. **Enable AWS Config Rules**
   ```bash
   aws configservice put-config-rule --config-rule '{
     "ConfigRuleName": "s3-bucket-versioning-enabled",
     "Source": {
       "Owner": "AWS",
       "SourceIdentifier": "S3_BUCKET_VERSIONING_ENABLED"
     }
   }'
   ```

## 📊 Monitoring and Metrics

### Key Metrics to Monitor

1. **NumberOfObjects** - Rapid decrease indicates deletion
2. **BucketSizeBytes** - Sudden drop indicates data loss
3. **BytesDownloaded** - Spike indicates exfiltration
4. **4xxErrors** - Spike indicates scanning/probing
5. **AllRequests** - Unusual spike indicates automated activity

### CloudWatch Dashboards

Create a dashboard to monitor all ransomware indicators:

```bash
aws cloudwatch put-dashboard --dashboard-name S3-Ransomware-Monitoring \
  --dashboard-body file://cloudwatch-dashboard.json
```

## 📚 Additional Resources

- [AWS S3 Ransomware Defense](https://aws.amazon.com/blogs/security/anatomy-of-a-ransomware-event-targeting-data-in-amazon-s3/)
- [Cloud Custodian S3 Filters](https://cloudcustodian.io/docs/aws/resources/s3.html)
- [AWS Security Best Practices](https://docs.aws.amazon.com/security/latest/userguide/best-practices.html)
- [S3 Ransomware Playbook](https://github.com/aws-samples/aws-customer-playbook-framework/blob/main/docs/Ransom_Response_S3.md)

## 🤝 Contributing

To improve ransomware detection:

1. Add new attack patterns to policies
2. Enhance simulation scenarios
3. Improve remediation actions
4. Update documentation with lessons learned

## 📝 License

This solution is provided as-is for security enhancement purposes.
