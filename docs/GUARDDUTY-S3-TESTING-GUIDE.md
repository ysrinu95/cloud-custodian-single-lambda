# GuardDuty S3 Protection - Cloud Custodian Testing Guide

## Overview

This guide provides step-by-step testing procedures for Cloud Custodian policies that respond to AWS GuardDuty S3 Protection findings.

**Policy File**: `policies/guardduty-s3-protection-response.yml`

## Prerequisites

### 1. Enable GuardDuty with S3 Protection

```bash
# Get GuardDuty detector ID
DETECTOR_ID=$(aws guardduty list-detectors --query 'DetectorIds[0]' --output text --region us-east-1)

# Enable GuardDuty (if not already enabled)
if [ -z "$DETECTOR_ID" ]; then
  DETECTOR_ID=$(aws guardduty create-detector \
    --enable \
    --finding-publishing-frequency FIFTEEN_MINUTES \
    --region us-east-1 \
    --query 'DetectorId' --output text)
fi

# Enable S3 Protection
aws guardduty update-detector \
  --detector-id $DETECTOR_ID \
  --data-sources '{
    "S3Logs": {
      "Enable": true
    }
  }' \
  --region us-east-1

echo "GuardDuty Detector ID: $DETECTOR_ID"
```

### 2. Deploy Cloud Custodian Policies

```bash
# Validate policies
custodian validate policies/guardduty-s3-protection-response.yml

# Deploy policies (dry-run first)
custodian run \
  --region us-east-1 \
  --output-dir ./output \
  --dryrun \
  policies/guardduty-s3-protection-response.yml

# Deploy for real
custodian run \
  --region us-east-1 \
  --output-dir ./output \
  policies/guardduty-s3-protection-response.yml
```

### 3. Set Up Environment Variables

```bash
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export DETECTOR_ID=$(aws guardduty list-detectors --query 'DetectorIds[0]' --output text)
export TEST_BUCKET="guardduty-test-bucket-${AWS_ACCOUNT_ID}"
```

## Test Scenarios

### Test 1: Exfiltration - Anomalous Object Download

**GuardDuty Finding**: `Exfiltration:S3/AnomalousObjectDownload`

#### Setup

```bash
# Create test bucket
aws s3 mb s3://${TEST_BUCKET} --region ${AWS_REGION}

# Upload test objects
for i in {1..10}; do
  echo "Test data $i" > test-file-$i.txt
  aws s3 cp test-file-$i.txt s3://${TEST_BUCKET}/
done
```

#### Generate Finding

```bash
# Generate sample GuardDuty finding
aws guardduty create-sample-findings \
  --detector-id ${DETECTOR_ID} \
  --finding-types 'Exfiltration:S3/AnomalousObjectDownload' \
  --region ${AWS_REGION}

echo "✅ Finding generated. Waiting 1-2 minutes for GuardDuty to process..."
sleep 120
```

#### Verify Finding

```bash
# List recent findings
aws guardduty list-findings \
  --detector-id ${DETECTOR_ID} \
  --finding-criteria '{
    "Criterion": {
      "type": {
        "Eq": ["Exfiltration:S3/AnomalousObjectDownload"]
      },
      "updatedAt": {
        "Gte": '$(date -u -d '5 minutes ago' +%s000)'
      }
    }
  }' \
  --region ${AWS_REGION}

# Get finding details
FINDING_ID=$(aws guardduty list-findings \
  --detector-id ${DETECTOR_ID} \
  --max-results 1 \
  --query 'FindingIds[0]' \
  --output text \
  --region ${AWS_REGION})

aws guardduty get-findings \
  --detector-id ${DETECTOR_ID} \
  --finding-ids ${FINDING_ID} \
  --region ${AWS_REGION}
```

#### Expected Cloud Custodian Response

1. **Auto-Remediation**:
   - Block public access enabled on bucket
   - Bucket tagged with `GuardDutyFinding=Exfiltration-AnomalousDownload`
   - Bucket tagged with `SecurityIncident=Active`

2. **Alert Sent**:
   - SNS notification to security@example.com and ysrinu95@gmail.com
   - Subject: "CRITICAL: GuardDuty Detected S3 Data Exfiltration Attempt"

#### Verification

```bash
# Check bucket block public access
aws s3api get-public-access-block \
  --bucket ${TEST_BUCKET} \
  --region ${AWS_REGION}

# Expected output:
# {
#   "PublicAccessBlockConfiguration": {
#     "BlockPublicAcls": true,
#     "IgnorePublicAcls": true,
#     "BlockPublicPolicy": true,
#     "RestrictPublicBuckets": true
#   }
# }

# Check bucket tags
aws s3api get-bucket-tagging \
  --bucket ${TEST_BUCKET} \
  --region ${AWS_REGION}

# Expected tags:
# - GuardDutyFinding: Exfiltration-AnomalousDownload
# - SecurityIncident: Active
```

