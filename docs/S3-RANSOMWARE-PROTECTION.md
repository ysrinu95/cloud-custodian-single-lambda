# S3 Ransomware Protection with Cloud Custodian

## Overview

This document explains how to use Cloud Custodian to detect and prevent ransomware attacks on Amazon S3, specifically targeting:

1. **Data Exfiltration** - Unauthorized data transfer out of your AWS environment
2. **Unauthorized Encryption** - Data encrypted with attacker-controlled keys

## Attack Scenarios Covered

### 1. Data Exfiltration Attacks

#### Scenario 1.1: Cross-Account Access
**Attack Method:** Attacker modifies bucket policy to grant access to their AWS account, then copies data out.

**Detection Policy:** `s3-cross-account-access-unauthorized`
- Monitors `PutBucketPolicy` CloudTrail events in real-time
- Checks if bucket policy allows access from non-whitelisted accounts
- **Automatic Remediation:** Removes unauthorized policy statements
- **Alert:** Sends critical notification to security team

**CloudTrail Event:**
```json
{
  "eventName": "PutBucketPolicy",
  "requestParameters": {
    "bucketName": "my-sensitive-data",
    "bucketPolicy": {
      "Statement": [{
        "Principal": {"AWS": "arn:aws:iam::ATTACKER-ACCOUNT:root"}
      }]
    }
  }
}
```

#### Scenario 1.2: Public Bucket Exposure
**Attack Method:** Attacker makes bucket public to exfiltrate data via anonymous access.

**Detection Policy:** `s3-public-access-ransomware`
- Monitors `PutBucketAcl` and `PutBucketPolicy` events
- Detects public access configurations
- **Automatic Remediation:**
  - Enables S3 Block Public Access
  - Removes public bucket policies
- **Alert:** Critical notification with remediation actions

#### Scenario 1.3: Bucket Replication
**Attack Method:** Attacker configures cross-region replication to their account.

**Detection Policy:** `s3-replication-to-untrusted-account`
- Monitors `PutBucketReplication` events
- Validates destination account is trusted
- **Automatic Remediation:** Deletes unauthorized replication configuration
- **Alert:** Critical notification

**Example Malicious Replication:**
```yaml
Destination:
  Account: "999999999999"  # Attacker account
  Bucket: "arn:aws:s3:::attacker-bucket"
```

### 2. Unauthorized Encryption Attacks

#### Scenario 2.1: External KMS Key Encryption
**Attack Method:** Attacker re-encrypts bucket with KMS key from their account, making data inaccessible without their key.

**Detection Policy:** `s3-encryption-unknown-kms-key`
- Monitors `PutBucketEncryption` events in real-time
- Validates KMS key belongs to trusted accounts/aliases
- **Automatic Remediation:** Resets encryption to AWS-managed AES256
- **Alert:** Critical notification with key details

**CloudTrail Event:**
```json
{
  "eventName": "PutBucketEncryption",
  "requestParameters": {
    "ServerSideEncryptionConfiguration": {
      "Rules": [{
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "aws:kms",
          "KMSMasterKeyID": "arn:aws:kms:us-east-1:ATTACKER-ACCOUNT:key/xxxxx"
        }
      }]
    }
  }
}
```

#### Scenario 2.2: Customer-Provided Key (SSE-C)
**Attack Method:** Attacker uploads objects encrypted with SSE-C using their own key not stored in AWS.

**Detection Policy:** `s3-object-encryption-customer-key`
- Monitors `PutObject` events with SSE-C headers
- Detects when objects are encrypted with customer-provided keys
- **Alert:** Critical notification (no automatic remediation - requires manual recovery)

**Attack Headers:**
```
x-amz-server-side-encryption-customer-algorithm: AES256
x-amz-server-side-encryption-customer-key: <attacker-key-base64>
x-amz-server-side-encryption-customer-key-MD5: <key-md5>
```

**Why This is Dangerous:**
- Customer-provided key is NOT stored in AWS
- Without the attacker's key, objects are permanently inaccessible
- Cannot be decrypted even by AWS or account owner

#### Scenario 2.3: Encryption Configuration Tampering
**Attack Method:** Attacker changes or removes encryption configuration as preparation for attack.

**Detection Policy:** `s3-encryption-configuration-change`
- Monitors `PutBucketEncryption` and `DeleteBucketEncryption` events
- Validates changes are made by authorized principals
- **Alert:** Warning notification for review

### 3. Attack Preparation Detection

#### Scenario 3.1: Versioning Disabled
**Attack Method:** Attacker disables versioning before encrypting data to prevent recovery from previous versions.

**Detection Policy:** `s3-versioning-disabled`
- Monitors `PutBucketVersioning` events
- Detects when versioning is suspended or disabled
- **Automatic Remediation:** Re-enables versioning
- **Alert:** Critical notification

**Attack Sequence:**
1. Disable versioning
2. Encrypt all objects with attacker key
3. Delete old versions (if versioning was previously enabled)

