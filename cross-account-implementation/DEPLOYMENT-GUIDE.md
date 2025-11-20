# Cross-Account Cloud Custodian Implementation - Complete Deployment Guide

## 📋 Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Architecture](#architecture)
4. [Step-by-Step Deployment](#step-by-step-deployment)
5. [Configuration](#configuration)
6. [Testing](#testing)
7. [Troubleshooting](#troubleshooting)
8. [Maintenance](#maintenance)

---

## Overview

This implementation provides a complete cross-account Cloud Custodian solution that:

- **Centralizes security automation** in a single account
- **Executes policies across multiple member accounts** via EventBridge and STS AssumeRole
- **Reduces costs by 83%** compared to per-account deployment
- **Requires minimal setup** in member accounts (just EventBridge + IAM role)
- **Provides production-ready Terraform modules** for infrastructure as code

### What's Included

```
cross-account-implementation/
├── terraform/
│   ├── central-account/     # Central security account infrastructure
│   └── member-account/      # Member account minimal setup
├── src/                     # Lambda function Python code
│   ├── lambda_handler.py
│   ├── cross_account_executor.py
│   └── validator.py
├── config/                  # Configuration files
│   └── account-policy-mapping.json
├── policies/                # Example Cloud Custodian policies
│   ├── ec2-require-tags.yml
│   ├── s3-block-public-access.yml
│   └── ...
├── scripts/                 # Deployment and testing scripts
│   ├── build-lambda-package.ps1
│   ├── deploy.ps1
│   └── test-cross-account-access.ps1
└── requirements.txt         # Python dependencies
```

---

## Prerequisites

### Required Tools

1. **AWS CLI** (v2.x or higher)
   ```powershell
   aws --version
   ```

2. **Terraform** (v1.0 or higher)
   ```powershell
   terraform version
   ```

3. **Python** (3.11 or higher)
   ```powershell
   python --version
   ```

4. **PowerShell** (5.1 or higher)
   ```powershell
   $PSVersionTable.PSVersion
   ```

### AWS Account Setup

You need:
- **1 Central Security Account** - Where Lambda and EventBridge bus will run
- **N Member Accounts** - Accounts to monitor and remediate

### AWS Permissions

**Central Account:**
- Create EventBridge custom bus and rules
- Create Lambda functions and IAM roles
- Create S3 buckets (for policies)
- Create CloudWatch log groups

**Member Accounts:**
- Create EventBridge rules
- Create IAM roles with trust policies
- Attach IAM policies for remediation permissions

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Member Account 1                            │
│                                                                 │
│  CloudTrail/Security Hub/GuardDuty/Config Event                │
│                    ↓                                            │
│  ┌──────────────────────────────────────────┐                  │
│  │ EventBridge Rule                          │                  │
│  │ - Forward all security events             │                  │
│  └──────────────────────────────────────────┘                  │
│                    ↓                                            │
│  ┌──────────────────────────────────────────┐                  │
│  │ IAM Role: CloudCustodianExecutionRole     │                  │
│  │ - Trust: Central Account                  │                  │
│  │ - External ID: cloud-custodian-<account>  │                  │
│  └──────────────────────────────────────────┘                  │
└─────────────────────────────────────────────────────────────────┘
                    ↓ (PutEvents)
┌─────────────────────────────────────────────────────────────────┐
│                   Central Security Account                       │
│                                                                 │
│  ┌──────────────────────────────────────────┐                  │
│  │ EventBridge Custom Bus                    │                  │
│  │ "centralized-security-events"             │                  │
│  └──────────────────────────────────────────┘                  │
│                    ↓                                            │
│  ┌──────────────────────────────────────────┐                  │
│  │ EventBridge Rule                          │                  │
│  │ - Match security events from members      │                  │
│  └──────────────────────────────────────────┘                  │
│                    ↓                                            │
│  ┌──────────────────────────────────────────┐                  │
│  │ Lambda: cloud-custodian-executor          │                  │
│  │ 1. Extract account ID from event          │                  │
│  │ 2. Assume role in member account          │                  │
│  │ 3. Execute Cloud Custodian policy         │                  │
│  └──────────────────────────────────────────┘                  │
│                    ↓                                            │
│  ┌──────────────────────────────────────────┐                  │
│  │ S3 Bucket: Policy Storage                 │                  │
│  │ - policies/ec2-require-tags.yml           │                  │
│  │ - config/account-policy-mapping.json      │                  │
│  └──────────────────────────────────────────┘                  │
└─────────────────────────────────────────────────────────────────┘
```

### Key Components

1. **EventBridge Custom Bus** - Receives events from all member accounts
2. **Lambda Function** - Executes Cloud Custodian policies with cross-account credentials
3. **S3 Bucket** - Stores policies and account mappings
4. **IAM Roles** - Enable cross-account access with External ID security

---

## Step-by-Step Deployment

### Phase 1: Prepare Central Account

#### 1.1 Configure Terraform Variables

```powershell
cd terraform/central-account
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
aws_region = "us-east-1"
environment = "production"

# List all member account IDs
member_account_ids = [
  "111111111111",
  "222222222222",
  "333333333333"
]

# Policy storage bucket
policy_bucket_name = "my-org-custodian-policies"
create_policy_bucket = true

# Lambda configuration
lambda_timeout = 900
lambda_memory_size = 512
log_level = "INFO"

# Optional: SQS notifications
create_notification_queue = false
```

#### 1.2 Build Lambda Package

```powershell
cd ..\..
.\scripts\build-lambda-package.ps1
```

This creates `terraform/central-account/lambda-function.zip` with:
- Lambda handler code
- Cloud Custodian library
- All dependencies

#### 1.3 Deploy Central Account Infrastructure

```powershell
.\scripts\deploy.ps1 -Mode central
```

Or manually:

```powershell
cd terraform/central-account
terraform init
terraform plan
terraform apply
```

#### 1.4 Save Outputs

```powershell
terraform output > outputs.txt
```

You'll need:
- `event_bus_arn` - For member account configuration
- `event_bus_name` - For member account configuration
- `policy_bucket_name` - For uploading policies

---

### Phase 2: Upload Policies and Configuration

#### 2.1 Upload Cloud Custodian Policies

```powershell
$bucketName = "my-org-custodian-policies"  # From terraform output

# Upload all example policies
Get-ChildItem policies/*.yml | ForEach-Object {
    aws s3 cp $_.FullName "s3://$bucketName/policies/$($_.Name)"
}
```

#### 2.2 Upload Account Policy Mapping

Edit `config/account-policy-mapping.json` with your account IDs and policy mappings:

```json
{
  "accounts": {
    "111111111111": {
      "name": "Production Account",
      "environment": "production",
      "policies": {
        "RunInstances": ["ec2-require-tags", "ec2-encryption-required"],
        "CreateBucket": ["s3-block-public-access", "s3-encryption-required"]
      }
    }
  }
}
```

Upload to S3:

```powershell
aws s3 cp config/account-policy-mapping.json "s3://$bucketName/config/"
```

---

### Phase 3: Deploy to Member Accounts

**Repeat these steps for EACH member account.**

#### 3.1 Switch to Member Account Credentials

```powershell
# Option 1: Use AWS CLI profiles
$env:AWS_PROFILE = "member-account-1"

# Option 2: Use temporary credentials
# (Manually set AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN)
```

#### 3.2 Configure Member Account Terraform

```powershell
cd terraform/member-account
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
central_account_id = "999999999999"  # Central account ID
central_environment = "production"   # Must match central account

# Copy from central account terraform output
central_event_bus_arn = "arn:aws:events:us-east-1:999999999999:event-bus/centralized-security-events"

# Optional local logging
create_local_log_group = false
```

#### 3.3 Deploy Member Account Infrastructure

```powershell
terraform init
terraform plan
terraform apply
```

#### 3.4 Verify Outputs

```powershell
terraform output
```

Note the `external_id` value - it should be `cloud-custodian-<account_id>`.

---

### Phase 4: Testing

#### 4.1 Test Cross-Account Access

```powershell
cd ..\..
.\scripts\test-cross-account-access.ps1 `
    -CentralAccountId "999999999999" `
    -MemberAccountIds "111111111111,222222222222"
```

Expected output:

```
Testing Account: 111111111111
[1/4] Testing AssumeRole...
  ✓ Successfully assumed role
[2/4] Testing STS GetCallerIdentity...
  ✓ STS access confirmed
[3/4] Testing EC2 DescribeInstances...
  ✓ EC2 access confirmed (5 instances found)
[4/4] Testing S3 ListBuckets...
  ✓ S3 access confirmed (12 buckets found)

All tests passed! ✓
```

#### 4.2 Test Lambda Function

Send a test event:

```powershell
$testEvent = @{
    "source" = "aws.cloudtrail"
    "detail-type" = "AWS API Call via CloudTrail"
    "account" = "111111111111"
    "region" = "us-east-1"
    "detail" = @{
        "eventName" = "RunInstances"
        "userIdentity" = @{
            "accountId" = "111111111111"
        }
    }
} | ConvertTo-Json -Depth 10

aws lambda invoke `
    --function-name "cloud-custodian-cross-account-executor-production" `
    --payload $testEvent `
    response.json

cat response.json
```

#### 4.3 Monitor CloudWatch Logs

```powershell
aws logs tail /aws/lambda/cloud-custodian-cross-account-executor-production --follow
```

---

## Configuration

### Account Policy Mapping Structure

```json
{
  "accounts": {
    "<ACCOUNT_ID>": {
      "name": "Human-readable name",
      "environment": "production|staging|development",
      "policies": {
        "<EVENT_NAME>": ["policy1", "policy2"]
      }
    }
  },
  "default_policies": {
    "<EVENT_NAME>": ["default-policy"]
  }
}
```

### Supported Event Names

| Event Source | Event Name | Description |
|-------------|------------|-------------|
| `aws.cloudtrail` | `RunInstances` | EC2 instance launched |
| `aws.cloudtrail` | `CreateBucket` | S3 bucket created |
| `aws.cloudtrail` | `CreateAccessKey` | IAM access key created |
| `aws.securityhub` | `SecurityHubFinding` | Security Hub finding |
| `aws.guardduty` | `GuardDutyFinding` | GuardDuty finding |
| `aws.config` | `ConfigComplianceChange` | Config compliance change |

### Policy File Naming

- Policy file name (without `.yml`) must match the policy name in account mapping
- Example: `ec2-require-tags.yml` → `"ec2-require-tags"`

---

## Troubleshooting

### Issue: AssumeRole Failed - Access Denied

**Symptoms:**
```
✗ Failed to assume role in account 111111111111: AccessDenied
```

**Solutions:**

1. **Verify trust policy in member account:**
   ```powershell
   aws iam get-role --role-name CloudCustodianExecutionRole --query 'Role.AssumeRolePolicyDocument'
   ```

2. **Check External ID:**
   - Should be `cloud-custodian-<account_id>`
   - Must match between central Lambda and member role

3. **Verify central Lambda role has permissions:**
   - Check `sts:AssumeRole` permission
   - Verify role ARN pattern matches

### Issue: Lambda Timeout

**Symptoms:**
```
Task timed out after 900.00 seconds
```

**Solutions:**

1. **Increase timeout:**
   - Edit `terraform/central-account/terraform.tfvars`
   - Set `lambda_timeout = 900` (maximum)

2. **Optimize policies:**
   - Reduce number of resources checked
   - Add more specific filters

### Issue: Policy Not Found

**Symptoms:**
```
Failed to load policy from S3: NoSuchKey
```

**Solutions:**

1. **Verify policy uploaded to S3:**
   ```powershell
   aws s3 ls s3://my-org-custodian-policies/policies/
   ```

2. **Check policy name matches:**
   - Account mapping: `"ec2-require-tags"`
   - S3 key: `policies/ec2-require-tags.yml`

### Issue: No Policies Executed

**Symptoms:**
```
No policies configured for this event
```

**Solutions:**

1. **Check account mapping:**
   - Verify account ID exists in mapping
   - Verify event name matches

2. **Verify mapping uploaded:**
   ```powershell
   aws s3 cp s3://my-org-custodian-policies/config/account-policy-mapping.json -
   ```

---

## Maintenance

### Adding a New Member Account

1. **Update central account:**
   ```powershell
   # Edit terraform/central-account/terraform.tfvars
   member_account_ids = [
     "111111111111",
     "222222222222",
     "444444444444"  # New account
   ]
   
   # Apply changes
   terraform apply
   ```

2. **Deploy to new member account:**
   ```powershell
   # Switch to new account credentials
   $env:AWS_PROFILE = "member-account-4"
   
   cd terraform/member-account
   terraform apply
   ```

3. **Update account mapping:**
   ```powershell
   # Edit config/account-policy-mapping.json
   # Upload to S3
   aws s3 cp config/account-policy-mapping.json s3://my-org-custodian-policies/config/
   ```

### Adding New Policies

1. **Create policy file:**
   ```powershell
   # Create policies/my-new-policy.yml
   ```

2. **Upload to S3:**
   ```powershell
   aws s3 cp policies/my-new-policy.yml s3://my-org-custodian-policies/policies/
   ```

3. **Update account mapping:**
   ```json
   {
     "accounts": {
       "111111111111": {
         "policies": {
           "RunInstances": ["ec2-require-tags", "my-new-policy"]
         }
       }
     }
   }
   ```

4. **Upload mapping:**
   ```powershell
   aws s3 cp config/account-policy-mapping.json s3://my-org-custodian-policies/config/
   ```

### Monitoring

#### CloudWatch Metrics

Key metrics to monitor:
- Lambda invocations
- Lambda errors
- Lambda duration
- EventBridge rule triggers

#### CloudWatch Logs Insights Query

```sql
fields @timestamp, @message
| filter @message like /Policy execution/
| stats count() by account_id, policy_name
```

### Cost Optimization

**Current cost structure (10 accounts):**
- EventBridge custom bus: Free
- EventBridge rules (11 total): $1.00/month
- Lambda invocations: $0.20/month
- S3 storage: Negligible
- **Total: ~$1.20/month**

**vs. per-account deployment:**
- Lambda × 10: $5.00/month
- EventBridge rules × 10: $2.00/month
- **Total: ~$7.00/month**

**Savings: 83%**

---

## Summary

You now have:

✅ **Central security account** with EventBridge custom bus and Lambda  
✅ **Member accounts** with minimal EventBridge forwarding setup  
✅ **Cross-account IAM roles** with External ID security  
✅ **Cloud Custodian policies** for automated remediation  
✅ **Account-specific policy mapping** for flexible enforcement  
✅ **Testing scripts** to verify connectivity  
✅ **Deployment scripts** for automation  

**Cost:** ~$1.20/month for 10 accounts (83% savings)  
**Maintenance:** Minimal - add policies via S3 upload  
**Security:** External ID prevents confused deputy attacks  

---

## Support

For issues or questions:
1. Check CloudWatch logs for Lambda execution details
2. Run test scripts to verify cross-account access
3. Review Terraform outputs for configuration values
4. Verify EventBridge rules are triggering in member accounts

**Happy automating! 🚀**
