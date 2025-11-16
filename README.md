# Cloud Custodian Single Lambda with EventBridge

A complete solution for running Cloud Custodian policies in AWS Lambda triggered by EventBridge, with infrastructure managed by Terraform and automated deployment via GitHub Actions.

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          Event Sources                                   │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│  ┌──────────────┐       ┌──────────────┐       ┌──────────────┐        │
│  │  CloudTrail  │       │ Security Hub │       │  GuardDuty   │        │
│  │              │       │              │       │              │        │
│  │ • EC2 Events │       │ • Findings   │       │ • Findings   │        │
│  │ • S3 Events  │       │ • Compliance │       │ • Threats    │        │
│  │ • IAM Events │       │ • Standards  │       │ • Anomalies  │        │
│  └──────┬───────┘       └──────┬───────┘       └──────┬───────┘        │
│         │                      │                       │                │
│         └──────────────────────┴───────────────────────┘                │
│                                │                                         │
└────────────────────────────────┼─────────────────────────────────────────┘
                                 │
                                 ▼
                    ┌────────────────────────┐
                    │   EventBridge Rules    │
                    ├────────────────────────┤
                    │ • CloudTrail Rule      │
                    │   (EC2, S3, IAM APIs)  │
                    │                        │
                    │ • Security Hub Rule    │
                    │   (Findings Import)    │
                    └───────────┬────────────┘
                                │
                                │ Trigger
                                ▼
              ┌─────────────────────────────────┐
              │   Lambda: Custodian Executor    │
              │   (cloud-custodian-executor)    │
              ├─────────────────────────────────┤
              │                                 │
              │  Components:                    │
              │  • Event Validator              │◄─── Native Library
              │  • Policy Executor              │     (Cloud Custodian)
              │  • Policy Mapping Engine        │
              │                                 │
              │  Policies:                      │
              │  • EC2: Terminate Public        │
              │  • S3: Block Public Access      │
              │  • Security Hub: Notify         │
              └────────┬────────────────────────┘
                       │
        ┌──────────────┼──────────────┐
        │              │              │
        ▼              ▼              ▼
   ┌─────────┐   ┌─────────┐   ┌─────────────┐
   │   EC2   │   │   S3    │   │     SQS     │
   │ Actions │   │ Actions │   │   Queue     │
   └─────────┘   └─────────┘   └──────┬──────┘
                                       │
                                       │ Trigger
                                       ▼
                          ┌────────────────────────┐
                          │  Lambda: Mailer        │
                          │  (custodian-mailer)    │
                          ├────────────────────────┤
                          │                        │
                          │  • SQS Message Parser  │
                          │  • Template Renderer   │
                          │  • Email Formatter     │
                          └───────────┬────────────┘
                                      │
                                      ▼
                             ┌────────────────┐
                             │   Amazon SES   │
                             │                │
                             │ Email Delivery │
                             └────────────────┘
                                      │
                                      ▼
                              [ Email Recipients ]

              ┌─────────────────────────────────────┐
              │      Supporting Services            │
              ├─────────────────────────────────────┤
              │  • CloudWatch Logs (Monitoring)     │
              │  • S3 Bucket (Policy Storage)       │
              │  • IAM Roles (Permissions)          │
              │  • GitHub Actions (CI/CD)           │
              └─────────────────────────────────────┘