### Test 2: Impact - Permissions Modification

**GuardDuty Finding**: `Impact:S3/PermissionsModification.Unusual`

#### Setup

```bash
# Create test bucket with initial policy
aws s3 mb s3://${TEST_BUCKET}-permissions --region ${AWS_REGION}

# Apply a normal policy
aws s3api put-bucket-policy \
  --bucket ${TEST_BUCKET}-permissions \
  --policy '{
    "Version": "2012-10-17",
    "Statement": [{
      "Sid": "AllowAccountAccess",
      "Effect": "Allow",
      "Principal": {"AWS": "arn:aws:iam::'${AWS_ACCOUNT_ID}':root"},
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::'${TEST_BUCKET}'-permissions/*"
    }]
  }' \
  --region ${AWS_REGION}
```

#### Generate Finding

```bash
# Generate sample finding
aws guardduty create-sample-findings \
  --detector-id ${DETECTOR_ID} \
  --finding-types 'Impact:S3/PermissionsModification.Unusual' \
  --region ${AWS_REGION}

sleep 120
```

#### Expected Response

1. **Auto-Remediation**:
   - Public access blocked
   - Suspicious policy statements removed
   - Tagged with `GuardDutyFinding=Impact-PermissionsModified`
   - Tagged with `RequiresReview=Immediate`

2. **Alert**: Critical notification about permissions tampering

#### Verification

```bash
# Verify public access block
aws s3api get-public-access-block \
  --bucket ${TEST_BUCKET}-permissions \
  --region ${AWS_REGION}

# Check if policy was modified
aws s3api get-bucket-policy \
  --bucket ${TEST_BUCKET}-permissions \
  --region ${AWS_REGION} || echo "Policy removed"
```

### Test 3: Policy - Encryption Disabled

**GuardDuty Finding**: `Policy:S3/BucketEncryptionDisabled`

#### Setup

```bash
# Create bucket with encryption
aws s3 mb s3://${TEST_BUCKET}-encryption --region ${AWS_REGION}

aws s3api put-bucket-encryption \
  --bucket ${TEST_BUCKET}-encryption \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }' \
  --region ${AWS_REGION}

# Disable encryption (simulating attack)
aws s3api delete-bucket-encryption \
  --bucket ${TEST_BUCKET}-encryption \
  --region ${AWS_REGION}
```

#### Generate Finding

```bash
aws guardduty create-sample-findings \
  --detector-id ${DETECTOR_ID} \
  --finding-types 'Policy:S3/BucketEncryptionDisabled' \
  --region ${AWS_REGION}

sleep 120
```

#### Expected Response

1. **Auto-Remediation**:
   - Encryption re-enabled with AES256
   - Tagged with `GuardDutyFinding=Policy-EncryptionDisabled`
   - Tagged with `AutoRemediated=EncryptionEnabled`

2. **Alert**: Critical notification about encryption disabled

#### Verification

```bash
# Verify encryption is re-enabled
aws s3api get-bucket-encryption \
  --bucket ${TEST_BUCKET}-encryption \
  --region ${AWS_REGION}

# Expected output:
# {
#   "ServerSideEncryptionConfiguration": {
#     "Rules": [{
#       "ApplyServerSideEncryptionByDefault": {
#         "SSEAlgorithm": "AES256"
#       }
#     }]
#   }
# }
```

### Test 4: Policy - Versioning Disabled (Ransomware Indicator)

**GuardDuty Finding**: `Policy:S3/BucketVersioningDisabled`

#### Setup

```bash
# Create bucket with versioning
aws s3 mb s3://${TEST_BUCKET}-versioning --region ${AWS_REGION}

aws s3api put-bucket-versioning \
  --bucket ${TEST_BUCKET}-versioning \
  --versioning-configuration Status=Enabled \
  --region ${AWS_REGION}

# Suspend versioning (simulating ransomware preparation)
aws s3api put-bucket-versioning \
  --bucket ${TEST_BUCKET}-versioning \
  --versioning-configuration Status=Suspended \
  --region ${AWS_REGION}
```

#### Generate Finding

```bash
aws guardduty create-sample-findings \
  --detector-id ${DETECTOR_ID} \
  --finding-types 'Policy:S3/BucketVersioningDisabled' \
  --region ${AWS_REGION}

sleep 120
```

#### Expected Response

1. **Auto-Remediation**:
   - Versioning re-enabled
   - Tagged with `GuardDutyFinding=Policy-VersioningDisabled`
   - Tagged with `RansomwareIndicator=VersioningDisabled`

