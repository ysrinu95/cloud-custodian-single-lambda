# Cloud Custodian Single Lambda with EventBridge

A complete solution for running Cloud Custodian policies in AWS Lambda triggered by EventBridge, with infrastructure managed by Terraform and automated deployment via GitHub Actions.

## 🏗️ Architecture

```
┌─────────────────┐
│  EventBridge    │
│  Schedule Rule  │
└────────┬────────┘
         │ Trigger
         ▼
┌─────────────────┐      ┌──────────────────┐
│  Lambda         │◄─────┤  Lambda Layer    │
│  Function       │      │  (Cloud          │
│                 │      │   Custodian)     │
└────────┬────────┘      └──────────────────┘
         │
         ├──► CloudWatch Logs
         │
         ├──► AWS Resources (EC2, S3, RDS, etc.)
         │
         └──► SNS (Notifications)
```

## 🎯 Features

- **Two Execution Modes**:
  - **Native Mode**: Uses Cloud Custodian as a Python library (recommended)
  - **CLI Mode**: Executes `custodian` CLI commands via subprocess
  
- **EventBridge Integration**: Scheduled or event-driven policy execution
- **Terraform Infrastructure**: Complete IaC for Lambda, layers, IAM, and EventBridge
- **GitHub Actions CI/CD**: Automated building and deployment
- **Lambda Layers**: Optimized Cloud Custodian dependencies
- **Flexible Policy Management**: Support for inline, S3, or packaged policies

## 📋 Prerequisites

- AWS Account with appropriate permissions
- Terraform >= 1.0
- Python 3.11+
- AWS CLI configured
- Git and GitHub account (for CI/CD)

## 🚀 Quick Start

### 1. Clone the Repository

```bash
git clone <repository-url>
cd cloud-custodian-single-lambda
```

### 2. Build the Lambda Layer

**On Linux/macOS:**
```bash
chmod +x scripts/build_layer.sh
./scripts/build_layer.sh
```

**On Windows:**
```powershell
.\scripts\build_layer.ps1
```

### 3. Configure Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:
```hcl
aws_region             = "us-east-1"
environment            = "dev"
lambda_execution_mode  = "native"  # or "cli"
schedule_expression    = "rate(1 hour)"
```

### 4. Deploy Infrastructure

```bash
terraform init
terraform plan
terraform apply
```

## 📁 Project Structure

```
cloud-custodian-single-lambda/
├── .github/
│   └── workflows/
│       └── deploy.yml              # GitHub Actions workflow
├── policies/
│   ├── sample-policies.yml         # Example policies
│   └── test-policy.yml             # Test policy
├── src/
│   ├── lambda_native.py            # Native mode handler
│   └── lambda_cli.py               # CLI mode handler
├── scripts/
│   ├── build_layer.sh              # Layer build script (Linux/macOS)
│   ├── build_layer.ps1             # Layer build script (Windows)
│   └── test_layer.sh               # Layer test script
├── terraform/
│   ├── main.tf                     # Terraform configuration
│   ├── variables.tf                # Input variables
│   ├── outputs.tf                  # Output values
│   ├── lambda.tf                   # Lambda resources
│   ├── iam.tf                      # IAM roles and policies
│   ├── eventbridge.tf              # EventBridge rules
│   └── terraform.tfvars.example    # Example variables
├── requirements.txt                # Python dependencies
└── README.md                       # This file
```

## 🔧 Configuration

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

### EventBridge Schedule Expressions

Configure the schedule in `terraform.tfvars`:

```hcl
# Run every hour
schedule_expression = "rate(1 hour)"

# Run daily at 9 AM UTC
schedule_expression = "cron(0 9 * * ? *)"

# Run every 15 minutes
schedule_expression = "rate(15 minutes)"

# Run Monday-Friday at 6 PM UTC
schedule_expression = "cron(0 18 ? * MON-FRI *)"
```

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
aws events describe-rule --name cloud-custodian-schedule-dev
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

```bash
# Check rule status
aws events describe-rule --name cloud-custodian-schedule-dev

# Check Lambda permissions
aws lambda get-policy --function-name cloud-custodian-executor-dev
```

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
