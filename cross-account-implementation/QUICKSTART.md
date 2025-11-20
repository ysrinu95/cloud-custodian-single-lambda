# Cross-Account Deployment Quick Start

This guide provides step-by-step instructions to deploy and test the cross-account Cloud Custodian infrastructure using GitHub Actions.

---

## 📋 Prerequisites Checklist

- [x] Member account created (ID: from `member-account-config.json`)
- [x] GitHub repository with code pushed
- [ ] GitHub secrets configured
- [ ] GitHub Actions workflows reviewed
- [ ] Ready to deploy!

---

## 🚀 Quick Deployment (6 Steps)

### Step 0: Setup AWS OIDC for GitHub Actions (10 minutes - One-time setup)

**This is required for secure, keyless authentication from GitHub Actions to AWS**

1. **Create OIDC Identity Provider in AWS**:
   ```bash
   aws iam create-open-id-connect-provider \
     --url https://token.actions.githubusercontent.com \
     --client-id-list sts.amazonaws.com \
     --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
   ```

2. **Create IAM role for GitHub Actions**:
   
   Create trust policy file:
   ```bash
   cat > github-trust-policy.json <<EOF
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Effect": "Allow",
       "Principal": {
         "Federated": "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):oidc-provider/token.actions.githubusercontent.com"
       },
       "Action": "sts:AssumeRoleWithWebIdentity",
       "Condition": {
         "StringEquals": {
           "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
         },
         "StringLike": {
           "token.actions.githubusercontent.com:sub": "repo:ysrinu95/cloud-custodian-single-lambda:*"
         }
       }
     }]
   }
   EOF
   ```

3. **Create the role and attach permissions**:
   ```bash
   aws iam create-role \
     --role-name GitHubActions-CloudCustodian-Role \
     --assume-role-policy-document file://github-trust-policy.json
   
   aws iam attach-role-policy \
     --role-name GitHubActions-CloudCustodian-Role \
     --policy-arn arn:aws:iam::aws:policy/PowerUserAccess
   ```

### Step 1: Configure GitHub Secrets (5 minutes)

1. **Get your AWS Account ID**:
   ```bash
   aws sts get-caller-identity --query Account --output text
   ```

2. **Get member account ID**:
   ```bash
   cat cross-account-implementation/scripts/member-account-config.json | jq -r '.member_account_id'
   ```

3. **Add secrets to GitHub**:
   - Go to: `https://github.com/ysrinu95/cloud-custodian-single-lambda/settings/secrets/actions`
   - Click "New repository secret" for each:

   | Name | Value | Where to find |
   |------|-------|---------------|
   | `AWS_ACCOUNT_ID` | Your AWS account ID | `aws sts get-caller-identity` |
   | `MEMBER_ACCOUNT_ID` | Member account ID | From member-account-config.json |
   | `TERRAFORM_STATE_BUCKET` | S3 bucket for state (optional) | Your bucket name |

### Step 2: Push Workflows to GitHub (2 minutes)

```bash
cd "/mnt/c/United Techno/Git Repos/cloud-custodian-single-lambda"

# Add workflow files
git add cross-account-implementation/.github/workflows/

# Commit
git commit -m "Add GitHub Actions workflows for cross-account deployment"

# Push (this will trigger validation automatically)
git push origin main
```

### Step 3: Deploy Central Account (10 minutes)

**Option A: Via GitHub UI**
1. Go to: Actions → Deploy Cross-Account Infrastructure
2. Click "Run workflow"
3. Select:
   - Branch: `main`
   - Environment: `central`
   - Action: `apply`
4. Click "Run workflow"

**Option B: Via GitHub CLI**
```bash
gh workflow run deploy-cross-account.yml \
  -f environment=central \
  -f action=apply
```

**Watch progress**:
```bash
gh run watch
```

### Step 4: Deploy Member Account (10 minutes)

**Get member account ID first**:
```bash
MEMBER_ACCOUNT_ID=$(cat cross-account-implementation/scripts/member-account-config.json | jq -r '.member_account_id')
echo "Member Account ID: $MEMBER_ACCOUNT_ID"
```

**Deploy via GitHub Actions**:
```bash
gh workflow run deploy-cross-account.yml \
  -f environment=member \
  -f action=apply \
  -f member_account_id=$MEMBER_ACCOUNT_ID
```

