# Quick Setup Guide

## Step-by-Step Setup for Event-Driven Architecture

### 1. Create S3 Bucket for Policies

```powershell
# Set your bucket name
$BUCKET_NAME = "your-custodian-policies-bucket"
$REGION = "us-east-1"

# Create bucket
aws s3 mb s3://$BUCKET_NAME --region $REGION

# Enable versioning
aws s3api put-bucket-versioning `
  --bucket $BUCKET_NAME `
  --versioning-configuration Status=Enabled
```

### 2. Update Policy Mapping Configuration

Edit `config/policy-mapping.json` and update line 4:

```json
"s3_policy_bucket": "your-custodian-policies-bucket",
```

Replace with your actual bucket name.

### 3. Upload Files to S3

```powershell
# Upload policy mapping configuration
aws s3 cp config/policy-mapping.json s3://$BUCKET_NAME/config/policy-mapping.json

# Upload S3 security policies
aws s3 cp policies/s3-bucket-security.yml s3://$BUCKET_NAME/custodian-policies/s3-bucket-security.yml

# Verify uploads
aws s3 ls s3://$BUCKET_NAME/config/
aws s3 ls s3://$BUCKET_NAME/custodian-policies/
```

### 4. Configure Terraform

Edit `terraform/terraform.tfvars`:

```hcl
aws_region             = "us-east-1"
environment            = "dev"
project_name           = "cloud-custodian"
lambda_execution_mode  = "native"

# IMPORTANT: Update this with your bucket name
policy_bucket          = "your-custodian-policies-bucket"
policy_mapping_key     = "config/policy-mapping.json"

lambda_timeout         = 300
lambda_memory_size     = 512
log_retention_days     = 7

tags = {
  Project     = "CloudCustodian"
  Environment = "dev"
  ManagedBy   = "Terraform"
}
```

### 5. Deploy Infrastructure

```powershell
cd terraform

# Initialize Terraform
terraform init

# Review changes
terraform plan

# Deploy
terraform apply -auto-approve
```

### 6. Verify CloudTrail

```powershell
# List CloudTrail trails
aws cloudtrail list-trails

# Check status of a trail
aws cloudtrail get-trail-status --name <trail-name>

# If no trail exists, create one
$TRAIL_BUCKET = "your-cloudtrail-bucket"
aws s3 mb s3://$TRAIL_BUCKET --region us-east-1

aws cloudtrail create-trail `
  --name cloud-custodian-trail `
  --s3-bucket-name $TRAIL_BUCKET

aws cloudtrail start-logging --name cloud-custodian-trail
```

### 7. Test the Setup

Create a test S3 bucket to trigger the Lambda:

```powershell
# Create a public bucket (this will trigger Lambda after 5-15 minutes)
$TEST_BUCKET = "test-public-bucket-$(Get-Date -Format 'yyyyMMddHHmmss')"
aws s3api create-bucket --bucket $TEST_BUCKET --region us-east-1

# Make it public (will trigger remediation)
aws s3api put-bucket-acl --bucket $TEST_BUCKET --acl public-read

# Wait 5-15 minutes for CloudTrail event to propagate to EventBridge

# Check Lambda logs
aws logs tail /aws/lambda/cloud-custodian-executor-dev --follow

# Check if remediation happened
aws s3api get-public-access-block --bucket $TEST_BUCKET

# Cleanup test bucket
aws s3 rb s3://$TEST_BUCKET --force
```

### 8. Manual Lambda Test (Optional)

Create `test-event.json`:

```json
{
  "version": "0",
  "id": "test-123",
  "detail-type": "AWS API Call via CloudTrail",
  "source": "aws.s3",
  "region": "us-east-1",
  "detail": {
    "eventVersion": "1.08",
    "eventTime": "2025-11-10T10:00:00Z",
    "eventName": "CreateBucket",
    "eventSource": "s3.amazonaws.com",
    "requestParameters": {
      "bucketName": "test-bucket-manual"
    },
    "sourceIPAddress": "203.0.113.0",
    "userAgent": "aws-cli/2.0"
  }
}
```

