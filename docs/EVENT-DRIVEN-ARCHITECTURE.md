# Event-Driven Cloud Custodian Architecture

## Overview

This architecture implements an event-driven Cloud Custodian solution that automatically responds to S3 API calls detected via CloudTrail. The Lambda function validates events, determines the appropriate policy to execute, and remediates security issues in real-time.

## Architecture Flow

```
1. User Action (e.g., Create S3 Bucket)
   ↓
2. CloudTrail logs API call
   ↓
3. EventBridge detects CloudTrail event (5-15 min delay)
   ↓
4. Lambda function triggered with event details
   ↓
5. Event Validator validates event and extracts information
   ↓
6. Policy Mapping determines which policy to execute
   ↓
7. Policy Executor downloads policy from S3
   ↓
8. Cloud Custodian executes specific policy
   ↓
9. Remediation actions taken (if not dry-run)
   ↓
10. Results logged to CloudWatch
```

## Components

### 1. Event Validator (`src/validator.py`)

**Purpose**: Validates EventBridge events and determines which Cloud Custodian policy should be executed.

**Key Functions**:
- `validate_event()` - Validates EventBridge event structure and extracts key information
- `get_policy_mapping()` - Looks up the appropriate policy mapping for the event type
- `get_policy_details()` - Returns complete policy execution details

**Event Information Extracted**:
- Event name (CreateBucket, PutBucketAcl, etc.)
- Bucket name
- AWS region
- Source IP address
- User agent
- Event timestamp

### 2. Policy Executor (`src/policy_executor.py`)

**Purpose**: Downloads policy files from S3 and executes specific Cloud Custodian policies.

**Key Functions**:
- `download_policy_file()` - Downloads policy YAML from S3
- `parse_policy_file()` - Parses YAML and validates structure
- `find_policy()` - Finds specific policy by name in the file
- `execute_policy()` - Executes the Cloud Custodian policy
- `download_policy_mapping()` - Downloads policy mapping configuration from S3

### 3. Lambda Handler (`src/lambda_native.py`)

**Purpose**: Main entry point that orchestrates event validation and policy execution.

**Environment Variables**:
- `POLICY_MAPPING_BUCKET` - S3 bucket containing policy mapping and policy files
- `POLICY_MAPPING_KEY` - S3 key for policy mapping JSON (default: `config/policy-mapping.json`)
- `DRYRUN` - Set to 'true' to run in dry-run mode (default: 'false')
- `AWS_REGION` - AWS region (automatically set by Lambda)

### 4. Policy Mapping Configuration (`config/policy-mapping.json`)

**Purpose**: Maps S3 CloudTrail events to specific Cloud Custodian policies.

**Structure**:
```json
{
  "version": "1.0",
  "s3_policy_bucket": "your-policies-bucket",
  "s3_policy_prefix": "custodian-policies/",
  "mappings": [
    {
      "event_type": "CreateBucket",
      "description": "S3 bucket creation",
      "policy_file": "s3-bucket-security.yml",
      "policy_name": "s3-bucket-public-access-check",
      "enabled": true,
      "priority": 1
    }
  ],
  "default_policy": {
    "policy_file": "s3-bucket-security.yml",
    "policy_name": "s3-bucket-default-check",
    "enabled": true
  }
}
```

**Fields**:
- `event_type` - CloudTrail event name (CreateBucket, PutBucketAcl, etc.)
- `policy_file` - YAML file containing Cloud Custodian policies
- `policy_name` - Specific policy name within the YAML file
- `enabled` - Whether this mapping is active
- `priority` - Execution priority (lower = higher priority)

### 5. Policy Files (`policies/s3-bucket-security.yml`)

**Purpose**: Contains Cloud Custodian policy definitions for S3 security.

**Example Policies**:
- `s3-bucket-public-access-check` - Check for public access on bucket creation
- `s3-bucket-acl-check` - Monitor ACL modifications
- `s3-bucket-policy-check` - Check bucket policy changes
- `s3-bucket-public-block-removed` - Alert when public access block is removed
- `s3-bucket-cors-check` - Monitor CORS configurations
- `s3-bucket-website-check` - Check static website hosting

## Setup Instructions

### Step 1: Create S3 Bucket for Policies

