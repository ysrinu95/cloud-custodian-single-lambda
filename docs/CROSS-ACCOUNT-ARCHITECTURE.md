# Cross-Account Cloud Custodian Architecture

## Problem Statement

**Challenge**: Multiple AWS member accounts without Organization-level CloudTrail or centralized Security Hub access. Need to remediate resources across all member accounts from a single centralized security account.

**Requirements**:
- ✅ Single deployment in central security account
- ✅ Execute policies across multiple member accounts
- ✅ No infrastructure deployment in each member account
- ✅ Centralized event aggregation and policy execution
- ✅ Cross-account IAM role assumption for remediation

---

## Architecture Overview

```
┌────────────────────────────────────────────────────────────────────────────┐
│                          MEMBER ACCOUNT 1 (111111111111)                    │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────┐      ┌──────────────┐      ┌──────────────┐             │
│  │  CloudTrail  │      │ Security Hub │      │  GuardDuty   │             │
│  │  (Local)     │      │  (Standalone)│      │  (Detector)  │             │
│  └──────┬───────┘      └──────┬───────┘      └──────┬───────┘             │
│         │                     │                      │                      │
│         │   ┌─────────────────┴──────────────────────┘                     │
│         │   │                                                               │
│         └───┼──► EventBridge Default Bus                                   │
│             │                                                               │
│             │   EventBridge Rule (Cross-Account)                           │
│             │   • Target: Central Account Event Bus                        │
│             └──────────────────┬────────────────────────────────────       │
│                                │                                            │
│  ┌──────────────────────────┐  │                                           │
│  │  IAM Role: Custodian     │◄─┼─────────────────────────────────────┐    │
│  │  ExecutionRole           │  │                                      │    │
│  ├──────────────────────────┤  │                                      │    │
│  │  Trust Policy:           │  │                                      │    │
│  │    Principal: Central    │  │                                      │    │
│  │    Account               │  │                                      │    │
│  │                          │  │                                      │    │
│  │  Permissions:            │  │                                      │    │
│  │    • EC2 (terminate,     │  │                                      │    │
│  │      stop, modify)       │  │                                      │    │
│  │    • S3 (set blocks,     │  │                                      │    │
│  │      modify policies)    │  │                                      │    │
│  │    • IAM (read-only)     │  │                                      │    │
│  │    • SecurityHub (read)  │  │                                      │    │
│  └──────────────────────────┘  │                                      │    │
│                                │                                      │    │
│  Resources to Remediate:       │                                      │    │
│    • EC2 Instances             │                                      │    │
│    • S3 Buckets                │                                      │    │
│    • IAM Users/Roles           │                                      │    │
│    • Security Groups           │                                      │    │
│                                │                                      │    │
└────────────────────────────────┼──────────────────────────────────────┼────┘
                                 │                                      │
                                 │   EventBridge                       │
                                 │   Cross-Account                     │
                                 │   Event Forwarding                  │
                                 ▼                                      │
┌────────────────────────────────────────────────────────────────────────────┐
│                    CENTRAL SECURITY ACCOUNT (999999999999)                 │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────┐    │
│  │         EventBridge Custom Event Bus (Centralized)                 │    │
│  │                                                                     │    │
│  │  Receives events from:                                             │    │
│  │    • Member Account 1 (via cross-account rule)                     │    │
│  │    • Member Account 2 (via cross-account rule)                     │    │
│  │    • Member Account N (via cross-account rule)                     │    │
│  └────────────────────────┬───────────────────────────────────────────┘    │
│                           │                                                 │
│                           │   EventBridge Rule                             │
│                           │   (Pattern: All AWS Events)                    │
│                           ▼                                                 │
│         ┌─────────────────────────────────────┐                            │
│         │   Lambda: Custodian Executor        │                            │
│         │   (cloud-custodian-executor)        │                            │
│         ├─────────────────────────────────────┤                            │
│         │                                     │                            │
│         │  Components:                        │                            │
│         │  • Event Validator                  │                            │
│         │  • Account ID Extractor             │───┐                        │
│         │  • Policy Mapping Engine            │   │                        │
│         │  • Cross-Account Role Assumer       │   │                        │
│         │  • Policy Executor                  │   │                        │
│         │                                     │   │                        │
│         │  Policies (by Account):             │   │                        │
│         │  • account-111111111111:            │   │                        │
│         │    - EC2 terminate public           │   │                        │
│         │    - S3 block public access         │   │                        │
│         │  • account-222222222222:            │   │                        │
│         │    - EC2 stop untagged              │   │                        │
│         └────────┬────────────────────────────┘   │                        │
│                  │                                │                        │
│                  │  3. Assume Role               │                        │
│                  │     in Target Account         │                        │
│                  └───────────────────────────────┘                        │
│                                                                             │
│         ┌─────────────────────────────────────┐                            │
│         │   IAM Role: Lambda Execution        │                            │
│         ├─────────────────────────────────────┤                            │
│         │  Permissions:                       │                            │
│         │    • sts:AssumeRole (all member     │                            │
│         │      account execution roles)       │                            │
│         │    • s3:GetObject (policy bucket)   │                            │
│         │    • sqs:SendMessage (notifications)│                            │
│         │    • logs:PutLogEvents              │                            │
│         └─────────────────────────────────────┘                            │
│                                                                             │
│  ┌──────────────┐   ┌─────────────────┐   ┌──────────────────┐           │
│  │   S3 Bucket  │   │   SQS Queue     │   │  CloudWatch Logs │           │
│  │              │   │                 │   │                  │           │
│  │ • Policies   │   │ • Notifications │   │ • Execution Logs │           │
│  │ • Mapping    │   │ • Email Queue   │   │ • Audit Trail    │           │
│  └──────────────┘   └─────────────────┘   └──────────────────┘           │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Solution Components

### 1. Member Account Setup (Minimal)

Each member account requires **only**:

#### A. EventBridge Cross-Account Rule
```json
{
  "source": ["aws.cloudtrail", "aws.securityhub", "aws.guardduty"],
  "detail-type": [
    "AWS API Call via CloudTrail",
    "Security Hub Findings - Imported",
    "GuardDuty Finding"
  ]
}
```
**Target**: Central Account EventBridge Custom Bus

#### B. IAM Execution Role
```json
{
  "RoleName": "CloudCustodianExecutionRole",
  "TrustPolicy": {
    "Principal": {
      "AWS": "arn:aws:iam::999999999999:role/cloud-custodian-executor-role"
    }
  },
  "Permissions": [
    "ec2:TerminateInstances",
    "ec2:StopInstances",
    "ec2:ModifyInstanceAttribute",
    "s3:PutBucketPublicAccessBlock",
    "s3:PutBucketPolicy",
    "iam:ListUsers",
    "iam:GetRole",
    "securityhub:GetFindings"
  ]
}
```

**That's it!** No Lambda, no policies, no additional infrastructure.

---

### 2. Central Security Account Setup

#### A. EventBridge Custom Bus
```bash
aws events create-event-bus \
  --name centralized-security-events \
  --region us-east-1