#### Scenario 3.2: Object Lock Manipulation
**Attack Method:** Attacker enables object lock on encrypted objects to make them immutable.

**Detection Policy:** `s3-object-lock-configuration-change`
- Monitors `PutObjectLockConfiguration` events
- Validates changes are from authorized sources
- **Alert:** Critical notification for immediate review

## Deployment

### 1. Update Trusted Accounts

Edit `policies/s3-ransomware-protection.yml` and update whitelisted account IDs:

```yaml
filters:
  - type: cross-account
    whitelist:
      - "172327596604"  # Your central account
      - "813185901390"  # Your member account
      - "123456789012"  # Add other trusted accounts
```

### 2. Update Trusted KMS Keys

Add your organization's KMS key aliases:

```yaml
filters:
  - type: kms-key
    key: c7n:AliasName
    op: not-in
    value:
      - alias/aws/s3
      - alias/your-org-encryption-key
      - alias/backup-encryption-key
```

### 3. Update Authorized Principals

Add IAM roles/users authorized to modify encryption:

```yaml
filters:
  - type: event
    key: "userIdentity.arn"
    op: not-in
    value:
      - "arn:aws:iam::172327596604:role/AdminRole"
      - "arn:aws:iam::172327596604:user/SecurityAdmin"
```

### 4. Deploy Policies

```bash
# Validate policies
custodian validate policies/s3-ransomware-protection.yml

# Deploy to AWS (creates Lambda functions for real-time monitoring)
custodian run \
  --region us-east-1 \
  --output-dir ./output \
  policies/s3-ransomware-protection.yml
```

### 5. Using GitHub Actions

Add to your workflow dispatch or commit the policy file:

```bash
git add policies/s3-ransomware-protection.yml
git commit -m "feat: Add S3 ransomware protection policies"
git push origin main

# Or trigger via GitHub Actions
gh workflow run cloud-custodian-policies.yml \
  -f operation_type=validate-and-deploy \
  -f policy_file=s3-ransomware-protection.yml
```

## Policy Execution Modes

### Real-Time Detection (CloudTrail Mode)
Policies with `mode: cloudtrail` execute within seconds of the event:
- `s3-cross-account-access-unauthorized`
- `s3-public-access-ransomware`
- `s3-replication-to-untrusted-account`
- `s3-encryption-unknown-kms-key`
- `s3-object-encryption-customer-key`
- `s3-versioning-disabled`

### Periodic Scans
Policies with `mode: periodic` run on schedule:
- `s3-scan-external-kms-encryption` - Every 24 hours
- `s3-bucket-policy-suspicious-principals` - Every 6 hours

## Alert Notifications

All policies send notifications via:
1. **SQS Queue:** `cloud-custodian-mailer-queue-prod`
2. **Mailer Lambda:** Processes queue messages
3. **SNS Topic:** Publishes to email
4. **Email Recipients:** 
   - security@example.com
   - ysrinu95@gmail.com

### Alert Severity Levels

- **Priority 1 (CRITICAL):** Immediate action required
  - Cross-account access
  - Public bucket exposure
  - Unknown KMS key encryption
  - SSE-C encryption detected
  - Versioning disabled

- **Priority 2 (WARNING):** Review required
  - Encryption configuration changes
  - Authorized but unusual activities

## Testing

### Test Data Exfiltration Detection

```bash
# Test cross-account access detection
aws s3api put-bucket-policy \
  --bucket test-ransomware-bucket \
  --policy '{
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"AWS": "arn:aws:iam::999999999999:root"},
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::test-ransomware-bucket/*"
    }]
  }'

# Expected: Policy removed within 30 seconds, alert sent
```

### Test Unauthorized Encryption Detection

```bash
# Create a test KMS key
aws kms create-key --description "Test ransomware key"

# Apply to bucket
aws s3api put-bucket-encryption \
  --bucket test-ransomware-bucket \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "aws:kms",
        "KMSMasterKeyID": "arn:aws:kms:us-east-1:172327596604:key/test-key-id"
      }
    }]
  }'

# Expected: Encryption reset to AES256, alert sent
```

### Test SSE-C Detection

```bash
# Generate a test key
KEY=$(openssl rand -base64 32)
KEY_MD5=$(echo -n "$KEY" | base64 -d | md5sum | awk '{print $1}' | xxd -r -p | base64)

# Upload object with SSE-C
aws s3api put-object \
  --bucket test-ransomware-bucket \
  --key test-object.txt \
  --body test-file.txt \
  --sse-customer-algorithm AES256 \
  --sse-customer-key "$KEY" \
  --sse-customer-key-md5 "$KEY_MD5"

# Expected: Alert sent (object remains encrypted)
```

## Incident Response

### If Cross-Account Access Detected:
1. ✅ **Automatic:** Unauthorized policy statements removed
2. 🔍 **Manual:** Review CloudTrail for `PutBucketPolicy` event
3. 🔒 **Manual:** Check if any data was accessed via GetObject calls
4. 📊 **Manual:** Enable S3 access logging if not already enabled
5. 🚨 **Manual:** Report incident if data was accessed

