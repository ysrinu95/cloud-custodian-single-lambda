# Event Context Usage in Cloud Custodian Policies

## Overview

The Lambda function now passes the complete CloudTrail event data to Cloud Custodian policies. This allows policies to access event details such as user identity, event name, request parameters, and more.

## How It Works

1. **Lambda receives EventBridge event** containing CloudTrail data
2. **Validator extracts and stores** the complete raw event in `event_info['raw_event']`
3. **Policy executor passes event context** to Cloud Custodian by setting `policy.data['event']` to the CloudTrail event detail
4. **Policies can access event data** using the format `{event.fieldName}`

## Available Event Data

The event context contains all CloudTrail event fields from the `detail` section:

```json
{
  "eventVersion": "1.08",
  "userIdentity": {
    "type": "IAMUser",
    "principalId": "AIDAI...",
    "arn": "arn:aws:iam::123456789012:user/alice",
    "accountId": "123456789012",
    "userName": "alice"
  },
  "eventTime": "2025-11-13T12:34:56Z",
  "eventSource": "s3.amazonaws.com",
  "eventName": "CreateBucket",
  "awsRegion": "us-east-1",
  "sourceIPAddress": "203.0.113.1",
  "userAgent": "aws-cli/2.0.0",
  "requestParameters": {
    "bucketName": "my-new-bucket"
  },
  "responseElements": {
    "location": "/my-new-bucket"
  },
  "requestID": "ABC123...",
  "eventID": "DEF456...",
  "eventType": "AwsApiCall"
}
```

## Usage Examples

### Example 1: Auto-Tag with Creator Information

```yaml
policies:
- name: s3-auto-tag-creator
  resource: aws.s3
  description: 'Auto-tags S3 buckets with creator information'
  actions:
  - type: tag
    tags:
      CreatedBy: '{event.userIdentity.userName}'
      CreatedByArn: '{event.userIdentity.arn}'
      CreatedDate: '{now:%Y-%m-%d}'
      CreatedViaEvent: '{event.eventName}'
      SourceIP: '{event.sourceIPAddress}'
```

**Resulting tags:**
- `CreatedBy: alice`
- `CreatedByArn: arn:aws:iam::123456789012:user/alice`
- `CreatedDate: 2025-11-13`
- `CreatedViaEvent: CreateBucket`
- `SourceIP: 203.0.113.1`

### Example 2: IAM User Auto-Tagging

```yaml
policies:
- name: iam-user-auto-tag
  resource: aws.iam-user
  description: 'Auto-tags new IAM users with creator info'
  actions:
  - type: tag
    tags:
      CreatedBy: '{event.userIdentity.principalId}'
      CreatedByArn: '{event.userIdentity.arn}'
      CreatedDate: '{now:%Y-%m-%d}'
      CreatedViaEvent: CreateUser
```

### Example 3: EC2 Instance Tagging

```yaml
policies:
- name: ec2-auto-tag-creator
  resource: aws.ec2
  description: 'Auto-tags EC2 instances with launch information'
  actions:
  - type: tag
    tags:
      LaunchedBy: '{event.userIdentity.userName}'
      LaunchedByArn: '{event.userIdentity.arn}'
      LaunchDate: '{now:%Y-%m-%d}'
      LaunchTime: '{now:%H:%M:%S}'
      LaunchEvent: '{event.eventName}'
      SourceIP: '{event.sourceIPAddress}'
```

### Example 4: Security Hub Finding with Event Details

```yaml
policies:
- name: s3-public-bucket-detection
  resource: aws.s3
  description: 'Detects and reports public S3 buckets'
  filters:
  - type: check-public-block
    BlockPublicAcls: false
  actions:
  - type: post-finding
    severity_label: HIGH
    compliance_status: FAILED
    title: 'S3 Bucket Made Public'
    description: 'S3 bucket was made public by {event.userIdentity.userName} at {event.eventTime}'
    recommendation: 'Review bucket access and re-enable public access block'
    types:
    - Software and Configuration Checks/AWS Security Best Practices
```

### Example 5: Email Notification with Event Context