### Step 5: Test Deployment (5 minutes)

```bash
gh workflow run test-cross-account.yml \
  -f test_type=event-forwarding \
  -f member_account_id=$MEMBER_ACCOUNT_ID
```

---

## ✅ Verification Steps

### 1. Verify Central Account Resources

```bash
# Check EventBridge bus
aws events describe-event-bus --name centralized-security-events

# Check Lambda function
aws lambda get-function --function-name cloud-custodian-cross-account-executor

# Check S3 bucket
aws s3 ls | grep custodian-policies
```

### 2. Verify Member Account Resources

```bash
# Assume role in member account
aws sts assume-role \
  --role-arn "arn:aws:iam::$MEMBER_ACCOUNT_ID:role/OrganizationAccountAccessRole" \
  --role-session-name test-verification

# Use temporary credentials to check resources
# (Copy credentials from above output)

# Check EventBridge rule
aws events list-rules --profile member-test

# Check IAM role
aws iam get-role --role-name CloudCustodianExecutionRole --profile member-test
```

### 3. View GitHub Actions Results

```bash
# List workflow runs
gh run list --limit 5

# View specific run
gh run view <RUN_ID>

# Download artifacts (Terraform state)
gh run download <RUN_ID>
```

---

## 🧪 Testing Guide

### Test 1: Event Forwarding (2 minutes)

Verify events flow from member to central account:

```bash
gh workflow run test-cross-account.yml \
  -f test_type=event-forwarding \
  -f member_account_id=$MEMBER_ACCOUNT_ID

# Wait 30 seconds, then check logs
gh run watch
```

**Expected Result**: Lambda logs show received event from member account

### Test 2: EC2 Remediation (5 minutes)

Test automatic termination of EC2 with public IP:

```bash
gh workflow run test-cross-account.yml \
  -f test_type=ec2-remediation \
  -f member_account_id=$MEMBER_ACCOUNT_ID
```

**What happens**:
1. Creates EC2 instance with public IP in member account
2. CloudTrail logs RunInstances event
3. EventBridge forwards to central account
4. Lambda assumes role and executes policy
5. Instance is terminated
6. Email notification sent (if configured)

**Expected Result**: Instance terminated within 3-5 minutes

### Test 3: S3 Remediation (5 minutes)

Test automatic blocking of public S3 buckets:

```bash
gh workflow run test-cross-account.yml \
  -f test_type=s3-remediation \
  -f member_account_id=$MEMBER_ACCOUNT_ID
```

**What happens**:
1. Creates S3 bucket without public access blocks
2. CloudTrail logs CreateBucket event
3. EventBridge forwards to central account
4. Lambda assumes role and executes policy
5. Public access block is enabled
6. Email notification sent (if configured)

**Expected Result**: Public access blocks enabled within 3-5 minutes

### Test 4: Run All Tests (10 minutes)

```bash
gh workflow run test-cross-account.yml \
  -f test_type=all \
  -f member_account_id=$MEMBER_ACCOUNT_ID
```

---

## 📊 Monitoring

### Check Lambda Execution Logs

**Central Account**:
```bash
aws logs tail /aws/lambda/cloud-custodian-cross-account-executor --follow
```

**Filter for specific events**:
```bash
# EC2 events
aws logs tail /aws/lambda/cloud-custodian-cross-account-executor \
  --since 10m \
  --filter-pattern "RunInstances"

# S3 events
aws logs tail /aws/lambda/cloud-custodian-cross-account-executor \
  --since 10m \
  --filter-pattern "CreateBucket"
```

### Check EventBridge Metrics

```bash
# Central account - events received
aws cloudwatch get-metric-statistics \
  --namespace AWS/Events \
  --metric-name Invocations \
  --dimensions Name=RuleName,Value=cloud-custodian-cross-account-rule \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

### Check Lambda Metrics

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --dimensions Name=FunctionName,Value=cloud-custodian-cross-account-executor \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

---

## 🔧 Troubleshooting

### Issue 1: GitHub Actions Fails - "AWS credentials not found"

**Solution**:
```bash
# Verify secrets are set
gh secret list

