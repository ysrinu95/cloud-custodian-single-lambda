# GitHub Actions Workflows

This directory contains CI/CD workflows for the Cloud Custodian Lambda deployment.

## 📋 Workflows

### 1. Deploy Infrastructure (`deploy-infrastructure.yml`)

**Purpose:** Complete CI/CD pipeline for deploying Cloud Custodian Lambda infrastructure.

**Triggers:**
- Push to `main` or `develop` branches
- Manual workflow dispatch

**Jobs:**
1. **build-layer** - Builds and optimizes the Cloud Custodian Lambda layer
2. **terraform-plan** - Plans infrastructure changes
3. **terraform-apply** - Deploys infrastructure (main/develop only)
4. **terraform-destroy** - Destroys infrastructure (manual only)

**Usage:**
```bash
# Automatic deployment on push to main
git push origin main

# Manual deployment
# Go to Actions → Deploy Infrastructure → Run workflow
# Select: action=apply, environment=dev, execution_mode=native
```

---

### 2. Test Policies (`test-policies.yml`)

**Purpose:** Validate and test Cloud Custodian policies before deployment.

**Triggers:**
- Manual workflow dispatch only

**Jobs:**
1. **validate-policy** - Validates YAML and policy syntax
2. **dry-run-policy** - Tests policy without executing actions
3. **live-test-policy** - Executes policy with real actions (⚠️ use caution)
4. **test-lambda-integration** - Tests policy in deployed Lambda

**Usage:**
```bash
# Go to Actions → Test Policies → Run workflow

# Options:
# - validate-only: Just check syntax (safe)
# - dry-run: Test matching without actions (safe)
# - live-test: Execute real actions (⚠️ caution!)
```

---

## 🔐 Required Secrets

### GitHub Repository Secrets

Configure these secrets in: `Settings → Secrets and variables → Actions → Repository secrets`

#### Required Secrets:

```bash
# AWS Authentication
AWS_ROLE_ARN=arn:aws:iam::123456789012:role/GitHubActions-CloudCustodian-Role
# OR (fallback)
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY

# Terraform State
TERRAFORM_STATE_BUCKET=my-terraform-state-bucket

# Optional - for test workflows
LAMBDA_FUNCTION_NAME=cloud-custodian-executor-dev
```

---

## 🏗️ Setup Instructions

### Step 1: Configure AWS OIDC (Recommended)

Create an IAM Role for GitHub Actions:

```bash
# Create trust policy
cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/YOUR_REPO:*"
        }
      }
    }
  ]
}
EOF

# Create IAM role
aws iam create-role \
  --role-name GitHubActions-CloudCustodian-Role \
  --assume-role-policy-document file://trust-policy.json

# Attach required policies
aws iam attach-role-policy \
  --role-name GitHubActions-CloudCustodian-Role \
  --policy-arn arn:aws:iam::aws:policy/PowerUserAccess
```

### Step 2: Create S3 Bucket for Terraform State

```bash
aws s3api create-bucket \
  --bucket my-terraform-state-bucket \
  --region us-east-1

aws s3api put-bucket-versioning \
  --bucket my-terraform-state-bucket \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket my-terraform-state-bucket \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'
```

### Step 3: Add Secrets to GitHub

1. Go to your GitHub repository
2. Navigate to `Settings → Secrets and variables → Actions`
3. Click `New repository secret`
4. Add each secret:

```
Name: AWS_ROLE_ARN
Value: arn:aws:iam::123456789012:role/GitHubActions-CloudCustodian-Role

Name: TERRAFORM_STATE_BUCKET
Value: my-terraform-state-bucket
```

### Step 4: Configure Environments (Optional)

For deployment approvals:

1. Go to `Settings → Environments`
2. Create environments: `dev`, `staging`, `prod`
3. Add protection rules:
   - Required reviewers (for prod)
   - Wait timer
   - Deployment branches (main only for prod)

---

## 🚀 Deployment Flow

### Development Workflow

```mermaid
graph LR
    A[Push to develop] --> B[Build Layer]
    B --> C[Terraform Plan]
    C --> D[Terraform Apply]
    D --> E[Test Lambda]
    E --> F[Deploy to Staging]
```

### Production Workflow