```

### Architecture Components

1. **Event Sources**:
   - **CloudTrail**: Captures EC2, S3, and IAM API calls in real-time
   - **Security Hub**: Aggregates security findings from AWS services
   - **GuardDuty**: Threat detection findings integrated via Security Hub

2. **EventBridge Rules**:
   - **CloudTrail Rule**: Triggers on `RunInstances`, `CreateBucket` events
   - **Security Hub Rule**: Triggers on `Security Hub Findings - Imported` events

3. **Lambda Executor**:
   - Validates incoming events (CloudTrail or Security Hub)
   - Maps events to appropriate Cloud Custodian policies
   - Executes policies using native Cloud Custodian library
   - Takes remediation actions on AWS resources
   - Sends notifications to SQS queue

4. **Lambda Mailer**:
   - Polls SQS queue for notification messages
   - Renders email templates with finding details
   - Sends formatted emails via Amazon SES

5. **Policy Execution Flow**:
   - **EC2**: Terminates instances with public IPs → Email notification
   - **S3**: Enables public access blocks on public buckets → Email notification
   - **Security Hub**: Filters HIGH/CRITICAL findings → Email notification

## 🎯 Features

- **Native Library Execution**: Uses Cloud Custodian as a Python library for optimal performance
- **Multi-Source Event Processing**: 
  - **CloudTrail Events**: Real-time API call monitoring (EC2, S3, IAM)
  - **Security Hub Findings**: Aggregated security findings from AWS Security Hub
  - **GuardDuty & Macie**: Threat detection and data security findings via Security Hub
  
- **Event-Driven Architecture**: EventBridge rules trigger Lambda functions based on:
  - Resource creation/modification (CloudTrail)
  - Security findings and compliance issues (Security Hub)
  
- **Automated Remediation**: 
  - EC2: Terminate instances with public IPs
  - S3: Enable public access blocks on public buckets
  - Security Hub: Alert on HIGH/CRITICAL findings
  
- **Email Notifications**: 
  - SQS-based notification queue
  - Dedicated mailer Lambda function
  - Amazon SES integration
  - Rich HTML email templates with finding details
  
- **Terraform Infrastructure**: Complete IaC for Lambda, EventBridge, IAM, SQS, and SES
- **GitHub Actions CI/CD**: Automated policy upload to S3 on every commit
- **Policy Mapping Engine**: Dynamic event-to-policy mapping with JSON configuration

## 📋 Prerequisites

- AWS Account with appropriate permissions
- **CloudTrail enabled** with S3 data events logging
- Terraform >= 1.0
- Python 3.11+
- AWS CLI configured
- Git and GitHub account (for CI/CD)

## ⚠️ Important: CloudTrail Setup

For the EventBridge rule to trigger on S3 events, you **must** have CloudTrail enabled with S3 data events logging:

1. **Enable CloudTrail** (if not already enabled):
   ```bash
   aws cloudtrail create-trail \
     --name cloud-custodian-trail \
     --s3-bucket-name your-cloudtrail-bucket
   ```

2. **Start logging**:
   ```bash
   aws cloudtrail start-logging --name cloud-custodian-trail
   ```

3. **Verify CloudTrail is working**:
   ```bash
   aws cloudtrail get-trail-status --name cloud-custodian-trail
   ```

**Note**: CloudTrail events typically take 5-15 minutes to appear in EventBridge. The EventBridge rule will trigger on these S3 API calls:
- `CreateBucket`
- `PutBucketAcl`
- `PutBucketPolicy`
- `PutBucketPublicAccessBlock`
- `DeleteBucketPublicAccessBlock`
- `PutBucketCors`
- `PutBucketWebsite`

## 🚀 Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/ysrinu95/cloud-custodian-single-lambda.git
cd cloud-custodian-single-lambda
```

### 2. Configure AWS Credentials

Ensure AWS CLI is configured with appropriate credentials:
```bash
aws configure
```

Required permissions:
- Lambda (create/update functions)
- IAM (create/update roles and policies)
- EventBridge (create/update rules)
- S3 (create bucket for policies)
- SQS (create queues)
- SES (verify email addresses)
- CloudTrail (view trails)
- Security Hub (read findings)

### 3. Verify Prerequisites

**CloudTrail**: Ensure CloudTrail is enabled and logging S3/EC2 events
```bash
aws cloudtrail describe-trails
aws cloudtrail get-trail-status --name <trail-name>
```

**Security Hub**: Enable Security Hub if not already enabled
```bash
aws securityhub describe-hub
# If not enabled:
aws securityhub enable-security-hub
```

**SES Email**: Verify sender email address
```bash
aws ses verify-email-identity --email-address your-email@example.com
```

### 4. Configure Terraform

Edit `terraform/terraform.tfvars`:
```hcl
aws_region   = "us-east-1"
environment  = "dev"
account_id   = "123456789012"
mailer_email = "your-email@example.com"
```

### 5. Deploy Infrastructure

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

This will create:
- 2 Lambda functions (executor + mailer)
- 2 EventBridge rules (CloudTrail + Security Hub)
- IAM roles with necessary permissions
- SQS queue for notifications
- S3 bucket for policy storage

### 6. Upload Policies

Policies are automatically uploaded to S3 via GitHub Actions on every commit.

**Manual upload** (if needed):
```bash
aws s3 cp policies/ s3://ysr95-custodian-policies/policies/ --recursive --exclude "*" --include "*.yml"
```

### 7. Test the Setup

