# AWS Organizations Member Account Creation Guide

## Prerequisites

1. **AWS CLI** installed and configured
2. **AWS Account** with administrative access (this will be your central account)
3. **Unique email address** for the member account (can use Gmail +addressing: yourname+test1@gmail.com)
4. **jq** installed for JSON parsing

Install jq if needed:
```bash
# Ubuntu/Debian
sudo apt-get install jq

# macOS
brew install jq

# Windows (via Chocolatey)
choco install jq
```

---

## Quick Start - Automated Creation

### Step 1: Run the creation script

```bash
cd cross-account-implementation/scripts
chmod +x create-member-account.sh

./create-member-account.sh \
  "aws-custodian-member-test@example.com" \
  "Cloud Custodian Test Member"
```

**The script will**:
- ✅ Check if AWS Organizations is enabled (enable if needed)
- ✅ Create the member account
- ✅ Wait for creation to complete (2-5 minutes)
- ✅ Save account details to `member-account-config.json`
- ✅ Test access to the member account
- ✅ Display next steps

### Step 2: Configure AWS CLI profile

Add to `~/.aws/config`:
```ini
[profile member-test]
role_arn = arn:aws:iam::<MEMBER_ACCOUNT_ID>:role/OrganizationAccountAccessRole
source_profile = default
region = us-east-1
```

Replace `<MEMBER_ACCOUNT_ID>` with the ID from `member-account-config.json`.

### Step 3: Test access

```bash
aws sts get-caller-identity --profile member-test
```

Expected output:
```json
{
    "UserId": "AROA...:test-session",
    "Account": "<MEMBER_ACCOUNT_ID>",
    "Arn": "arn:aws:sts::<MEMBER_ACCOUNT_ID>:assumed-role/OrganizationAccountAccessRole/test-session"
}
```

---

## Manual Creation (Alternative)

If you prefer to create manually:

### Step 1: Enable AWS Organizations

```bash
aws organizations create-organization --feature-set ALL
```

### Step 2: Create member account

```bash
aws organizations create-account \
  --email "aws-custodian-member-test@example.com" \
  --account-name "Cloud Custodian Test Member" \
  --role-name "OrganizationAccountAccessRole"
```

Save the `CreateAccountRequestId` from the output.

### Step 3: Check creation status

```bash
aws organizations describe-create-account-status \
  --create-account-request-id <REQUEST_ID>
```

Wait until `State` is `SUCCEEDED`, then note the `AccountId`.

### Step 4: Configure CLI profile

Add to `~/.aws/config`:
```ini
[profile member-test]
role_arn = arn:aws:iam::<MEMBER_ACCOUNT_ID>:role/OrganizationAccountAccessRole
source_profile = default
region = us-east-1
```

---

## Email Address Options

You can use email aliasing to create multiple test accounts with a single email:

### Gmail
```
yourname+member1@gmail.com
yourname+member2@gmail.com
yourname+custodian-test@gmail.com
```

### Outlook/Hotmail
```
yourname+member1@outlook.com
yourname+member2@hotmail.com
```

### Custom Domain
```
member1@yourdomain.com
member2@yourdomain.com
```

All emails will arrive at your primary inbox, but AWS treats them as unique addresses.

---

## Verification Checklist

After creation, verify:

- [ ] Member account created successfully
- [ ] `member-account-config.json` file exists
- [ ] AWS CLI profile configured
- [ ] Can assume role: `aws sts get-caller-identity --profile member-test`
- [ ] Can list resources: `aws ec2 describe-instances --profile member-test`

---

## Common Issues & Solutions

### Issue 1: "AWSOrganizationsNotInUseException"
**Solution**: Enable AWS Organizations first:
```bash
aws organizations create-organization --feature-set ALL
```

### Issue 2: "Email address already in use"
**Solution**: Use a different email or email alias (+addressing)

### Issue 3: "Cannot assume role"
**Problem**: Role propagation delay
**Solution**: Wait 2-3 minutes and try again

### Issue 4: "ConstraintViolationException: You have exceeded the maximum number of accounts"
**Solution**: 
- Default limit: 10 accounts per organization
- Request increase: https://console.aws.amazon.com/support/home#/case/create?issueType=service-limit-increase

---

## Account Limits

| Limit | Default | Can Increase |
|-------|---------|--------------|
| Accounts per Organization | 10 | Yes (via support) |
| Account Creation Rate | 1 per minute | No |
| Organization Size | N/A | Unlimited |

---

## Cost Information

### Account Creation
- **Cost to create account**: $0.00 (FREE)
- **Monthly account fee**: $0.00 (FREE)
- **You only pay for resources used**

### AWS Free Tier (New Account)
Member accounts get their own 12-month free tier:
- **EC2**: 750 hours/month (t2.micro)
- **S3**: 5GB storage + 20,000 GET requests
- **Lambda**: 1M requests + 400,000 GB-seconds
- **CloudWatch**: 10 custom metrics + 5GB logs

---

## Security Best Practices

### 1. Enable CloudTrail immediately
```bash
aws cloudtrail create-trail \
  --name member-account-trail \
  --s3-bucket-name cloudtrail-bucket-name \
  --is-multi-region-trail \
  --profile member-test
```

### 2. Enable MFA for root user
1. Log in to member account root email
2. Go to Security Credentials
3. Enable MFA device

### 3. Create IAM admin user (don't use root)
```bash
aws iam create-user --user-name admin --profile member-test
aws iam attach-user-policy \
  --user-name admin \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess \
  --profile member-test
```

---

## Cleanup (When Done Testing)

### Close member account
```bash
# List accounts
aws organizations list-accounts

# Close account
aws organizations close-account --account-id <MEMBER_ACCOUNT_ID>
```

**Note**: Account closure takes 90 days. Account enters "suspended" state immediately.

---

## Next Steps

Once the member account is created:

1. ✅ **Deploy member account infrastructure**
   - EventBridge forwarding rule
   - IAM execution role for Cloud Custodian

2. ✅ **Deploy central account infrastructure**
   - EventBridge custom bus
   - Lambda executor
   - S3 bucket for policies

3. ✅ **Test cross-account event forwarding**

4. ✅ **Test cross-account remediation**
   - EC2 public instance termination
   - S3 public bucket remediation

Proceed to: [DEPLOYMENT_GUIDE.md](../DEPLOYMENT_GUIDE.md)