Invoke Lambda directly:

```powershell
aws lambda invoke `
  --function-name cloud-custodian-executor-dev `
  --cli-binary-format raw-in-base64-out `
  --payload file://test-event.json `
  response.json

Get-Content response.json | ConvertFrom-Json | ConvertTo-Json -Depth 10
```

## Troubleshooting

### Lambda Not Triggering

1. **Check EventBridge Rule**:
```powershell
aws events describe-rule --name cloud-custodian-s3-events-dev
```

2. **Check Lambda Permissions**:
```powershell
aws lambda get-policy --function-name cloud-custodian-executor-dev
```

3. **Check CloudTrail Status**:
```powershell
aws cloudtrail get-trail-status --name your-trail-name
```

### Policy Not Found Error

1. **Verify S3 Files**:
```powershell
aws s3 ls s3://$BUCKET_NAME/config/
aws s3 ls s3://$BUCKET_NAME/custodian-policies/
```

2. **Check Policy Mapping**:
```powershell
aws s3 cp s3://$BUCKET_NAME/config/policy-mapping.json - | ConvertFrom-Json | ConvertTo-Json -Depth 10
```

3. **Verify Lambda Environment Variables**:
```powershell
aws lambda get-function-configuration --function-name cloud-custodian-executor-dev --query 'Environment.Variables'
```

## Enable Dry-Run Mode

To test without taking actions:

```powershell
aws lambda update-function-configuration `
  --function-name cloud-custodian-executor-dev `
  --environment "Variables={POLICY_MAPPING_BUCKET=$BUCKET_NAME,POLICY_MAPPING_KEY=config/policy-mapping.json,DRYRUN=true,LOG_GROUP=/aws/lambda/cloud-custodian-executor-dev,ENVIRONMENT=dev}"
```

To disable dry-run:

```powershell
aws lambda update-function-configuration `
  --function-name cloud-custodian-executor-dev `
  --environment "Variables={POLICY_MAPPING_BUCKET=$BUCKET_NAME,POLICY_MAPPING_KEY=config/policy-mapping.json,DRYRUN=false,LOG_GROUP=/aws/lambda/cloud-custodian-executor-dev,ENVIRONMENT=dev}"
```

## Monitoring

### View Lambda Logs

```powershell
# Tail logs in real-time
aws logs tail /aws/lambda/cloud-custodian-executor-dev --follow

# Search for specific event
aws logs filter-log-events `
  --log-group-name /aws/lambda/cloud-custodian-executor-dev `
  --filter-pattern "CreateBucket" `
  --max-items 10
```

### Check EventBridge Metrics

```powershell
$START_TIME = (Get-Date).AddHours(-1).ToString("yyyy-MM-ddTHH:mm:ss")
$END_TIME = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")

aws cloudwatch get-metric-statistics `
  --namespace AWS/Events `
  --metric-name Invocations `
  --dimensions Name=RuleName,Value=cloud-custodian-s3-events-dev `
  --start-time $START_TIME `
  --end-time $END_TIME `
  --period 300 `
  --statistics Sum
```

## Next Steps

1. **Customize Policies**: Edit `policies/s3-bucket-security.yml` to match your requirements
2. **Add SNS Notifications**: Configure SNS topics and update policies with notify actions
3. **Test in Dev**: Thoroughly test all scenarios in development environment
4. **Monitor Costs**: Set up AWS Budgets to monitor CloudTrail and Lambda costs
5. **Documentation**: Document any custom policies or mappings you create

## Important Notes

- CloudTrail events take **5-15 minutes** to propagate to EventBridge
- Always test with **DRYRUN=true** first
- Keep policy files under version control in S3
- Monitor CloudWatch logs for errors
- Use separate buckets for dev/prod environments

---

**For detailed information, see**: `docs/EVENT-DRIVEN-ARCHITECTURE.md`