# If missing, add them
gh secret set AWS_ACCESS_KEY_ID < <(echo "YOUR_ACCESS_KEY")
gh secret set AWS_SECRET_ACCESS_KEY < <(echo "YOUR_SECRET_KEY")
gh secret set MEMBER_ACCOUNT_ID < <(echo "$MEMBER_ACCOUNT_ID")
```

### Issue 2: "AssumeRole Access Denied"

**Problem**: Lambda cannot assume role in member account

**Solution**:
```bash
# Check trust policy in member account
aws iam get-role \
  --role-name CloudCustodianExecutionRole \
  --profile member-test \
  --query 'Role.AssumeRolePolicyDocument'

# Should show central account as trusted principal
```

### Issue 3: Events Not Forwarding

**Problem**: Events not reaching central account

**Solution**:
```bash
# Check EventBridge rule in member account
aws events describe-rule \
  --name forward-security-events-to-central \
  --profile member-test

# Check rule targets
aws events list-targets-by-rule \
  --rule forward-security-events-to-central \
  --profile member-test
```

### Issue 4: Lambda Execution Errors

**Check logs**:
```bash
aws logs tail /aws/lambda/cloud-custodian-cross-account-executor \
  --since 30m \
  --format short
```

**Common errors**:
- `AccessDenied`: Check IAM permissions
- `RoleNotFound`: Deploy member account infrastructure
- `ValidationException`: Check event format

---

## 📈 Cost Monitoring

### Current Deployment Cost

```bash
# Check Lambda invocations
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --dimensions Name=FunctionName,Value=cloud-custodian-cross-account-executor \
  --start-time $(date -u -d '30 days ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 86400 \
  --statistics Sum

# Estimated monthly cost (assuming 1000 invocations):
# Lambda: $0.00 (within free tier)
# EventBridge: $0.00 (within free tier)
# CloudWatch Logs: $0.00 (within free tier)
# Total: $0.00
```

---

## 🧹 Cleanup (Optional)

### Destroy All Resources

```bash
# Via GitHub Actions
gh workflow run deploy-cross-account.yml \
  -f environment=both \
  -f action=destroy \
  -f member_account_id=$MEMBER_ACCOUNT_ID

# Or manually via Terraform
cd cross-account-implementation/terraform/member-account
terraform destroy -auto-approve

cd ../central-account
terraform destroy -auto-approve
```

### Close Member Account (Optional)

```bash
aws organizations close-account \
  --account-id $MEMBER_ACCOUNT_ID
```

**Note**: Account closure takes 90 days and is irreversible.

---

## ✨ Next Steps

After successful deployment:

1. **Customize Policies**
   - Edit `cross-account-implementation/policies/*.yml`
   - Push changes (will auto-upload to S3)

2. **Add More Member Accounts**
   - Create additional member accounts
   - Update `member_account_ids` variable
   - Re-run deployment

3. **Enable Email Notifications**
   - Deploy mailer Lambda
   - Configure SES
   - Update policies with notify action

4. **Set Up Monitoring**
   - Create CloudWatch dashboards
   - Set up SNS alerts
   - Configure log insights

5. **Production Hardening**
   - Enable MFA for sensitive operations
   - Implement approval workflows
   - Set up backup/recovery procedures

---

## 📚 Reference Documentation

- [GITHUB_ACTIONS_SETUP.md](GITHUB_ACTIONS_SETUP.md) - Detailed workflow documentation
- [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) - Manual deployment guide
- [CROSS-ACCOUNT-ARCHITECTURE.md](../docs/CROSS-ACCOUNT-ARCHITECTURE.md) - Architecture deep dive
- [MEMBER_ACCOUNT_CREATION.md](MEMBER_ACCOUNT_CREATION.md) - Account creation guide

---

## 🆘 Getting Help

If you encounter issues:

1. Check workflow logs in GitHub Actions
2. Review CloudWatch logs in AWS
3. Verify IAM permissions
4. Check this troubleshooting guide
5. Review architecture documentation

**Common Commands**:
```bash
# View workflow status
gh run list --limit 5

# View detailed logs
gh run view <RUN_ID> --log

# Check AWS resources
aws cloudformation describe-stacks
aws lambda list-functions
aws events list-event-buses
```