```

#### B. EventBridge Rule
Triggers Lambda on all forwarded events:
```json
{
  "source": ["aws.cloudtrail", "aws.securityhub", "aws.guardduty"],
  "account": ["111111111111", "222222222222", "333333333333"]
}
```

#### C. Lambda Function (Enhanced)
New components in `src/policy_executor.py`:

```python
class CrossAccountExecutor:
    def __init__(self, event):
        self.account_id = event['account']
        self.region = event['region']
        
    def assume_role(self):
        """Assume role in target account"""
        sts = boto3.client('sts')
        role_arn = f"arn:aws:iam::{self.account_id}:role/CloudCustodianExecutionRole"
        
        response = sts.assume_role(
            RoleArn=role_arn,
            RoleSessionName=f"custodian-{self.account_id}",
            DurationSeconds=900
        )
        
        return boto3.Session(
            aws_access_key_id=response['Credentials']['AccessKeyId'],
            aws_secret_access_key=response['Credentials']['SecretAccessKey'],
            aws_session_token=response['Credentials']['SessionToken'],
            region_name=self.region
        )
    
    def execute_policy(self, policy, session):
        """Execute policy using assumed role credentials"""
        # Create Cloud Custodian policy with cross-account session
        policy_config = {
            'name': policy['name'],
            'resource': policy['resource'],
            'filters': policy['filters'],
            'actions': policy['actions']
        }
        
        # Execute with temporary credentials
        custodian.run(policy_config, session=session)