2. **Alert**: Critical ransomware indicator detected

#### Verification

```bash
# Verify versioning is re-enabled
aws s3api get-bucket-versioning \
  --bucket ${TEST_BUCKET}-versioning \
  --region ${AWS_REGION}

# Expected: "Status": "Enabled"
```

### Test 5: Policy - Public Access Granted

**GuardDuty Finding**: `Policy:S3/BucketPublicAccessGranted`

#### Setup

```bash
# Create private bucket
aws s3 mb s3://${TEST_BUCKET}-public --region ${AWS_REGION}

# Make bucket public (simulating attack)
aws s3api put-bucket-policy \
  --bucket ${TEST_BUCKET}-public \
  --policy '{
    "Version": "2012-10-17",
    "Statement": [{
      "Sid": "PublicReadAccess",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::'${TEST_BUCKET}'-public/*"
    }]
  }' \
  --region ${AWS_REGION}
```

#### Generate Finding

```bash
aws guardduty create-sample-findings \
  --detector-id ${DETECTOR_ID} \
  --finding-types 'Policy:S3/BucketPublicAccessGranted' \
  --region ${AWS_REGION}

sleep 120
```

#### Expected Response

1. **Auto-Remediation**:
   - Public access blocked
   - Bucket policy removed
   - Tagged with `GuardDutyFinding=Policy-PublicAccess`
   - Tagged with `ExfiltrationRisk=High`

2. **Alert**: Critical bucket made public

#### Verification

```bash
# Verify public access blocked
aws s3api get-public-access-block \
  --bucket ${TEST_BUCKET}-public \
  --region ${AWS_REGION}

# Verify policy removed
aws s3api get-bucket-policy \
  --bucket ${TEST_BUCKET}-public \
  --region ${AWS_REGION} 2>&1 | grep "NoSuchBucketPolicy" || echo "Policy still exists!"
```

### Test 6: UnauthorizedAccess - Malicious IP

**GuardDuty Finding**: `UnauthorizedAccess:S3/MaliciousIPCaller.Custom`

#### Setup

```bash
# Create test bucket
aws s3 mb s3://${TEST_BUCKET}-malicious --region ${AWS_REGION}
```

#### Generate Finding

```bash
aws guardduty create-sample-findings \
  --detector-id ${DETECTOR_ID} \
  --finding-types 'UnauthorizedAccess:S3/MaliciousIPCaller.Custom' \
  --region ${AWS_REGION}

sleep 120
```

#### Expected Response

1. **Auto-Remediation**:
   - Public access blocked
   - Tagged with `GuardDutyFinding=UnauthorizedAccess-Credentials`
   - Tagged with `CredentialCompromise=Suspected`

2. **Alert**: Critical credential compromise suspected
3. **Manual Action Required**: Review IAM credentials

#### Verification

```bash
# Check remediation
aws s3api get-public-access-block \
  --bucket ${TEST_BUCKET}-malicious \
  --region ${AWS_REGION}

# Check for active IAM sessions (manual review)
aws iam get-credential-report
```

## Monitoring and Verification

### Monitor Cloud Custodian Logs

```bash
# Get Lambda function name
LAMBDA_NAME=$(aws lambda list-functions \
  --query 'Functions[?starts_with(FunctionName, `cloud-custodian`)].FunctionName' \
  --output text)

# Tail logs
aws logs tail /aws/lambda/${LAMBDA_NAME} \
  --follow \
  --region ${AWS_REGION}
```

### Monitor GuardDuty Findings

```bash
# List all active S3 findings
aws guardduty list-findings \
  --detector-id ${DETECTOR_ID} \
  --finding-criteria '{
    "Criterion": {
      "service.archived": {
        "Eq": ["false"]
      },
      "type": {
        "Contains": ["S3"]
      }
    }
  }' \
  --region ${AWS_REGION}
```

### Check SNS Notifications

```bash
# Check SNS topic subscriptions
aws sns list-subscriptions-by-topic \
  --topic-arn arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:cloud-custodian-notifications-prod \
  --region ${AWS_REGION}

# Check SQS queue for mailer messages
aws sqs receive-message \
  --queue-url https://sqs.${AWS_REGION}.amazonaws.com/${AWS_ACCOUNT_ID}/cloud-custodian-mailer-queue-prod \
  --max-number-of-messages 10 \
  --region ${AWS_REGION}
```

## Integration Testing

### Test Complete Flow

