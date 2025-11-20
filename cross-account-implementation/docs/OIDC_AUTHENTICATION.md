# OIDC Authentication for GitHub Actions

This document explains how to set up secure, keyless authentication between GitHub Actions and AWS using OpenID Connect (OIDC).

---

## Why OIDC Instead of Access Keys?

### Security Benefits

✅ **No Long-Lived Credentials**: No access keys stored in GitHub Secrets  
✅ **Automatic Rotation**: Temporary credentials that expire automatically  
✅ **Least Privilege**: Fine-grained permissions per repository  
✅ **Audit Trail**: CloudTrail logs show which GitHub workflow assumed the role  
✅ **No Secret Management**: No need to rotate or manage static credentials  

### How It Works

```
GitHub Actions Workflow
    ↓ (Requests temporary credentials)
AWS STS (Security Token Service)
    ↓ (Validates GitHub OIDC token)
IAM OIDC Provider
    ↓ (Checks trust policy)
IAM Role for GitHub Actions
    ↓ (Returns temporary credentials)
GitHub Actions Workflow
    ↓ (Uses credentials for 1 hour)
AWS Resources
```

---

## Setup Instructions

### Step 1: Create OIDC Identity Provider in AWS

This registers GitHub's OIDC provider with your AWS account:

```bash
# Get your AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account ID: $AWS_ACCOUNT_ID"

# Create OIDC provider
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1

echo "✅ OIDC Provider created"
```

**Verify it was created**:
```bash
aws iam list-open-id-connect-providers
```

### Step 2: Create IAM Trust Policy

This policy allows GitHub Actions from your specific repository to assume the role:

```bash
cat > github-actions-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
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
    }
  ]
}
EOF

echo "✅ Trust policy created"
```

**Understanding the trust policy**:
- `Federated`: Points to the OIDC provider created in Step 1
- `token.actions.githubusercontent.com:aud`: Must be `sts.amazonaws.com`
- `token.actions.githubusercontent.com:sub`: Restricts to your specific repository
  - Format: `repo:OWNER/REPO:*`
  - The `*` allows any branch/tag to use the role

### Step 3: Create IAM Role

```bash
# Create the role
aws iam create-role \
  --role-name GitHubActions-CloudCustodian-Role \
  --assume-role-policy-document file://github-actions-trust-policy.json \
  --description "Role for GitHub Actions to deploy Cloud Custodian infrastructure"

echo "✅ IAM Role created"
```

### Step 4: Attach Permissions

**Option 1: Use AWS Managed Policy (Quick Start)**:
```bash
aws iam attach-role-policy \
  --role-name GitHubActions-CloudCustodian-Role \
  --policy-arn arn:aws:iam::aws:policy/PowerUserAccess

echo "✅ PowerUserAccess policy attached"
```

**Option 2: Create Custom Policy (Recommended for Production)**:
```bash
cat > cloudcustodian-deploy-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "lambda:*",
        "events:*",
        "iam:GetRole",
        "iam:PassRole",
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "s3:*",
        "logs:*",
        "cloudformation:*",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSubnets",
        "ec2:DescribeVpcs"
      ],
      "Resource": "*"
    }
  ]
}
EOF

aws iam put-role-policy \
  --role-name GitHubActions-CloudCustodian-Role \
  --policy-name CloudCustodianDeploymentPolicy \
  --policy-document file://cloudcustodian-deploy-policy.json

echo "✅ Custom deployment policy attached"
```

### Step 5: Configure GitHub Secrets

Add these secrets to your GitHub repository:

1. Go to: `https://github.com/ysrinu95/cloud-custodian-single-lambda/settings/secrets/actions`
2. Click "New repository secret"
3. Add:

| Secret Name | Value | Example |
|-------------|-------|---------|
| `AWS_ACCOUNT_ID` | Your AWS account ID | `172327596604` |
| `MEMBER_ACCOUNT_ID` | Member account ID | `123456789012` |

**Note**: You do NOT need to add `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` when using OIDC!

### Step 6: Update GitHub Actions Workflow

Your workflow should use this configuration:

```yaml
permissions:
  id-token: write  # Required for OIDC
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::${{ secrets.AWS_ACCOUNT_ID }}:role/GitHubActions-CloudCustodian-Role
          aws-region: us-east-1
      
      - name: Test AWS access
        run: aws sts get-caller-identity
```

---

## Verification

### Test 1: Verify OIDC Provider

```bash
aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
```

**Expected output**:
```json
{
    "Url": "https://token.actions.githubusercontent.com",
    "ClientIDList": ["sts.amazonaws.com"],
    "ThumbprintList": ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}
```

### Test 2: Verify IAM Role

```bash
aws iam get-role --role-name GitHubActions-CloudCustodian-Role
```