```bash
# Create S3 bucket for policy storage
aws s3 mb s3://your-policies-bucket

# Enable versioning (recommended)
aws s3api put-bucket-versioning \
  --bucket your-policies-bucket \
  --versioning-configuration Status=Enabled
```

### Step 2: Upload Policy Files to S3

```bash
# Upload policy mapping configuration
aws s3 cp config/policy-mapping.json s3://your-policies-bucket/config/

# Upload policy files
aws s3 cp policies/s3-bucket-security.yml s3://your-policies-bucket/custodian-policies/
```

### Step 3: Update Policy Mapping Configuration

Edit `config/policy-mapping.json` and update the S3 bucket name:

```json
{
  "s3_policy_bucket": "your-policies-bucket",
  "s3_policy_prefix": "custodian-policies/",
  ...
}
```

Then re-upload:

```bash
aws s3 cp config/policy-mapping.json s3://your-policies-bucket/config/
```

### Step 4: Configure Terraform Variables

Create or update `terraform/terraform.tfvars`:

```hcl
aws_region             = "us-east-1"
environment            = "dev"
project_name           = "cloud-custodian"
lambda_execution_mode  = "native"

# S3 bucket for policy storage
policy_bucket          = "your-policies-bucket"
policy_mapping_key     = "config/policy-mapping.json"

# Lambda configuration
lambda_timeout         = 300
lambda_memory_size     = 512
```

### Step 5: Deploy Infrastructure

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### Step 6: Verify CloudTrail is Enabled

```bash
# Check CloudTrail status
aws cloudtrail get-trail-status --name your-trail-name

# If not enabled, create and start CloudTrail
aws cloudtrail create-trail \
  --name cloud-custodian-trail \
  --s3-bucket-name your-cloudtrail-bucket

aws cloudtrail start-logging --name cloud-custodian-trail
```

## Testing

### Test 1: Create Public S3 Bucket

```bash
# Create a public bucket (will trigger Lambda)
aws s3api create-bucket \
  --bucket test-public-bucket-$(date +%s) \
  --region us-east-1

# Wait 5-15 minutes for CloudTrail event to propagate

# Check Lambda logs
aws logs tail /aws/lambda/cloud-custodian-executor-dev --follow
```

### Test 2: Modify Bucket ACL

```bash
# Make bucket public (will trigger Lambda)
aws s3api put-bucket-acl \
  --bucket test-public-bucket-1234567890 \
  --acl public-read

# Wait for EventBridge trigger and check logs
```

### Test 3: Manual Lambda Invocation with Sample Event

Create a test event file `test-event.json`:

```json
{
  "version": "0",
  "id": "test-event-123",
  "detail-type": "AWS API Call via CloudTrail",
  "source": "aws.s3",
  "region": "us-east-1",
  "detail": {
    "eventVersion": "1.08",
    "eventTime": "2025-11-10T10:00:00Z",
    "eventName": "CreateBucket",
    "eventSource": "s3.amazonaws.com",
    "requestParameters": {
      "bucketName": "test-bucket-123"
    },
    "responseElements": null,
    "sourceIPAddress": "203.0.113.0",
    "userAgent": "aws-cli/2.0"
  }
}
```

Invoke Lambda:

```bash
aws lambda invoke \
  --function-name cloud-custodian-executor-dev \
  --cli-binary-format raw-in-base64-out \
  --payload file://test-event.json \
  response.json

cat response.json
```

## Policy Mapping Examples

### Add New Event Mapping

To handle a new S3 event type, add a mapping to `policy-mapping.json`:

```json
{
  "event_type": "PutBucketLogging",
  "description": "S3 bucket logging configuration",
  "policy_file": "s3-bucket-security.yml",
  "policy_name": "s3-bucket-logging-check",
  "enabled": true,
  "priority": 2
}
```

Then create the corresponding policy in your policy file.

### Disable a Mapping

Set `enabled: false` in the mapping:

```json
{
  "event_type": "PutBucketCors",
  "enabled": false,
  ...
}
```

### Change Priority

Lower priority number = higher priority:

```json
{
  "event_type": "DeleteBucketPublicAccessBlock",
  "priority": 1  // Highest priority
},
{
  "event_type": "PutBucketCors",
  "priority": 2  // Lower priority
}
```

