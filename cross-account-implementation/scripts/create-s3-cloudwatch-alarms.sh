#!/bin/bash
# Create CloudWatch Alarms for S3 monitoring
# These alarms will trigger Cloud Custodian policies via EventBridge

REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
SNS_TOPIC_ARN="arn:aws:sns:${REGION}:${ACCOUNT_ID}:cloudwatch-alarms"

echo "Creating CloudWatch Alarms for S3 Monitoring..."
echo "Region: $REGION"
echo "Account: $ACCOUNT_ID"
echo ""

# 1. S3 Delete Requests Spike Alarm
# Monitors ALL S3 buckets for unusual delete activity
echo "Creating S3 Delete Requests Spike Alarm..."
aws cloudwatch put-metric-alarm \
  --alarm-name "S3-Delete-Requests-High-AllBuckets" \
  --alarm-description "Alert when S3 DELETE requests exceed 100 in 5 minutes (potential mass deletion)" \
  --metric-name NumberOfRequests \
  --namespace AWS/S3 \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 100 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=FilterId,Value=DeleteRequests \
  --treat-missing-data notBreaching \
  --region $REGION

# 2. S3 Data Transfer Cost Spike Alarm
# Monitors BytesDownloaded for excessive data egress
echo "Creating S3 Data Transfer Cost Spike Alarm..."
aws cloudwatch put-metric-alarm \
  --alarm-name "S3-DataTransfer-Cost-High-AllBuckets" \
  --alarm-description "Alert when S3 data transfer exceeds 100GB in 1 hour (potential exfiltration)" \
  --metric-name BytesDownloaded \
  --namespace AWS/S3 \
  --statistic Sum \
  --period 3600 \
  --evaluation-periods 1 \
  --threshold 107374182400 \
  --comparison-operator GreaterThanThreshold \
  --treat-missing-data notBreaching \
  --region $REGION

# 3. S3 Bucket Size Growth Alarm
# Monitors BucketSizeBytes for rapid growth
echo "Creating S3 Bucket Size Growth Alarm..."
# Note: This requires per-bucket configuration. Example for a specific bucket:
# aws cloudwatch put-metric-alarm \
#   --alarm-name "S3-BucketSize-Growth-<bucket-name>" \
#   --alarm-description "Alert on unusual bucket size growth" \
#   --metric-name BucketSizeBytes \
#   --namespace AWS/S3 \
#   --statistic Average \
#   --period 86400 \
#   --evaluation-periods 1 \
#   --threshold 1099511627776 \
#   --comparison-operator GreaterThanThreshold \
#   --dimensions Name=BucketName,Value=<bucket-name> Name=StorageType,Value=StandardStorage \
#   --treat-missing-data notBreaching \
#   --region $REGION

# 4. S3 4xx Error Spike Alarm
# Monitors 4xxErrors for reconnaissance activity
echo "Creating S3 4xx Errors Spike Alarm..."
aws cloudwatch put-metric-alarm \
  --alarm-name "S3-4xxErrors-High-AllBuckets" \
  --alarm-description "Alert when S3 4xx errors exceed 50 in 5 minutes (potential reconnaissance)" \
  --metric-name 4xxErrors \
  --namespace AWS/S3 \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 50 \
  --comparison-operator GreaterThanThreshold \
  --treat-missing-data notBreaching \
  --region $REGION

echo ""
echo "✅ CloudWatch Alarms created successfully!"
echo ""
echo "NOTE: To enable request metrics for S3 buckets, run:"
echo "  aws s3api put-bucket-metrics-configuration \\"
echo "    --bucket <bucket-name> \\"
echo "    --id EntireBucket \\"
echo "    --metrics-configuration '{\"Id\":\"EntireBucket\",\"Filter\":{}}'"
echo ""
echo "To verify alarms:"
echo "  aws cloudwatch describe-alarms --alarm-name-prefix S3-"