**Expected output** (trust policy):
```json
{
    "Role": {
        "AssumeRolePolicyDocument": {
            "Statement": [{
                "Effect": "Allow",
                "Principal": {
                    "Federated": "arn:aws:iam::172327596604:oidc-provider/token.actions.githubusercontent.com"
                },
                "Action": "sts:AssumeRoleWithWebIdentity"
            }]
        }
    }
}
```

### Test 3: Verify Attached Policies

```bash
aws iam list-attached-role-policies --role-name GitHubActions-CloudCustodian-Role
```

### Test 4: Test from GitHub Actions

Push a workflow that runs:

```yaml
- name: Test OIDC Authentication
  run: |
    echo "Testing AWS access..."
    aws sts get-caller-identity
    echo "✅ OIDC authentication successful!"
```

---

## Troubleshooting

### Error: "Not authorized to perform sts:AssumeRoleWithWebIdentity"

**Cause**: Trust policy doesn't match the GitHub repository or OIDC provider not found

**Solution**:
1. Check the repository name in the trust policy matches exactly:
   ```bash
   aws iam get-role --role-name GitHubActions-CloudCustodian-Role \
     --query 'Role.AssumeRolePolicyDocument'
   ```
2. Verify the OIDC provider exists:
   ```bash
   aws iam list-open-id-connect-providers
   ```

### Error: "Token audience validation failed"

**Cause**: The `aud` claim in the OIDC token doesn't match

**Solution**: Ensure trust policy has:
```json
"StringEquals": {
  "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
}
```

### Error: "Access Denied" when deploying resources

**Cause**: IAM role doesn't have sufficient permissions

**Solution**: Attach necessary policies:
```bash
aws iam attach-role-policy \
  --role-name GitHubActions-CloudCustodian-Role \
  --policy-arn arn:aws:iam::aws:policy/PowerUserAccess
```

### Error: "id-token permission is required"

**Cause**: Workflow doesn't have `id-token: write` permission

**Solution**: Add to workflow:
```yaml
permissions:
  id-token: write
  contents: read
```

---

## Security Best Practices

### 1. Restrict to Specific Branches (Production)

Update trust policy to allow only main branch:

```json
"Condition": {
  "StringEquals": {
    "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
    "token.actions.githubusercontent.com:sub": "repo:ysrinu95/cloud-custodian-single-lambda:ref:refs/heads/main"
  }
}
```

### 2. Use Separate Roles for Different Environments

```bash
# Development role (more permissive)
aws iam create-role \
  --role-name GitHubActions-CloudCustodian-Dev

# Production role (restricted)
aws iam create-role \
  --role-name GitHubActions-CloudCustodian-Prod
```

### 3. Enable CloudTrail Logging

Monitor who assumes the role:

```bash
# Check CloudTrail logs
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceName,AttributeValue=GitHubActions-CloudCustodian-Role \
  --max-results 10
```

### 4. Set Role Session Duration

Limit the lifetime of temporary credentials:

```bash
aws iam update-role \
  --role-name GitHubActions-CloudCustodian-Role \
  --max-session-duration 3600  # 1 hour
```

### 5. Use External ID for Extra Security

Add an External ID to the trust policy:

```json
"Condition": {
  "StringEquals": {
    "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
    "sts:ExternalId": "github-actions-cloud-custodian"
  }
}
```

---

## Migration from Access Keys

### If You're Currently Using Access Keys:

**Before** (Old way):
```yaml
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
    aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
    aws-region: us-east-1
```

**After** (OIDC way):
```yaml
permissions:
  id-token: write

- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::${{ secrets.AWS_ACCOUNT_ID }}:role/GitHubActions-CloudCustodian-Role
    aws-region: us-east-1
```

**Steps to migrate**:
1. Complete Steps 1-4 above (create OIDC provider and role)
2. Update workflows to use `role-to-assume`
3. Test the new authentication method
4. Delete access keys from GitHub Secrets
5. Deactivate/delete the IAM access keys in AWS

---

## Cost Implications

**OIDC Authentication**: FREE ✅
- No additional costs for using OIDC
- No costs for temporary credentials from STS
- Reduced risk of credential exposure = lower security costs

**Access Keys**: Potential costs ⚠️
- Risk of leaked keys leading to unauthorized charges
- Overhead of credential rotation and management
- Audit and compliance costs

---

## Additional Resources

- [GitHub OIDC Documentation](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [AWS IAM OIDC Provider](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
- [AWS STS AssumeRoleWithWebIdentity](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRoleWithWebIdentity.html)
- [Configure AWS Credentials GitHub Action](https://github.com/aws-actions/configure-aws-credentials)

---

## Summary

✅ **Setup Complete Checklist**:
- [ ] OIDC provider created in AWS
- [ ] IAM role with trust policy created
- [ ] Permissions attached to role
- [ ] GitHub secrets configured (AWS_ACCOUNT_ID)
- [ ] Workflow updated with `permissions: id-token: write`
- [ ] Workflow tested successfully

**Next Steps**: Proceed to deploy your infrastructure using the secure OIDC authentication! 🚀