**Test EC2 Policy**:
```bash
# Launch an EC2 instance with a public IP
aws ec2 run-instances \
  --image-id ami-0c55b159cbfafe1f0 \
  --instance-type t2.micro \
  --associate-public-ip-address

# Check logs after 1-2 minutes
aws logs tail /aws/lambda/cloud-custodian-executor-dev --follow
```

**Test S3 Policy**:
```bash
# Create a bucket without public access blocks
aws s3api create-bucket --bucket test-public-bucket-$(date +%s) --region us-east-1

# Check logs after 5-15 minutes (CloudTrail delay)
aws logs tail /aws/lambda/cloud-custodian-executor-dev --follow
```

**Test Security Hub Policy**:
```bash
# Update a HIGH severity finding
aws securityhub batch-update-findings \
  --finding-identifiers Id="<finding-arn>",ProductArn="<product-arn>" \
  --note Text="Testing Cloud Custodian",UpdatedBy="Test"

# Check logs
aws logs tail /aws/lambda/cloud-custodian-executor-dev --follow
```

## 📁 Project Structure

```
cloud-custodian-single-lambda/
├── .github/
│   └── workflows/
│       └── upload-policies.yml     # GitHub Actions: Upload policies to S3
├── config/
│   └── policy-mapping.json         # Event-to-policy mapping configuration
├── docs/
│   ├── ADR-001-EventBridge-Lambda-Architecture.md
│   ├── EVENT-DRIVEN-ARCHITECTURE.md
│   ├── EVENT_CONTEXT_USAGE.md
│   └── NFR-Cloud-Custodian-Lambda.md
├── policies/
│   ├── aws-ec2-stop-public-instances.yml           # EC2 remediation policy
│   ├── s3-public-bucket-remediation-realtime.yml   # S3 remediation policy
│   └── security-hub-findings-notification.yml      # Security Hub policy
├── scripts/
│   ├── build_layer.sh              # Build Lambda layer (Linux/macOS)
│   ├── test_ec2_policy.ps1         # Test EC2 policy
│   ├── test_ec2_policy.py          # Python test script
│   └── transform_policy_mapping.py # Policy mapping transformer
├── src/
│   ├── lambda_native.py            # Lambda entry point
│   ├── policy_executor.py          # Policy execution engine
│   └── validator.py                # Event validator (CloudTrail + Security Hub)
├── terraform/
│   ├── cloud-custodian.tf          # Main infrastructure config
│   ├── variables.tf                # Input variables
│   ├── outputs.tf                  # Output values
│   ├── terraform.tfvars            # Variable values
│   └── lambda-function.zip         # Lambda deployment package
├── cloudtrail-event-selectors.json # CloudTrail event configuration
├── requirements.txt                # Python dependencies
└── README.md                       # This file
```

## � Active Policies

### 1. EC2 Public Instance Termination
**File**: `policies/aws-ec2-stop-public-instances.yml`

**Trigger**: CloudTrail `RunInstances` event

**Function**: Automatically terminates EC2 instances launched with public IP addresses

**Actions**:
- Terminates the instance
- Sends email notification with instance details

**Status**: ✅ Tested and operational

---

### 2. S3 Public Bucket Remediation
**File**: `policies/s3-public-bucket-remediation-realtime.yml`

**Trigger**: CloudTrail `CreateBucket` event

**Function**: Automatically secures S3 buckets that allow public access

**Actions**:
- Enables all four public access block settings:
  - BlockPublicAcls: true
  - IgnorePublicAcls: true
  - BlockPublicPolicy: true
  - RestrictPublicBuckets: true
- Sends email notification with bucket details

**Status**: ✅ Tested and operational

---

### 3. Security Hub Findings Notification
**File**: `policies/security-hub-findings-notification.yml`

**Trigger**: Security Hub `Findings - Imported` event

**Function**: Alerts on HIGH and CRITICAL security findings from Security Hub, GuardDuty, and Macie

**Filters**:
- Severity: HIGH or CRITICAL
- Sources: AWS Security Hub, GuardDuty, Macie

**Actions**:
- Sends detailed email notification including:
  - Finding severity and description
  - Affected resources
  - Remediation recommendations
  - Timeline (first observed, last updated)
  - Direct links to AWS Console

**Status**: 🔄 Deployed, pending testing

---

## �🔧 Configuration

### Execution Modes

#### Native Mode (Recommended)
Uses Cloud Custodian as a Python library for better performance and error handling.