```

#### D. Policy Mapping (Account-Specific)
Enhanced `config/policy-mapping.json`:
```json
{
  "accounts": {
    "111111111111": {
      "name": "Production",
      "policies": {
        "RunInstances": ["aws-ec2-stop-public-instances"],
        "CreateBucket": ["s3-public-bucket-remediation-realtime"]
      }
    },
    "222222222222": {
      "name": "Development",
      "policies": {
        "RunInstances": ["aws-ec2-tag-enforcement"],
        "Security Hub Findings - Imported": ["security-hub-findings-notification"]
      }
    }
  }
}
```

---

## Execution Flow

### Step-by-Step Process

```
1. Event Occurs in Member Account (111111111111)
   └─► EC2 instance launched with public IP

2. CloudTrail logs API call
   └─► Event: "RunInstances"

3. EventBridge Rule in Member Account
   └─► Matches pattern
   └─► Forwards to Central Account Event Bus

4. Central Account EventBridge
   └─► Receives cross-account event
   └─► Triggers Lambda: cloud-custodian-executor

5. Lambda Execution
   ├─► Extract account ID: 111111111111
   ├─► Extract event: "RunInstances"
   ├─► Fetch policy mapping from S3
   ├─► Identify policy: "aws-ec2-stop-public-instances"
   ├─► Assume role: CloudCustodianExecutionRole in 111111111111
   ├─► Create boto3 session with temporary credentials
   ├─► Execute policy with cross-account session
   │   ├─► Query EC2 instances in member account
   │   ├─► Filter: PublicIpAddress != null
   │   ├─► Action: Terminate instance
   │   └─► Log: CloudWatch in central account
   └─► Send notification to SQS (if configured)

6. Email Notification (Optional)
   └─► Mailer Lambda processes SQS
   └─► Sends email via SES
```

---

## Terraform Implementation

### Member Account Module

`terraform/modules/member-account/main.tf`:
```hcl
# EventBridge Rule to forward events to central account
resource "aws_cloudwatch_event_rule" "forward_to_central" {
  name        = "forward-security-events-to-central"
  description = "Forward security events to central account"

  event_pattern = jsonencode({
    source = [
      "aws.cloudtrail",
      "aws.securityhub",
      "aws.guardduty"
    ]
  })
}

resource "aws_cloudwatch_event_target" "central_bus" {
  rule      = aws_cloudwatch_event_rule.forward_to_central.name
  arn       = "arn:aws:events:us-east-1:999999999999:event-bus/centralized-security-events"
  role_arn  = aws_iam_role.eventbridge_cross_account.arn
}

# IAM Role for EventBridge cross-account forwarding
resource "aws_iam_role" "eventbridge_cross_account" {
  name = "eventbridge-cross-account-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "events.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "eventbridge_put_events" {
  role = aws_iam_role.eventbridge_cross_account.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "events:PutEvents"
      Resource = "arn:aws:events:us-east-1:999999999999:event-bus/centralized-security-events"
    }]
  })
}

# IAM Role for Cloud Custodian execution
resource "aws_iam_role" "custodian_execution" {
  name = "CloudCustodianExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::999999999999:role/cloud-custodian-executor-role"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "sts:ExternalId" = "cloud-custodian-${var.account_id}"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "custodian_permissions" {
  role       = aws_iam_role.custodian_execution.name
  policy_arn = aws_iam_policy.custodian_remediation.arn
}

resource "aws_iam_policy" "custodian_remediation" {
  name        = "CloudCustodianRemediationPolicy"
  description = "Permissions for Cloud Custodian to remediate resources"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2Remediation"
        Effect = "Allow"
        Action = [
          "ec2:TerminateInstances",
          "ec2:StopInstances",
          "ec2:ModifyInstanceAttribute",
          "ec2:DescribeInstances",
          "ec2:DescribeSecurityGroups"
        ]
        Resource = "*"
      },
      {
        Sid    = "S3Remediation"
        Effect = "Allow"
        Action = [
          "s3:PutBucketPublicAccessBlock",
          "s3:PutBucketPolicy",
          "s3:GetBucketPublicAccessBlock",
          "s3:ListBucket"
        ]
        Resource = "*"
      },
      {
        Sid    = "SecurityHubRead"
        Effect = "Allow"
        Action = [
          "securityhub:GetFindings",
          "securityhub:DescribeHub"
        ]
        Resource = "*"
      }
    ]
  })
}