```bash
#!/bin/bash
# test-guardduty-s3-complete.sh

set -e

echo "🧪 Starting GuardDuty S3 Protection Integration Test"

# Test 1: Exfiltration
echo "Test 1: Exfiltration Detection"
aws guardduty create-sample-findings \
  --detector-id ${DETECTOR_ID} \
  --finding-types 'Exfiltration:S3/AnomalousObjectDownload' \
  --region ${AWS_REGION}

# Test 2: Impact
echo "Test 2: Impact Detection"
aws guardduty create-sample-findings \
  --detector-id ${DETECTOR_ID} \
  --finding-types 'Impact:S3/PermissionsModification.Unusual' \
  --region ${AWS_REGION}

# Test 3: Policy
echo "Test 3: Policy Violation"
aws guardduty create-sample-findings \
  --detector-id ${DETECTOR_ID} \
  --finding-types 'Policy:S3/BucketEncryptionDisabled' \
  --region ${AWS_REGION}

echo "⏳ Waiting 2 minutes for GuardDuty to process..."
sleep 120

echo "📊 Checking findings..."
aws guardduty list-findings \
  --detector-id ${DETECTOR_ID} \
  --finding-criteria '{
    "Criterion": {
      "updatedAt": {
        "Gte": '$(date -u -d '5 minutes ago' +%s000)'
      }
    }
  }' \
  --region ${AWS_REGION}

echo "✅ Test complete. Check CloudWatch logs and SNS notifications."
```

## Cleanup

```bash
# Delete test buckets
for suffix in "" "-permissions" "-encryption" "-versioning" "-public" "-malicious"; do
  BUCKET="${TEST_BUCKET}${suffix}"
  if aws s3 ls s3://${BUCKET} 2>/dev/null; then
    echo "Deleting ${BUCKET}..."
    aws s3 rb s3://${BUCKET} --force --region ${AWS_REGION} || true
  fi
done

# Archive test findings (optional)
FINDING_IDS=$(aws guardduty list-findings \
  --detector-id ${DETECTOR_ID} \
  --finding-criteria '{
    "Criterion": {
      "type": {
        "Contains": ["S3"]
      }
    }
  }' \
  --query 'FindingIds' \
  --output text \
  --region ${AWS_REGION})

if [ -n "$FINDING_IDS" ]; then
  aws guardduty archive-findings \
    --detector-id ${DETECTOR_ID} \
    --finding-ids ${FINDING_IDS} \
    --region ${AWS_REGION}
fi

echo "✅ Cleanup complete"
```

## Troubleshooting

### Issue: Findings Not Generated

```bash
# Check GuardDuty is enabled
aws guardduty get-detector \
  --detector-id ${DETECTOR_ID} \
  --region ${AWS_REGION}

# Ensure Status is "ENABLED"
```

### Issue: Cloud Custodian Not Responding

```bash
# Check Lambda function exists
aws lambda list-functions \
  --query 'Functions[?contains(FunctionName, `custodian`)].FunctionName' \
  --region ${AWS_REGION}

# Check Lambda logs for errors
aws logs tail /aws/lambda/cloud-custodian-* --follow
```

### Issue: No Notifications Received

```bash
# Check SNS subscription confirmation
aws sns list-subscriptions \
  --region ${AWS_REGION} \
  | grep "ysrinu95@gmail.com"

# Check SQS queue has messages
aws sqs get-queue-attributes \
  --queue-url https://sqs.${AWS_REGION}.amazonaws.com/${AWS_ACCOUNT_ID}/cloud-custodian-mailer-queue-prod \
  --attribute-names ApproximateNumberOfMessages \
  --region ${AWS_REGION}
```

## Performance Metrics

### Expected Response Times

| Event | Expected Time | Actual |
|-------|--------------|--------|
| GuardDuty finding generated | Immediate | |
| Cloud Custodian triggered | 1-5 minutes | |
| Remediation applied | 1-2 minutes | |
| SNS notification sent | 1-3 minutes | |
| **Total incident response** | **3-10 minutes** | |

### Success Criteria

- ✅ All 12 GuardDuty S3 finding types handled
- ✅ Auto-remediation completes within 10 minutes
- ✅ Notifications received for all critical findings
- ✅ No false positives during testing
- ✅ Proper tagging applied to all affected buckets

## References

- [AWS GuardDuty S3 Protection](https://docs.aws.amazon.com/guardduty/latest/ug/s3-protection.html)
- [GuardDuty Finding Types](https://docs.aws.amazon.com/guardduty/latest/ug/guardduty_finding-types-s3.html)
- [Cloud Custodian S3 Filters](https://cloudcustodian.io/docs/aws/resources/s3.html)
- [Cloud Custodian Event Mode](https://cloudcustodian.io/docs/aws/lambda.html#cloudtrail-mode)