### If Unauthorized KMS Key Detected:
1. ✅ **Automatic:** Encryption reset to AWS-managed AES256
2. 🔍 **Manual:** Identify the KMS key owner via CloudTrail
3. 🔒 **Manual:** Check if any objects were re-encrypted
4. 📊 **Manual:** Review IAM permissions for bucket access
5. 🚨 **Manual:** If objects were re-encrypted, restore from backups

### If SSE-C Encryption Detected:
1. ⚠️ **CRITICAL:** Objects may be permanently inaccessible
2. 🔍 **Manual:** Identify the user/principal from CloudTrail
3. 🔒 **Manual:** Immediately revoke credentials
4. 📊 **Manual:** Check S3 versioning for previous unencrypted versions
5. 🚨 **Manual:** Restore objects from backups or previous versions
6. 📝 **Manual:** Document incident for forensic analysis

## Best Practices

### Prevention:
1. ✅ Enable S3 Block Public Access at account level
2. ✅ Enable S3 versioning on all buckets
3. ✅ Use SCPs to prevent encryption changes by unauthorized principals
4. ✅ Require MFA for sensitive S3 operations
5. ✅ Enable S3 Object Lock for critical data (immutable backups)
6. ✅ Use VPC endpoints for S3 access (prevent internet exfiltration)
7. ✅ Enable AWS CloudTrail for S3 data events

### Detection:
1. ✅ Deploy all Cloud Custodian ransomware policies
2. ✅ Enable S3 access logging to separate logging bucket
3. ✅ Use AWS GuardDuty for anomaly detection
4. ✅ Monitor CloudWatch Metrics for unusual data transfer patterns
5. ✅ Set up AWS Config Rules for compliance monitoring

### Response:
1. ✅ Have tested backup and recovery procedures
2. ✅ Maintain offline/air-gapped backups
3. ✅ Document incident response playbook
4. ✅ Regularly test Cloud Custodian policies
5. ✅ Review CloudTrail logs daily for anomalies

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    S3 Ransomware Protection                  │
└─────────────────────────────────────────────────────────────┘
                               │
                               ▼
                    ┌──────────────────┐
                    │   CloudTrail     │
                    │  S3 API Events   │
                    └────────┬─────────┘
                             │
                ┌────────────┼────────────┐
                ▼            ▼            ▼
    ┌──────────────┐ ┌─────────────┐ ┌──────────────┐
    │ PutBucket    │ │ PutObject   │ │ PutBucket    │
    │   Policy     │ │  (SSE-C)    │ │ Encryption   │
    └──────┬───────┘ └──────┬──────┘ └──────┬───────┘
           │                │                │
           └────────────────┼────────────────┘
                            ▼
                 ┌────────────────────┐
                 │ Cloud Custodian    │
                 │  Lambda Function   │
                 └──────────┬─────────┘
                            │
                ┌───────────┴───────────┐
                ▼                       ▼
    ┌─────────────────────┐  ┌────────────────────┐
    │  Auto Remediation:  │  │   Notification:    │
    │  • Remove Policy    │  │  • SQS Queue       │
    │  • Block Public     │  │  • Mailer Lambda   │
    │  • Reset Encryption │  │  • SNS → Email     │
    │  • Enable Versioning│  │  • Security Team   │
    └─────────────────────┘  └────────────────────┘
```

## Monitoring Dashboard

Create CloudWatch Dashboard to monitor:

```bash
# Metric: Ransomware policy violations
Namespace: CloudCustodian
Metric: PolicyViolation
Dimensions: PolicyName=s3-ransomware-*

# Metric: Auto-remediation actions
Namespace: CloudCustodian
Metric: ActionExecution
Dimensions: ActionType=remove-statements,set-bucket-encryption

# Metric: SSE-C encryption events (CRITICAL)
Namespace: CloudCustodian
Metric: PolicyMatch
Dimensions: PolicyName=s3-object-encryption-customer-key
```

## Compliance Mapping

These policies help with compliance requirements:

- **PCI-DSS 3.4:** Protect stored cardholder data
- **HIPAA:** Protect PHI from unauthorized access
- **GDPR Article 32:** Security of processing
- **SOC 2:** Logical access controls
- **NIST 800-53:** SC-28 (Protection of data at rest)

## Support

For issues or questions:
- GitHub Issues: https://github.com/ysrinu95/cloud-custodian-single-lambda/issues
- Email: ysrinu95@gmail.com
- AWS Support: For CloudTrail/S3 service issues

## References

- [Cloud Custodian Documentation](https://cloudcustodian.io/docs/)
- [AWS S3 Security Best Practices](https://docs.aws.amazon.com/AmazonS3/latest/userguide/security-best-practices.html)
- [AWS S3 Encryption](https://docs.aws.amazon.com/AmazonS3/latest/userguide/UsingEncryption.html)
- [Ransomware Risk Management](https://aws.amazon.com/blogs/security/ransomware-risk-management-on-aws/)
