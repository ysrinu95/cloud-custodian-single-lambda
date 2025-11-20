# GitHub Actions Workflow Setup

This guide explains how to set up GitHub Actions workflows for automated deployment and testing of the cross-account Cloud Custodian infrastructure.

---

## Prerequisites

1. **GitHub Repository** with admin access
2. **AWS Accounts**:
   - Central account (your main account)
   - Member account (created via Organizations)
3. **AWS OIDC Identity Provider** configured in your AWS account
4. **IAM Role** with trust relationship to GitHub Actions

---

## AWS OIDC Setup (Required)

### Step 1: Create OIDC Identity Provider in AWS

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

### Step 2: Create IAM Role for GitHub Actions

Create a trust policy file (`github-actions-trust-policy.json`):

```json
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
          "token.actions.githubusercontent.com:sub": "repo:YOUR_GITHUB_ORG/YOUR_REPO:*"
        }
      }
    }
  ]
}
```

Create the role:

```bash
aws iam create-role \
  --role-name GitHubActions-CloudCustodian-Role \
  --assume-role-policy-document file://github-actions-trust-policy.json

# Attach necessary permissions
aws iam attach-role-policy \
  --role-name GitHubActions-CloudCustodian-Role \
  --policy-arn arn:aws:iam::aws:policy/PowerUserAccess
```

---

## GitHub Secrets Configuration

### Required Secrets

Navigate to: `Settings` → `Secrets and variables` → `Actions` → `New repository secret`

| Secret Name | Description | Example Value |
|-------------|-------------|---------------|
| `AWS_ACCOUNT_ID` | Central account AWS account ID | `172327596604` |
| `MEMBER_ACCOUNT_ID` | Member AWS account ID | `123456789012` |
| `POLICY_BUCKET_NAME` | S3 bucket for policies (optional) | `custodian-policies-172327596604` |
| `TERRAFORM_STATE_BUCKET` | S3 bucket for Terraform state (optional) | `terraform-state-172327596604` |

### Optional Secrets

| Secret Name | Description | When to Use |
|-------------|-------------|-------------|
| `CENTRAL_ACCOUNT_ID` | Central account ID | For destroy operations |

---

## Workflow Files

### 1. deploy-cross-account.yml

**Purpose**: Deploy infrastructure to central and member accounts

**Triggers**:
- Push to `main` branch (auto-deploy central account)
- Pull request (validation only)
- Manual workflow dispatch (flexible deployment)

**Manual Trigger Options**:

| Option | Values | Description |
|--------|--------|-------------|
| `environment` | `central`, `member`, `both` | Which account to deploy |
| `action` | `plan`, `apply`, `destroy` | Terraform action to perform |
| `member_account_id` | Account ID | Member account (overrides secret) |

**Jobs**:
1. **validate** - Validate Python code and policy files
2. **build-lambda** - Build Lambda deployment package
3. **deploy-central-account** - Deploy EventBridge bus, Lambda, IAM
4. **deploy-member-account** - Deploy EventBridge rule, IAM role
5. **test-deployment** - Test cross-account connectivity
6. **upload-policies** - Upload policy files to S3
7. **destroy** - Destroy infrastructure (manual only)

### 2. test-cross-account.yml

**Purpose**: Test cross-account event forwarding and remediation

**Triggers**: Manual workflow dispatch only

**Manual Trigger Options**:

| Option | Values | Description |
|--------|--------|-------------|
| `test_type` | `event-forwarding`, `ec2-remediation`, `s3-remediation`, `all` | Type of test |
| `member_account_id` | Account ID | Member account to test |

**Jobs**:
1. **test-event-forwarding** - Verify events reach central account
2. **test-ec2-remediation** - Test EC2 public instance termination
3. **test-s3-remediation** - Test S3 public bucket remediation
4. **summary** - Generate test results summary

---

## Setup Steps

### Step 1: Configure GitHub Secrets

```bash
# Get your AWS credentials
aws configure list

# Get member account ID from the creation script output
cat cross-account-implementation/scripts/member-account-config.json | jq -r '.member_account_id'
```

Add these to GitHub Secrets:
1. Go to your repository → Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Add each required secret

### Step 2: Update Workflow Files (if needed)

The workflows are pre-configured, but you may want to customize:

**Region** (if not us-east-1):
```yaml
env:
  AWS_REGION: ap-south-1  # Change to your region
```

**Terraform version**:
```yaml
env:
  TERRAFORM_VERSION: 1.6.0  # Update if needed
```

### Step 3: Test Locally First

Before using GitHub Actions, test manually:

```bash
# Validate Python code
cd cross-account-implementation/src
python -m py_compile *.py

# Validate policies
cd ../policies
for file in *.yml; do python -c "import yaml; yaml.safe_load(open('$file'))"; done

# Build Lambda package
cd ../src
pip install c7n c7n-mailer -t package/
cp *.py package/
cd package && zip -r ../lambda-function.zip .
```

### Step 4: Push to GitHub

```bash
cd cross-account-implementation
git add .github/workflows/
git commit -m "Add GitHub Actions workflows for cross-account deployment"
git push origin main
```

This will trigger the validation and central account deployment automatically.

---

## Usage Examples

### Example 1: Deploy Central Account Only