variable "account_id" {
  description = "AWS Account ID"
  type        = string
}
```

### Central Account Module

`terraform/modules/central-account/main.tf`:
```hcl
# EventBridge Custom Bus
resource "aws_cloudwatch_event_bus" "centralized" {
  name = "centralized-security-events"
}

# Policy to allow member accounts to put events
resource "aws_cloudwatch_event_bus_policy" "allow_member_accounts" {
  event_bus_name = aws_cloudwatch_event_bus.centralized.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowMemberAccountPutEvents"
      Effect = "Allow"
      Principal = {
        AWS = [
          "arn:aws:iam::111111111111:root",
          "arn:aws:iam::222222222222:root",
          "arn:aws:iam::333333333333:root"
        ]
      }
      Action   = "events:PutEvents"
      Resource = aws_cloudwatch_event_bus.centralized.arn
    }]
  })
}

# EventBridge Rule on custom bus
resource "aws_cloudwatch_event_rule" "custodian_trigger" {
  name           = "cloud-custodian-cross-account-trigger"
  description    = "Trigger Cloud Custodian for cross-account events"
  event_bus_name = aws_cloudwatch_event_bus.centralized.name

  event_pattern = jsonencode({
    source = [
      "aws.cloudtrail",
      "aws.securityhub",
      "aws.guardduty"
    ]
    account = var.member_account_ids
  })
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule           = aws_cloudwatch_event_rule.custodian_trigger.name
  event_bus_name = aws_cloudwatch_event_bus.centralized.name
  arn            = aws_lambda_function.custodian_executor.arn
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.custodian_executor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.custodian_trigger.arn
}

# Lambda function (enhanced for cross-account)
resource "aws_lambda_function" "custodian_executor" {
  filename         = "lambda-function.zip"
  function_name    = "cloud-custodian-executor"
  role            = aws_iam_role.lambda_execution.arn
  handler         = "lambda_native.handler"
  runtime         = "python3.11"
  timeout         = 900
  memory_size     = 512

  environment {
    variables = {
      POLICY_BUCKET = var.policy_bucket
      CROSS_ACCOUNT = "true"
    }
  }
}

# Lambda execution role (cross-account assume role)
resource "aws_iam_role" "lambda_execution" {
  name = "cloud-custodian-executor-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_assume_member_roles" {
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AssumeRoleInMemberAccounts"
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Resource = [
          "arn:aws:iam::111111111111:role/CloudCustodianExecutionRole",
          "arn:aws:iam::222222222222:role/CloudCustodianExecutionRole",
          "arn:aws:iam::333333333333:role/CloudCustodianExecutionRole"
        ]
      },
      {
        Sid    = "S3PolicyAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.policy_bucket}",
          "arn:aws:s3:::${var.policy_bucket}/*"
        ]
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

variable "member_account_ids" {
  description = "List of member account IDs"
  type        = list(string)
}

variable "policy_bucket" {
  description = "S3 bucket for policies"
  type        = string
}
```

---

## Deployment Guide

### Step 1: Deploy Central Account

```bash
cd terraform/central-account
terraform init
terraform apply \
  -var="member_account_ids=[\"111111111111\",\"222222222222\"]" \
  -var="policy_bucket=central-custodian-policies"
```

### Step 2: Deploy Each Member Account

```bash
cd terraform/member-account
terraform init
terraform apply \
  -var="account_id=111111111111" \
  -var="central_account_id=999999999999"
```

Repeat for each member account.

### Step 3: Upload Policies to Central S3

```bash
aws s3 cp policies/ s3://central-custodian-policies/policies/ --recursive
aws s3 cp config/policy-mapping.json s3://central-custodian-policies/config/
```

---

## Security Considerations

### 1. External ID for AssumeRole
Always use ExternalId to prevent confused deputy problem:
```python
response = sts.assume_role(
    RoleArn=role_arn,
    RoleSessionName=f"custodian-{account_id}",
    ExternalId=f"cloud-custodian-{account_id}",
    DurationSeconds=900
)
```

### 2. Least Privilege IAM Policies
Each member account role should have only necessary permissions:
- EC2: Only terminate/stop (not create/modify)
- S3: Only block public access (not delete)
- IAM: Read-only

### 3. CloudTrail Event Validation
Verify event authenticity before assuming roles:
```python
def validate_event_source(event):
    if event.get('source') not in ['aws.cloudtrail', 'aws.securityhub']:
        raise ValueError("Invalid event source")
    
    if 'account' not in event:
        raise ValueError("Missing account ID")
    
    return True
```

### 4. Audit Logging
All cross-account actions logged to CloudWatch in central account:
```python
logger.info({
    'action': 'assume_role',
    'target_account': account_id,
    'role': role_arn,
    'success': True,
    'policy': policy_name
})
```

---

## Testing

### Test EventBridge Forwarding

**Member Account**:
```bash
aws events put-events --entries '[
  {
    "Source": "aws.cloudtrail",
    "DetailType": "AWS API Call via CloudTrail",
    "Detail": "{\"eventName\": \"RunInstances\", \"awsRegion\": \"us-east-1\"}",
    "EventBusName": "default"
  }
]'
```

**Central Account** - Check Lambda logs:
```bash
aws logs tail /aws/lambda/cloud-custodian-executor --follow
```

### Test Cross-Account Remediation

**Member Account** - Launch EC2 with public IP:
```bash
aws ec2 run-instances \
  --image-id ami-0c55b159cbfafe1f0 \
  --instance-type t2.micro \
  --associate-public-ip-address