```mermaid
graph LR
    A[Push to main] --> B[Build Layer]
    B --> C[Terraform Plan]
    C --> D[Review Required]
    D --> E[Terraform Apply]
    E --> F[Test Lambda]
    F --> G[Deploy to Prod]
```

---

## 📊 Workflow Status Badges

Add to your README.md:

```markdown
[![Deploy Infrastructure](https://github.com/YOUR_ORG/YOUR_REPO/actions/workflows/deploy-infrastructure.yml/badge.svg)](https://github.com/YOUR_ORG/YOUR_REPO/actions/workflows/deploy-infrastructure.yml)

[![Test Policies](https://github.com/YOUR_ORG/YOUR_REPO/actions/workflows/test-policies.yml/badge.svg)](https://github.com/YOUR_ORG/YOUR_REPO/actions/workflows/test-policies.yml)
```

---

## 🧪 Testing Policies

### Validate Policy Syntax

```bash
# Manual testing locally
custodian validate policies/sample-policies.yml

# Or use GitHub Actions
# Go to Actions → Test Policies → Run workflow
# Select: validate-only
```

### Dry Run Test

```bash
# Manual testing locally
custodian run \
  -s output \
  --region us-east-1 \
  --dryrun \
  policies/sample-policies.yml

# Or use GitHub Actions
# Select: dry-run
```

### Live Test (Caution!)

```bash
# Only in dev/staging environments!
# GitHub Actions → Test Policies → live-test
```

---

## 📝 Workflow Artifacts

Each workflow generates artifacts:

### Deploy Infrastructure:
- `cloud-custodian-layer` - Lambda layer zip
- `layer-build-report` - Build details
- `terraform-plan-{env}` - Terraform plan output
- `deployment-summary-{env}` - Deployment report

### Test Policies:
- `validation-report-{policy}` - Validation results
- `dryrun-results-{policy}` - Dry-run outputs
- `live-test-results-{policy}` - Live test results

Access artifacts: `Actions → Workflow run → Artifacts section`

---

## 🔍 Monitoring Deployments

### View Logs

```bash
# Lambda function logs
aws logs tail /aws/lambda/cloud-custodian-executor-dev --follow

# Terraform state
aws s3 ls s3://my-terraform-state-bucket/cloud-custodian/
```

### Check Deployment Status

```bash
# Lambda function
aws lambda get-function --function-name cloud-custodian-executor-dev

# EventBridge rule
aws events describe-rule --name cloud-custodian-schedule-dev

# CloudWatch logs
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/cloud-custodian
```

---

## 🐛 Troubleshooting

### Common Issues

#### 1. Authentication Failed
```
Error: Unable to assume role
```
**Solution:** Verify AWS_ROLE_ARN secret and OIDC provider setup

#### 2. Terraform State Lock
```
Error: Error acquiring the state lock
```
**Solution:** 
```bash
# Force unlock (use carefully!)
terraform force-unlock LOCK_ID
```

#### 3. Layer Too Large
```
Error: Layer size exceeds 250MB
```
**Solution:** Optimize build script, remove unnecessary packages

#### 4. Policy Validation Failed
```
Error: Invalid policy syntax
```
**Solution:** Run `custodian validate` locally first

---

## 📚 Additional Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [AWS OIDC for GitHub Actions](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [Terraform GitHub Actions](https://developer.hashicorp.com/terraform/tutorials/automation/github-actions)
- [Cloud Custodian Documentation](https://cloudcustodian.io/)

---

## 🔄 Workflow Updates

To update workflows:

1. Edit workflow files in `.github/workflows/`
2. Test changes in a feature branch
3. Create PR to `develop`
4. After testing, merge to `main`

---

## 💡 Best Practices

1. ✅ Always test policies with `validate-only` first
2. ✅ Use `dry-run` before live testing
3. ✅ Test in `dev` environment before production
4. ✅ Use environment protection rules for prod
5. ✅ Monitor CloudWatch Logs after deployment
6. ✅ Keep secrets encrypted in GitHub
7. ✅ Use OIDC instead of access keys when possible
8. ✅ Tag releases for production deployments

---

## 📞 Support

For issues or questions:
- Check workflow run logs in GitHub Actions
- Review CloudWatch Logs in AWS Console
- Consult the main README.md
- Check deployment artifacts