```yaml
policies:
- name: s3-encryption-disabled-alert
  resource: aws.s3
  description: 'Alerts when S3 encryption is disabled'
  filters:
  - type: bucket-encryption
    state: false
  actions:
  - type: notify
    template: aws-basic_email.html
    subject: '[ALERT] S3 Encryption Disabled by {event.userIdentity.userName}'
    violation_desc: 'S3 bucket encryption was disabled'
    action_desc: 'Event: {event.eventName} | User: {event.userIdentity.userName} | Source IP: {event.sourceIPAddress} | Time: {event.eventTime}'
    to:
    - security@example.com
    transport:
      type: sqs
      queue: https://sqs.us-east-1.amazonaws.com/172327596604/custodian-mailer-queue
```

## Event Field Reference

### Common Event Fields

| Field Path | Description | Example |
|------------|-------------|---------|
| `event.eventName` | API action performed | `CreateBucket`, `RunInstances` |
| `event.eventTime` | When the event occurred | `2025-11-13T12:34:56Z` |
| `event.eventSource` | AWS service | `s3.amazonaws.com`, `ec2.amazonaws.com` |
| `event.awsRegion` | AWS region | `us-east-1` |
| `event.sourceIPAddress` | Source IP address | `203.0.113.1` |
| `event.userAgent` | User agent string | `aws-cli/2.0.0` |

### User Identity Fields

| Field Path | Description | Example |
|------------|-------------|---------|
| `event.userIdentity.type` | Identity type | `IAMUser`, `AssumedRole`, `Root` |
| `event.userIdentity.userName` | IAM user name | `alice` |
| `event.userIdentity.principalId` | Principal ID | `AIDAI...` |
| `event.userIdentity.arn` | User ARN | `arn:aws:iam::123456789012:user/alice` |
| `event.userIdentity.accountId` | AWS account ID | `123456789012` |
| `event.userIdentity.sessionContext.sessionIssuer.userName` | Role name (for assumed roles) | `MyRole` |

### Request/Response Fields

| Field Path | Description |
|------------|-------------|
| `event.requestParameters.*` | API request parameters (varies by API) |
| `event.responseElements.*` | API response data (varies by API) |

### Service-Specific Examples

**S3 Events:**
- `event.requestParameters.bucketName` - Bucket name
- `event.requestParameters.key` - Object key
- `event.requestParameters.acl` - ACL setting

**EC2 Events:**
- `event.responseElements.instancesSet.items[0].instanceId` - Instance ID
- `event.requestParameters.instanceType` - Instance type

**IAM Events:**
- `event.requestParameters.userName` - IAM user name
- `event.requestParameters.policyName` - Policy name

## Resource Filtering

The Lambda function automatically adds resource filters based on the event:

### S3 Resources
Filtered by bucket name from the event:
```yaml
filters:
- type: value
  key: Name
  value: 'my-bucket'  # Extracted from event
```

### EC2 Resources
Filtered by instance ID from the event:
```yaml
filters:
- type: value
  key: InstanceId
  value: 'i-1234567890abcdef0'  # Extracted from event
```

### IAM Users
Filtered by username from the event:
```yaml
filters:
- type: value
  key: UserName
  value: 'alice'  # Extracted from event
```

### Security Groups
Filtered by group ID from the event:
```yaml
filters:
- type: value
  key: GroupId
  value: 'sg-1234567890abcdef0'  # Extracted from event
```

## Best Practices

1. **Always validate event data exists** - Use default values when accessing event fields
2. **Use appropriate field paths** - Refer to CloudTrail documentation for your service
3. **Test with real events** - Use actual CloudTrail events to test your policies
4. **Log event context** - The Lambda logs show when event context is provided
5. **Handle missing fields gracefully** - Not all events have all fields

## Debugging

The Lambda function logs when event context is provided:

```
INFO: Passing CloudTrail event context to policy
DEBUG: Event context: {...full event detail...}
```

Check CloudWatch Logs to verify event data is being passed correctly.

## Supported Services

Currently validated for:
- ✅ S3 (s3.amazonaws.com)
- ✅ EC2 (ec2.amazonaws.com)
- ✅ IAM (iam.amazonaws.com)
- ✅ Security Hub (securityhub.amazonaws.com)
- ✅ GuardDuty (guardduty.amazonaws.com)

Other AWS services will work but may not have automatic resource filtering.