**Manual Workflow Dispatch**:
1. Go to Actions tab → Deploy Cross-Account Infrastructure
2. Click "Run workflow"
3. Select:
   - Environment: `central`
   - Action: `apply`
4. Click "Run workflow"

**Via GitHub CLI**:
```bash
gh workflow run deploy-cross-account.yml \
  -f environment=central \
  -f action=apply
```

### Example 2: Deploy Both Accounts

```bash
gh workflow run deploy-cross-account.yml \
  -f environment=both \
  -f action=apply \
  -f member_account_id=123456789012
```

### Example 3: Plan Changes (Preview)

```bash
gh workflow run deploy-cross-account.yml \
  -f environment=both \
  -f action=plan \
  -f member_account_id=123456789012
```

### Example 4: Test EC2 Remediation

```bash
gh workflow run test-cross-account.yml \
  -f test_type=ec2-remediation \
  -f member_account_id=123456789012
```

### Example 5: Run All Tests

```bash
gh workflow run test-cross-account.yml \
  -f test_type=all \
  -f member_account_id=123456789012
```

### Example 6: Destroy Infrastructure

```bash
gh workflow run deploy-cross-account.yml \
  -f environment=both \
  -f action=destroy \
  -f member_account_id=123456789012
```

---

## Workflow Behavior

### Automatic Triggers

| Event | Workflow | Action |
|-------|----------|--------|
| Push to `main` | deploy-cross-account.yml | Deploy central account + upload policies |
| Pull Request | deploy-cross-account.yml | Validate only (no deployment) |

### Manual Triggers

All other operations require manual workflow dispatch via:
- GitHub UI: Actions tab → Select workflow → Run workflow
- GitHub CLI: `gh workflow run <workflow-name>`
- GitHub API: REST API call

---

## Monitoring Workflow Execution

### Via GitHub UI

1. Go to **Actions** tab
2. Click on the workflow run
3. View job logs and artifacts

### Via GitHub CLI

```bash
# List recent workflow runs
gh run list --workflow=deploy-cross-account.yml

# View specific run
gh run view <RUN_ID>

# Watch live logs
gh run watch <RUN_ID>

# Download artifacts
gh run download <RUN_ID>
```

### Check Terraform State

After successful deployment, download artifacts:
1. Go to workflow run → Artifacts
2. Download `central-account-state` or `member-account-state`
3. Extract and view `outputs.json`

---

## Troubleshooting

### Issue 1: "AWS credentials not found"

**Solution**: Verify GitHub secrets are set correctly
```bash
# Test locally
aws sts get-caller-identity
```

### Issue 2: "AssumeRole failed"

**Problem**: Cannot assume role in member account

**Solution**: 
1. Ensure member account has `OrganizationAccountAccessRole`
2. Verify trust policy allows central account

```bash
# Check role in member account
aws iam get-role --role-name OrganizationAccountAccessRole --profile member-test
```

### Issue 3: "Terraform state locked"

**Problem**: Previous run didn't complete

**Solution**:
1. Wait for lock to expire (15 minutes)
2. Or manually unlock (if using remote state):
```bash
terraform force-unlock <LOCK_ID>
```

### Issue 4: "Lambda package too large"

**Problem**: Lambda package exceeds size limit

**Solution**: Optimize package size
```bash
# Remove unnecessary files
cd package
find . -type d -name "tests" -exec rm -rf {} +
find . -type d -name "__pycache__" -exec rm -rf {} +
```

---

## Security Best Practices

### 1. Use OIDC Instead of Long-lived Credentials (Advanced)

Configure GitHub Actions to use OpenID Connect:

```yaml
permissions:
  id-token: write
  contents: read

steps:
  - name: Configure AWS credentials
    uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: arn:aws:iam::172327596604:role/GitHubActionsRole
      aws-region: us-east-1
```

### 2. Limit Secret Access

- Use environment secrets for production
- Require manual approval for deployments
- Enable branch protection rules

### 3. Audit Workflow Runs

- Review workflow logs regularly
- Monitor AWS CloudTrail for actions
- Set up notifications for failures

---

## Cost Considerations

### GitHub Actions Usage

| Resource | Free Tier | Cost After Free Tier |
|----------|-----------|---------------------|
| Linux runners | 2,000 minutes/month | $0.008/minute |
| Storage | 500 MB | $0.008/MB/day |
| Artifacts | 10 GB transfer | $0.50/GB |

### Typical Usage

- Deploy workflow: ~5-10 minutes
- Test workflow: ~5-8 minutes
- Monthly cost: **$0** (within free tier for small teams)

---

## Next Steps

After setting up GitHub Actions:

1. ✅ **Test the deployment workflow**
   ```bash
   gh workflow run deploy-cross-account.yml -f environment=central -f action=plan
   ```

2. ✅ **Deploy infrastructure**
   ```bash
   gh workflow run deploy-cross-account.yml -f environment=both -f action=apply
   ```

3. ✅ **Run tests**
   ```bash
   gh workflow run test-cross-account.yml -f test_type=all
   ```

4. ✅ **Monitor execution**
   - Check Actions tab for status
   - Review CloudWatch logs in AWS
   - Verify resources in AWS Console

---

## Additional Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [AWS Actions for GitHub](https://github.com/aws-actions)
- [Terraform GitHub Actions](https://developer.hashicorp.com/terraform/tutorials/automation/github-actions)
