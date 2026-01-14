# SES Email Identity Setup for Gmail

## Overview

The Cloud Custodian infrastructure has been updated to use **email identity verification** instead of domain verification for AWS SES. This allows you to send emails from your Gmail address (`ysrinu95@gmail.com`) without needing to own a domain.

## What Changed

### 1. Terraform Configuration Updates

**File: `terraform/central/cloud-custodian.tf`**

- **Replaced**: Domain-based SES resources (domain identity, Route53 records, DKIM, SPF, DMARC)
- **Added**: Simple email identity resource (`aws_ses_email_identity`)
- **Updated**: IAM policies to reference the new email identity
- **Removed**: All DNS-related resources (Route53 zone, verification records, MX records)

### 2. Configuration File Updates

**File: `c7n/config/mailer.yml`**
- Changed `from_address` from `ysrinu95@gmail.com` to `ysrinu95@gmail.com`

**File: `terraform/central/cloud-custodian.tf`**
- Changed `mailer_from_address` variable default from `ysrinu95@gmail.com` to `ysrinu95@gmail.com`

## Gmail Domain Verification - NOT Required

**Important**: You **cannot** verify the `gmail.com` domain in AWS SES because:
- Domain verification requires DNS control (TXT and CNAME records)
- You don't own the `gmail.com` domain (Google does)
- Gmail addresses must be verified individually

## Email Verification Process

After deploying the Terraform infrastructure, you must verify the email address:

### Step 1: Deploy Infrastructure

```bash
cd terraform/central
terraform init
terraform apply
```

### Step 2: Check Gmail Inbox

1. Open the Gmail inbox for `ysrinu95@gmail.com`
2. Look for an email from `no-reply-aws@amazon.com` with subject: **"Amazon SES Email Address Verification Request"**
3. The email will arrive within a few minutes of Terraform deployment

### Step 3: Verify Email

Click the verification link in the email. Example:
```
https://email-verification.us-east-1.amazonaws.com/verify?...
```

### Step 4: Confirm Verification

Check verification status via AWS CLI:
```bash
aws ses get-identity-verification-attributes --identities ysrinu95@gmail.com
```

Expected output when verified:
```json
{
    "VerificationAttributes": {
        "ysrinu95@gmail.com": {
            "VerificationStatus": "Success"
        }
    }
}
```

## SES Sandbox Limitations

By default, AWS SES operates in **Sandbox Mode** with these restrictions:

### Sending Limits
- Maximum 200 emails per 24 hours
- Maximum 1 email per second
- Can only send TO verified email addresses

### Moving to Production Access

To send emails to any recipient, request production access:

1. **AWS Console** → **SES** → **Account dashboard** → **Request production access**
2. Complete the form:
   - **Use case**: Cloud security notifications
   - **Website URL**: (if applicable)
   - **Description**: Automated cloud governance notifications via Cloud Custodian
   - **Bounce/complaint handling**: Describe your process

3. AWS typically approves within 24 hours

## Configuration Summary

| Setting | Old Value | New Value |
|---------|-----------|-----------|
| SES Type | Domain Identity | Email Identity |
| Domain/Email | central.ctkube.com | ysrinu95@gmail.com |
| DNS Required | Yes (TXT, CNAME, MX) | No |
| Verification | Automatic (Route53) | Manual (email link) |
| DKIM Setup | Yes | Not available for email identities |

## Testing Email Notifications

After verification, test the mailer:

```bash
# Deploy test policy
cd c7n
custodian run -s output policies/test-mailer-notification.yml
```

## Troubleshooting

### Email Not Received

1. Check spam/junk folder
2. Verify deployment completed:
   ```bash
   terraform output ses_email_verification_status
   ```

3. Resend verification email:
   ```bash
   aws ses verify-email-identity --email-address ysrinu95@gmail.com
   ```

### Send Email Failed

Check SES verification status:
```bash
aws ses list-identities --identity-type EmailAddress
aws ses get-identity-verification-attributes --identities ysrinu95@gmail.com
```

### Bounce/Complaint Notifications

Gmail addresses may have higher bounce rates. Consider:
- Moving to a custom domain for production
- Setting up bounce/complaint SNS topics
- Monitoring SES sending statistics

## Production Recommendations

For production use, consider:

1. **Use a Custom Domain**
   - Better deliverability
   - DKIM/SPF/DMARC support
   - Professional appearance

2. **Configure SNS Bounce/Complaint Handling**
   ```hcl
   resource "aws_ses_configuration_set" "main" {
     name = "custodian-mailer"
   }
   ```

3. **Set Up SES Sending Statistics**
   - Monitor reputation
   - Track bounces/complaints
   - Alert on issues

## References

- [AWS SES Email Verification](https://docs.aws.amazon.com/ses/latest/dg/verify-email-addresses.html)
- [SES Sandbox Mode](https://docs.aws.amazon.com/ses/latest/dg/request-production-access.html)
- [SES Sending Limits](https://docs.aws.amazon.com/ses/latest/dg/manage-sending-quotas.html)