```hcl
lambda_execution_mode = "native"
```

**Lambda Handler:** `src/lambda_native.py`

**Benefits:**
- Faster execution (no subprocess overhead)
- Better error handling and logging
- More Pythonic and maintainable
- Direct access to Custodian objects

#### CLI Mode
Executes Cloud Custodian CLI commands via subprocess.

```hcl
lambda_execution_mode = "cli"
```

**Lambda Handler:** `src/lambda_cli.py`

**Benefits:**
- Familiar to users who know the CLI
- Can use all CLI features and flags
- Easy to test locally

### Policy Sources

The Lambda function supports three policy sources:

#### 1. Packaged with Lambda (Default)
```json
{
  "policy_source": "file",
  "policy_path": "/var/task/policies/sample-policies.yml"
}
```

#### 2. S3 Bucket
```json
{
  "policy_source": "s3",
  "bucket": "my-policies-bucket",
  "key": "policies/prod-policies.yml"
}
```

#### 3. Inline Policy
```json
{
  "policy_source": "inline",
  "policy": {
    "policies": [...]
  }
}
```

### EventBridge Trigger Configuration

The EventBridge rule is configured to trigger on S3 bucket creation and configuration changes detected via CloudTrail. The following S3 API calls will trigger the Lambda function:

- **CreateBucket**: When a new S3 bucket is created
- **PutBucketAcl**: When bucket ACL is modified
- **PutBucketPolicy**: When bucket policy is added/changed
- **PutBucketPublicAccessBlock**: When public access block settings are modified
- **DeleteBucketPublicAccessBlock**: When public access block is removed
- **PutBucketCors**: When CORS configuration is added/changed
- **PutBucketWebsite**: When bucket is configured for static website hosting

The Lambda function receives detailed event information including:
- Bucket name
- Event name (API call)
- AWS region
- Source IP address
- User agent
- Event timestamp

**Example Event Flow:**
1. User creates a public S3 bucket
2. CloudTrail logs the `CreateBucket` API call
3. EventBridge detects the CloudTrail event (5-15 min delay)
4. Lambda function is triggered with event details
5. Cloud Custodian policies execute to check/remediate the bucket

## 🔐 IAM Permissions

The Lambda function requires appropriate IAM permissions to:

1. **Read Resources**: EC2, S3, RDS, Lambda, etc.
2. **Take Actions**: Stop instances, delete volumes, enable encryption, etc.
3. **Send Notifications**: SNS, SES
4. **Write Logs**: CloudWatch Logs

Review and customize `terraform/iam.tf` based on your policies.

## 🎬 GitHub Actions CI/CD

### Setup

1. **Add AWS Credentials to GitHub Secrets:**
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`

2. **Configure Repository Settings:**
   - Go to Settings → Environments
   - Create `development` and `production` environments
   - Add protection rules for production

### Workflow Triggers

- **Push to `main`**: Deploys to production
- **Push to `develop`**: Deploys to staging
- **Pull Request**: Runs plan only
- **Manual Dispatch**: Deploy to any environment with custom settings

### Workflow Steps

1. **Build Layer**: Creates optimized Lambda layer
2. **Terraform Plan**: Validates and plans infrastructure changes
3. **Terraform Apply**: Deploys infrastructure (only on main/develop)
4. **Test Invocation**: Validates Lambda function works

## 🧪 Testing

### Local Layer Testing

```bash
# Linux/macOS
./scripts/test_layer.sh
```

### Manual Lambda Invocation

```bash
aws lambda invoke \
  --function-name cloud-custodian-executor-dev \
  --payload '{"policy_source":"file","dryrun":true}' \
  --log-type Tail \
  response.json

cat response.json
```

### Testing Specific Policies

**Native Mode:**
```bash
aws lambda invoke \
  --function-name cloud-custodian-executor-dev \
  --payload '{
    "policy_source": "file",
    "policy_path": "/var/task/policies/test-policy.yml",
    "region": "us-east-1"
  }' \
  response.json
```

**CLI Mode:**
```bash
aws lambda invoke \
  --function-name cloud-custodian-executor-dev \
  --payload '{
    "policy_source": "file",
    "policy_path": "/var/task/policies/test-policy.yml",
    "dryrun": true,
    "verbose": true
  }' \
  response.json