## Monitoring

### CloudWatch Logs

```bash
# View Lambda logs
aws logs tail /aws/lambda/cloud-custodian-executor-dev --follow

# Filter for specific event type
aws logs filter-log-events \
  --log-group-name /aws/lambda/cloud-custodian-executor-dev \
  --filter-pattern "CreateBucket"
```

### EventBridge Metrics

```bash
# Check rule invocations
aws cloudwatch get-metric-statistics \
  --namespace AWS/Events \
  --metric-name Invocations \
  --dimensions Name=RuleName,Value=cloud-custodian-s3-events-dev \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

## Troubleshooting

### Issue: Lambda not triggering

**Check CloudTrail**:
```bash
aws cloudtrail get-trail-status --name your-trail-name
```

**Check EventBridge rule**:
```bash
aws events describe-rule --name cloud-custodian-s3-events-dev
```

**Check Lambda permissions**:
```bash
aws lambda get-policy --function-name cloud-custodian-executor-dev
```

### Issue: Policy not found

**Check S3 bucket and files**:
```bash
aws s3 ls s3://your-policies-bucket/config/
aws s3 ls s3://your-policies-bucket/custodian-policies/
```

**Verify policy mapping**:
```bash
aws s3 cp s3://your-policies-bucket/config/policy-mapping.json - | python -m json.tool
```

### Issue: Permission denied

**Check IAM role**:
```bash
aws iam get-role --role-name cloud-custodian-lambda-role-dev
aws iam list-attached-role-policies --role-name cloud-custodian-lambda-role-dev
```

## Dry-Run Mode

To test policies without taking actions, set the `DRYRUN` environment variable:

```bash
# Update Lambda function
aws lambda update-function-configuration \
  --function-name cloud-custodian-executor-dev \
  --environment "Variables={POLICY_MAPPING_BUCKET=your-policies-bucket,POLICY_MAPPING_KEY=config/policy-mapping.json,DRYRUN=true}"
```

## Best Practices

1. **Test in Dry-Run**: Always test new policies with `DRYRUN=true` first
2. **Version Policy Files**: Use S3 versioning for policy files
3. **Monitor CloudWatch**: Set up CloudWatch alarms for Lambda errors
4. **Regular Audits**: Review policy mapping configuration regularly
5. **Security**: Use least-privilege IAM permissions
6. **Documentation**: Document custom policies and mappings
7. **Backup**: Keep backup copies of policy files
8. **Testing**: Test policy changes in dev environment first

## Supported S3 Events

The current configuration supports these CloudTrail events:

- `CreateBucket` - New bucket creation
- `PutBucketAcl` - ACL modifications
- `PutBucketPolicy` - Bucket policy changes
- `PutBucketPublicAccessBlock` - Public access block modifications
- `DeleteBucketPublicAccessBlock` - Public access block removal
- `PutBucketCors` - CORS configuration changes
- `PutBucketWebsite` - Static website hosting configuration

To add more events, update the EventBridge rule pattern in `terraform/eventbridge.tf` and add corresponding mappings in `policy-mapping.json`.

## Cost Considerations

- **CloudTrail**: Data events incur charges (~$0.10 per 100,000 events)
- **Lambda**: Charged per invocation and duration
- **S3**: Storage costs for policy files (minimal)
- **CloudWatch**: Log storage costs

**Estimated Monthly Cost** (for moderate usage):
- CloudTrail: $20-50
- Lambda: $5-20
- S3: <$1
- CloudWatch: $5-10

**Total**: ~$30-80/month

## Extending the Solution

### Add EC2 Event Handling

1. Update EventBridge rule to include EC2 events
2. Create EC2 policy file
3. Add EC2 event mappings to `policy-mapping.json`
4. Update validator to handle EC2 events

### Add SNS Notifications

1. Create SNS topic
2. Add SNS actions to policies
3. Update IAM permissions for SNS
4. Configure email subscriptions

### Multi-Region Support

1. Deploy Lambda in each region
2. Use separate policy mapping per region
3. Consolidate logs in central account

---

**Created**: November 10, 2025  
**Version**: 1.0  
**Author**: Cloud Custodian Team