```

**Central Account** - Verify execution:
```bash
# Check Lambda execution
aws logs tail /aws/lambda/cloud-custodian-executor --since 2m

# Check assumed role CloudTrail
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=Username,AttributeValue=custodian-111111111111
```

---

## Benefits

| Feature | Single Account | Cross-Account |
|---------|---------------|---------------|
| **Deployment** | Each account | Central only |
| **Maintenance** | N × accounts | 1 account |
| **Policy Updates** | Update all | Update once |
| **Audit Trail** | Scattered | Centralized |
| **Cost** | N × Lambda | 1 Lambda |
| **Compliance** | Per account | Unified |

---

## Cost Estimation

### Single Account (Per Account)
- Lambda: $0.20/month × N accounts
- EventBridge: $0.50/month × N accounts
- Total: **$0.70 × N per month**

### Cross-Account (Centralized)
- Lambda: $0.20/month (central)
- EventBridge: $0.10/month × N accounts (forwarding only)
- STS API calls: $0.05/month
- Total: **$0.20 + (0.10 × N) per month**

**Example**: 10 accounts
- Single: $7.00/month
- Cross-Account: $1.20/month
- **Savings: 83%**

---

## Limitations & Workarounds

### 1. EventBridge Cross-Region
**Limitation**: Events don't automatically forward across regions.

**Workaround**: Deploy EventBridge rules in each region of member accounts, all forwarding to central account's primary region.

### 2. STS Session Duration
**Limitation**: Maximum 1 hour session duration.

**Workaround**: For long-running policies, implement session refresh logic:
```python
def refresh_credentials_if_needed(session, start_time):
    if time.time() - start_time > 2700:  # 45 minutes
        return assume_role()  # Get new credentials
    return session
```

### 3. API Rate Limits
**Limitation**: AssumeRole has rate limits (200 TPS).

**Workaround**: Implement exponential backoff and request caching:
```python
@lru_cache(maxsize=100)
def assume_role_cached(account_id, ttl_hash):
    return assume_role(account_id)

# Call with: assume_role_cached(account_id, ttl_hash=int(time.time() / 300))
```

---

## Next Steps

1. ✅ Review cross-account architecture
2. ✅ Deploy central account infrastructure
3. ✅ Deploy member account IAM roles and EventBridge rules
4. ✅ Update Lambda function with cross-account logic
5. ✅ Test event forwarding and role assumption
6. ✅ Deploy policies and test remediation
7. ✅ Monitor CloudWatch logs and audit trail

---

## References

- [AWS EventBridge Cross-Account Events](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-cross-account.html)
- [STS AssumeRole Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use.html)
- [Cloud Custodian Cross-Account Execution](https://cloudcustodian.io/docs/aws/usage.html#cross-account-execution)