```

## 📊 Monitoring

### CloudWatch Logs

View Lambda execution logs:
```bash
aws logs tail /aws/lambda/cloud-custodian-executor-dev --follow
```

### CloudWatch Metrics

Monitor Lambda metrics in AWS Console:
- Invocations
- Duration
- Errors
- Throttles

### EventBridge Monitoring

Check EventBridge rule status:
```bash
aws events describe-rule --name cloud-custodian-s3-events-dev
```

List recent rule invocations:
```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/Events \
  --metric-name Invocations \
  --dimensions Name=RuleName,Value=cloud-custodian-s3-events-dev \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

## 🔄 Updates and Maintenance

### Update Cloud Custodian Version

1. Edit `requirements.txt`:
   ```
   c7n==0.9.37  # Update version
   ```

2. Rebuild layer:
   ```bash
   ./scripts/build_layer.sh
   ```

3. Redeploy:
   ```bash
   cd terraform && terraform apply
   ```

### Update Policies

**For packaged policies:**
1. Edit files in `policies/`
2. Run `terraform apply` to redeploy Lambda

**For S3 policies:**
1. Update files in S3 bucket
2. No redeployment needed

## 🚨 Troubleshooting

### Layer Size Too Large

If layer exceeds 250MB:

1. Remove more unnecessary files in build script
2. Use Lambda container image instead
3. Split into multiple layers

### Import Errors

```bash
# Test layer locally
./scripts/test_layer.sh
```

### Permission Denied Errors

Check `terraform/iam.tf` and ensure Lambda has required permissions.

### EventBridge Not Triggering

Check CloudTrail status:
```bash
# Verify CloudTrail is enabled and logging
aws cloudtrail get-trail-status --name cloud-custodian-trail

# Check recent S3 events in CloudTrail
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceType,AttributeValue=AWS::S3::Bucket \
  --max-results 10
```

Check EventBridge rule:
```bash
# Check rule status
aws events describe-rule --name cloud-custodian-s3-events-dev

# Check Lambda permissions
aws lambda get-policy --function-name cloud-custodian-executor-dev
```

**Common Issues:**
- CloudTrail not enabled or not logging S3 data events
- CloudTrail events take 5-15 minutes to appear
- EventBridge rule pattern doesn't match the events
- Lambda function doesn't have permission to be invoked by EventBridge

## 🎓 Example Policies

The `policies/sample-policies.yml` includes examples for:

- EC2 instance tag enforcement
- Unattached EBS volume cleanup
- S3 bucket encryption enforcement
- Lambda version cleanup
- RDS backup validation

Customize these based on your requirements!

## 📚 Resources

- [Cloud Custodian Documentation](https://cloudcustodian.io/docs/)
- [AWS Lambda Layers](https://docs.aws.amazon.com/lambda/latest/dg/configuration-layers.html)
- [EventBridge Rules](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-rules.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📝 License

This project is licensed under the MIT License.

## 💡 Best Practices

1. **Start with Dry Run**: Test policies with `dryrun: true` first
2. **Monitor Costs**: Set up AWS Budgets for cost monitoring
3. **Use Tags**: Tag all resources for better tracking
4. **Review Policies**: Regularly review and update policies
5. **Test Locally**: Use Cloud Custodian CLI locally before deploying
6. **Version Control**: Keep policies in version control
7. **Separate Environments**: Use different AWS accounts for dev/prod

## 🔄 Comparison: Native vs CLI Mode

| Feature | Native Mode | CLI Mode |
|---------|------------|----------|
| Performance | ⭐⭐⭐⭐⭐ Faster | ⭐⭐⭐ Slower (subprocess) |
| Error Handling | ⭐⭐⭐⭐⭐ Better | ⭐⭐⭐ Limited |
| Debugging | ⭐⭐⭐⭐⭐ Easier | ⭐⭐⭐ Harder |
| Flexibility | ⭐⭐⭐⭐ Library API | ⭐⭐⭐⭐⭐ Full CLI |
| Familiarity | ⭐⭐⭐ Code | ⭐⭐⭐⭐⭐ CLI |
| Maintenance | ⭐⭐⭐⭐⭐ Easier | ⭐⭐⭐ More complex |

**Recommendation**: Use **Native Mode** for production workloads.

## 📞 Support

For issues and questions:
- Open an issue in the GitHub repository
- Check Cloud Custodian documentation
- Review AWS Lambda troubleshooting guides

---

**Built with ❤️ for Cloud Governance**
