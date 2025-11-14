# Event-Driven Cloud Custodian Policies

This directory contains Cloud Custodian policies designed for **event-driven execution** via Lambda, without using Cloud Custodian's built-in `mode` (cloudtrail/periodic).

## How It Works

1. **EventBridge** captures CloudTrail API calls (e.g., `CreateBucket`, `RunInstances`)
2. **Lambda** receives the event, validates it, and extracts resource IDs
3. **Policy Executor** passes the resource ID to Cloud Custodian
4. **Cloud Custodian** runs the policy with `filters` and `actions` on the specific resource

## Policy Structure

Each policy contains **only**:
- `name`: Policy identifier
- `resource`: AWS resource type (e.g., `aws.s3`, `aws.ec2`)
- `description`: What the policy does
- `filters`: (optional) Conditions to check before taking action
- `actions`: Remediation or tagging actions to perform

**No `mode` section** - The Lambda handles event-driven triggering.

## Available Policies

### S3 Policies

#### `s3-public-bucket-event.yml`
- **Trigger**: `PutBucketAcl`, `DeleteBucketPublicAccessBlock`, `PutBucketPolicy`
- **Action**: Blocks all public access settings
- **Use Case**: Automatically remediate public S3 buckets

#### `s3-encryption-event.yml`
- **Trigger**: `DeleteBucketEncryption`, `CreateBucket`
- **Action**: Enables AES256 encryption
- **Use Case**: Ensure all buckets are encrypted

#### `s3-auto-tag-event.yml`
- **Trigger**: `CreateBucket`
- **Action**: Auto-tag with creator information
- **Use Case**: Track who created each bucket

### EC2 Policies

#### `ec2-public-instance-event.yml`
- **Trigger**: `RunInstances`
- **Action**: Stop instances with public IPs
- **Use Case**: Prevent instances from being launched in public subnets

#### `ec2-security-group-event.yml`
- **Trigger**: `CreateSecurityGroup`, `AuthorizeSecurityGroupIngress`
- **Action**: Remove unrestricted SSH rules (0.0.0.0/0:22)
- **Use Case**: Block unrestricted SSH access

#### `ec2-auto-tag-event.yml`
- **Trigger**: `RunInstances`
- **Action**: Auto-tag with creator information
- **Use Case**: Track who launched each instance

### IAM Policies

#### `iam-user-created-event.yml`
- **Trigger**: `CreateUser`
- **Action**: Auto-tag with creator metadata
- **Use Case**: Track IAM user creation

#### `iam-policy-admin-access-event.yml`
- **Trigger**: `CreatePolicy`, `CreatePolicyVersion`
- **Action**: Tag and alert on admin access policies
- **Use Case**: Detect overly permissive IAM policies

## How Lambda Passes Event Data

The `policy_executor.py` module:

1. **Extracts resource ID** from CloudTrail event:
   ```python
   # For S3 CreateBucket
   bucket_name = event['detail']['requestParameters']['bucketName']
   
   # For EC2 RunInstances
   instance_id = event['detail']['responseElements']['instancesSet']['items'][0]['instanceId']
   ```

2. **Filters resources** by ID before running policy:
   ```python
   # Add filter to target specific resource
   policy['filters'].insert(0, {
       'type': 'value',
       'key': 'Name',  # or 'InstanceId', etc.
       'value': resource_id
   })
   ```

3. **Executes policy** using c7n library:
   ```python
   from c7n.policy import PolicyCollection
   
   collection = PolicyCollection.from_data(policy_config, options)
   for policy in collection:
       resources = policy.run()
   ```

## Benefits Over Periodic/CloudTrail Mode

✅ **Instant execution** - No Cloud Custodian deployment required  
✅ **Single Lambda** - One function handles all events  
✅ **Simplified policies** - Just filters and actions  
✅ **Dynamic policy loading** - Policies stored in S3  
✅ **Event context** - Full CloudTrail event data available  
✅ **Cost effective** - Lambda only runs on specific events  

## Example: S3 Public Bucket Remediation

### CloudTrail Event
```json
{
  "detail-type": "AWS API Call via CloudTrail",
  "source": "aws.s3",
  "detail": {
    "eventName": "PutBucketAcl",
    "requestParameters": {
      "bucketName": "my-test-bucket"
    }
  }
}
```

### Lambda Processing
```python
# 1. Extract bucket name
bucket_name = "my-test-bucket"

# 2. Load policy: s3-public-bucket-event.yml
# 3. Add filter for specific bucket
# 4. Run policy - blocks public access on my-test-bucket
```

### Policy Execution
```yaml
policies:
  - name: s3-public-bucket-remediation-event
    resource: aws.s3
    filters:
      - type: check-public-block
        BlockPublicAcls: false
    actions:
      - type: set-public-block
        BlockPublicAcls: true
        # ... all public access blocked
```

## Configuration

Update `config/policy-mapping.json` to map events to these policies:

```json
{
  "event_mapping": {
    "PutBucketAcl": [
      {
        "policy_name": "s3-public-bucket-remediation-event",
        "source_file": "s3-public-bucket-event.yml",
        "description": "Block public access on S3 buckets"
      }
    ]
  }
}
```

## Testing

Trigger an event and check CloudWatch Logs:

```bash
# Create a test bucket (triggers CreateBucket event)
aws s3 mb s3://test-bucket-12345

# Check Lambda logs
aws logs tail /aws/lambda/cloud-custodian-executor-dev --follow
```

## Notes

- Policies run on **specific resources** identified from CloudTrail events
- CloudTrail must be enabled and sending events to EventBridge
- Lambda must have IAM permissions to perform policy actions
- All policies support dry-run mode via `DRYRUN` environment variable
