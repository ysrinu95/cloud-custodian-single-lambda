#!/bin/bash
# ============================================================================
# Enable AWS CloudTrail, Config, and Security Hub - Member Account
# ============================================================================

# Set variables
PROFILE="member-account"
REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --profile ${PROFILE} --query Account --output text)
TRAIL_NAME="aikyam-cloud-custodian-trail"
S3_BUCKET_NAME="aikyam-cloudtrail-${ACCOUNT_ID}"
CONFIG_RECORDER_NAME="aikyam-config-recorder"
CONFIG_ROLE_NAME="aikyam-config-role"
DELIVERY_CHANNEL_NAME="aikyam-config-delivery"

echo "Using AWS Profile: ${PROFILE}"
echo "Current Account ID: ${ACCOUNT_ID}"
echo "Region: ${REGION}"
echo ""

# ============================================================================
# 1. Enable AWS CloudTrail
# ============================================================================
echo "==> Step 1: Setting up AWS CloudTrail..."

# Create S3 bucket for CloudTrail logs
echo "Creating S3 bucket for CloudTrail..."
aws s3api --profile member-account create-bucket \
  --bucket ${S3_BUCKET_NAME} \
  --region ${REGION} 2>/dev/null || echo "Bucket already exists"

# Apply bucket policy for CloudTrail
cat > /tmp/cloudtrail-bucket-policy.json << POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AWSCloudTrailAclCheck",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudtrail.amazonaws.com"
      },
      "Action": "s3:GetBucketAcl",
      "Resource": "arn:aws:s3:::${S3_BUCKET_NAME}"
    },
    {
      "Sid": "AWSCloudTrailWrite",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudtrail.amazonaws.com"
      },
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::${S3_BUCKET_NAME}/AWSLogs/${ACCOUNT_ID}/*",
      "Condition": {
        "StringEquals": {
          "s3:x-amz-acl": "bucket-owner-full-control"
        }
      }
    }
  ]
}
POLICY

aws s3api --profile member-account put-bucket-policy \
  --bucket ${S3_BUCKET_NAME} \
  --policy file:///tmp/cloudtrail-bucket-policy.json

# Enable bucket encryption
aws s3api --profile member-account put-bucket-encryption \
  --bucket ${S3_BUCKET_NAME} \
  --server-side-encryption-configuration '{
    "Rules": [
      {
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        }
      }
    ]
  }'

# Create CloudTrail
echo "Creating CloudTrail..."
aws cloudtrail --profile member-account create-trail \
  --name ${TRAIL_NAME} \
  --s3-bucket-name ${S3_BUCKET_NAME} \
  --include-global-service-events \
  --is-multi-region-trail \
  --enable-log-file-validation \
  --region ${REGION} 2>/dev/null || echo "Trail already exists"

# Start logging
aws cloudtrail --profile member-account start-logging \
  --name ${TRAIL_NAME} \
  --region ${REGION}

# Enable CloudTrail Insights (optional - detects unusual API activity)
aws cloudtrail --profile member-account put-insight-selectors \
  --trail-name ${TRAIL_NAME} \
  --insight-selectors '[{"InsightType": "ApiCallRateInsight"}]' \
  --region ${REGION} 2>/dev/null || echo "Insights optional - skipping if not supported"

echo "✓ CloudTrail enabled: ${TRAIL_NAME}"
echo ""

# ============================================================================
# 2. Enable AWS Config
# ============================================================================
echo "==> Step 2: Setting up AWS Config..."

# Create IAM role for Config
echo "Creating IAM role for AWS Config..."
cat > /tmp/config-trust-policy.json << TRUST
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "config.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
TRUST

aws iam --profile member-account create-role \
  --role-name ${CONFIG_ROLE_NAME} \
  --assume-role-policy-document file:///tmp/config-trust-policy.json \
  --description "Role for AWS Config service" 2>/dev/null || echo "Role already exists"

# Attach AWS managed policy for Config
aws iam --profile member-account attach-role-policy \
  --role-name ${CONFIG_ROLE_NAME} \
  --policy-arn arn:aws:iam::aws:policy/service-role/ConfigRole 2>/dev/null

# Create inline policy for S3 access
cat > /tmp/config-s3-policy.json << S3POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetBucketVersioning",
        "s3:PutObject",
        "s3:GetObject"
      ],
      "Resource": [
        "arn:aws:s3:::${S3_BUCKET_NAME}",
        "arn:aws:s3:::${S3_BUCKET_NAME}/*"
      ]
    }
  ]
}
S3POLICY

aws iam --profile member-account put-role-policy \
  --role-name ${CONFIG_ROLE_NAME} \
  --policy-name ConfigS3Access \
  --policy-document file:///tmp/config-s3-policy.json 2>/dev/null

# Wait for role to propagate
echo "Waiting for IAM role to propagate..."
sleep 10

# Create Configuration Recorder
echo "Creating AWS Config recorder..."
aws configservice --profile member-account put-configuration-recorder \
  --configuration-recorder name=${CONFIG_RECORDER_NAME},roleARN=arn:aws:iam::${ACCOUNT_ID}:role/${CONFIG_ROLE_NAME} \
  --recording-group allSupported=true,includeGlobalResourceTypes=true \
  --region ${REGION}

# Create Delivery Channel
echo "Creating AWS Config delivery channel..."
aws configservice --profile member-account put-delivery-channel \
  --delivery-channel name=${DELIVERY_CHANNEL_NAME},s3BucketName=${S3_BUCKET_NAME},configSnapshotDeliveryProperties={deliveryFrequency=TwentyFour_Hours} \
  --region ${REGION}

# Start Configuration Recorder
echo "Starting AWS Config recorder..."
aws configservice --profile member-account start-configuration-recorder \
  --configuration-recorder-name ${CONFIG_RECORDER_NAME} \
  --region ${REGION}

echo "✓ AWS Config enabled: ${CONFIG_RECORDER_NAME}"
echo ""

# ============================================================================
# 3. Enable AWS Security Hub
# ============================================================================
echo "==> Step 3: Setting up AWS Security Hub..."

# Enable Security Hub
echo "Enabling AWS Security Hub..."
aws securityhub --profile member-account enable-security-hub \
  --enable-default-standards \
  --region ${REGION} 2>/dev/null || echo "Security Hub already enabled"

# Enable AWS Foundational Security Best Practices standard
aws securityhub --profile member-account batch-enable-standards \
  --standards-subscription-requests '[
    {
      "StandardsArn": "arn:aws:securityhub:'${REGION}'::standards/aws-foundational-security-best-practices/v/1.0.0"
    },
    {
      "StandardsArn": "arn:aws:securityhub:'${REGION}'::standards/cis-aws-foundations-benchmark/v/1.2.0"
    }
  ]' \
  --region ${REGION} 2>/dev/null || echo "Standards already enabled"

# Enable product integrations
echo "Enabling Security Hub product integrations..."

# Enable AWS Config integration
aws securityhub --profile member-account enable-import-findings-for-product \
  --product-arn arn:aws:securityhub:${REGION}::product/aws/config \
  --region ${REGION} 2>/dev/null || echo "Config integration already enabled"

# Enable GuardDuty integration
aws securityhub --profile member-account enable-import-findings-for-product \
  --product-arn arn:aws:securityhub:${REGION}::product/aws/guardduty \
  --region ${REGION} 2>/dev/null || echo "GuardDuty integration already enabled"

# Enable IAM Access Analyzer integration
aws securityhub --profile member-account enable-import-findings-for-product \
  --product-arn arn:aws:securityhub:${REGION}::product/aws/access-analyzer \
  --region ${REGION} 2>/dev/null || echo "IAM Access Analyzer integration already enabled"

echo "✓ Security Hub enabled with standards"
echo ""

# ============================================================================
# Verification
# ============================================================================
echo "==> Verifying Services..."
echo ""

echo "CloudTrail Status:"
aws cloudtrail --profile member-account get-trail-status --name ${TRAIL_NAME} --region ${REGION} --query 'IsLogging' --output text

echo ""
echo "AWS Config Status:"
aws configservice --profile member-account describe-configuration-recorder-status --region ${REGION} --query 'ConfigurationRecordersStatus[0].recording' --output text

echo ""
echo "Security Hub Status:"
aws securityhub --profile member-account describe-hub --region ${REGION} --query 'HubArn' --output text 2>/dev/null || echo "Not enabled"

echo ""
echo "==> All services enabled successfully!"
echo ""
echo "Next steps:"
echo "1. Verify CloudTrail is logging: aws cloudtrail --profile member-account lookup-events --max-results 5"
echo "2. Check Config compliance: aws configservice --profile member-account describe-compliance-by-config-rule"
echo "3. Review Security Hub findings: aws securityhub --profile member-account get-findings --max-items 10"
echo ""
echo "Clean up temp files..."
rm -f /tmp/cloudtrail-bucket-policy.json /tmp/config-trust-policy.json /tmp/config-s3-policy.json
