# Cross-Account Cloud Custodian Implementation

This directory contains the implementation for running Cloud Custodian in a centralized security account that can remediate resources across multiple member accounts.

## Directory Structure

```
cross-account-implementation/
├── terraform/
│   ├── central-account/          # Infrastructure for central security account
│   │   ├── main.tf               # EventBridge custom bus, Lambda, IAM
│   │   ├── variables.tf          # Input variables
│   │   ├── outputs.tf            # Output values
│   │   └── terraform.tfvars.example
│   │
│   └── member-account/           # Infrastructure for each member account
│       ├── main.tf               # EventBridge forwarding rule, IAM role
│       ├── variables.tf          # Input variables
│       ├── outputs.tf            # Output values
│       └── terraform.tfvars.example
│
├── src/
│   ├── cross_account_executor.py # Cross-account policy execution logic
│   ├── lambda_handler.py         # Lambda entry point
│   └── validator.py              # Event validation
│
├── config/
│   └── account-policy-mapping.json  # Account-specific policy mappings
│
└── README.md                     # This file
```

## Quick Start

### Prerequisites

1. AWS CLI configured with appropriate credentials
2. Terraform >= 1.0
3. Python 3.11+
4. Access to:
   - Central security account (e.g., 999999999999)
   - Member accounts (e.g., 111111111111, 222222222222)

### Step 1: Deploy Central Account Infrastructure

```bash
cd terraform/central-account

# Copy and edit variables
cp terraform.tfvars.example terraform.tfvars
# Edit: member_account_ids, policy_bucket, etc.

# Deploy
terraform init
terraform apply
```

This creates:
- EventBridge custom bus for receiving cross-account events
- Lambda function for policy execution
- IAM role with permissions to assume roles in member accounts
- S3 bucket for policies (optional)

### Step 2: Deploy Member Account Infrastructure

For each member account:

```bash
cd terraform/member-account

# Copy and edit variables
cp terraform.tfvars.example terraform.tfvars
# Edit: account_id, central_account_id, central_event_bus_arn

# Deploy
terraform init
terraform apply
```

This creates:
- EventBridge rule to forward events to central account
- IAM role for Cloud Custodian execution (with trust to central account)
- IAM policy with remediation permissions

### Step 3: Upload Policies and Configuration

```bash
# Upload policies
aws s3 cp ../policies/ s3://YOUR-POLICY-BUCKET/policies/ --recursive

# Upload account-specific policy mapping
aws s3 cp config/account-policy-mapping.json s3://YOUR-POLICY-BUCKET/config/
```

### Step 4: Test the Setup

**Test EventBridge Forwarding**:
```bash
# In member account
aws events put-events --entries '[
  {
    "Source": "aws.ec2",
    "DetailType": "AWS API Call via CloudTrail",
    "Detail": "{\"eventName\": \"RunInstances\", \"awsRegion\": \"us-east-1\"}"
  }
]'

# Check central account Lambda logs
aws logs tail /aws/lambda/cloud-custodian-cross-account-executor --follow --region us-east-1
```

**Test Cross-Account Remediation**:
```bash
# In member account - launch EC2 with public IP
aws ec2 run-instances \
  --image-id ami-0c55b159cbfafe1f0 \
  --instance-type t2.micro \
  --associate-public-ip-address

# Check central account logs for remediation
aws logs tail /aws/lambda/cloud-custodian-cross-account-executor --since 2m --region us-east-1
```

## Configuration

### Account-Policy Mapping

Edit `config/account-policy-mapping.json`:

```json
{
  "accounts": {
    "111111111111": {
      "name": "Production",
      "region": "us-east-1",
      "policies": {
        "RunInstances": ["aws-ec2-stop-public-instances"],
        "CreateBucket": ["s3-public-bucket-remediation-realtime"]
      }
    },
    "222222222222": {
      "name": "Development",
      "region": "us-east-1",
      "policies": {
        "RunInstances": ["aws-ec2-tag-enforcement"],
        "Security Hub Findings - Imported": ["security-hub-findings-notification"]
      }
    }
  }
}
```

### Lambda Environment Variables

Set in `terraform/central-account/main.tf`:

```hcl
environment {
  variables = {
    POLICY_BUCKET            = "your-policy-bucket"
    ACCOUNT_MAPPING_KEY      = "config/account-policy-mapping.json"
    CROSS_ACCOUNT_ROLE_NAME  = "CloudCustodianExecutionRole"
    EXTERNAL_ID_PREFIX       = "cloud-custodian"
  }
}
```

## Security

### External ID

All cross-account role assumptions use External ID for security:
- Format: `cloud-custodian-{account_id}`
- Prevents confused deputy attacks

### Least Privilege

Member account execution roles have minimal permissions:
- EC2: Only terminate/stop (no create)
- S3: Only set public access blocks (no delete)
- IAM: Read-only access
- Security Hub: Read findings only

### Audit Trail

All actions logged to CloudWatch in central account:
- Which account was accessed
- What policy was executed
- What actions were taken
- Success/failure status

## Troubleshooting

### Events Not Forwarding

Check EventBridge rule in member account:
```bash
aws events describe-rule --name forward-security-events-to-central
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=PutEvents
```

### AssumeRole Fails

Verify trust relationship:
```bash
# In member account
aws iam get-role --role-name CloudCustodianExecutionRole

# Check if central account can assume
aws sts assume-role \
  --role-arn arn:aws:iam::MEMBER_ACCOUNT:role/CloudCustodianExecutionRole \
  --role-session-name test \
  --external-id cloud-custodian-MEMBER_ACCOUNT
```

### Policy Not Executing

Check Lambda logs:
```bash
aws logs tail /aws/lambda/cloud-custodian-cross-account-executor --follow
```

Check policy mapping exists in S3:
```bash
aws s3 cp s3://YOUR-POLICY-BUCKET/config/account-policy-mapping.json - | jq .
```

## Cost Estimation

### Per Month (Approximate)

**Central Account**:
- Lambda executions: $0.20
- EventBridge custom bus: $0.10
- S3 storage: $0.05

**Per Member Account**:
- EventBridge rule: $0.10
- STS API calls: $0.01

**Total for 10 Member Accounts**: ~$1.50/month

## Maintenance

### Adding New Member Account

1. Deploy member account Terraform
2. Add account to `account-policy-mapping.json`
3. Update central account Lambda IAM policy to include new account role ARN

### Updating Policies

1. Update policy YAML file
2. Upload to S3: `aws s3 cp policy.yml s3://YOUR-POLICY-BUCKET/policies/`
3. No Lambda redeployment needed!

### Updating Policy Mapping

1. Edit `config/account-policy-mapping.json`
2. Upload to S3: `aws s3 cp account-policy-mapping.json s3://YOUR-POLICY-BUCKET/config/`
3. Changes take effect immediately

## Support

For issues or questions, refer to:
- [Main Documentation](../docs/CROSS-ACCOUNT-ARCHITECTURE.md)
- [Cloud Custodian Docs](https://cloudcustodian.io/docs/)
- [AWS Cross-Account Events](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-cross-account.html)
