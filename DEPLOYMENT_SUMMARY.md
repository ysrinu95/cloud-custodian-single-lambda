# GuardDuty Real-Time Detection - Deployment Summary

## Overview
The Terraform configurations are ready to deploy real-time GuardDuty detection that triggers Lambda within seconds (not 15 minutes via SecurityHub).

## What Will Be Deployed

### Member Account (813185901390)
**File:** `cross-account-implementation/terraform/member-account/main.tf`

1. **EventBridge Rule: `forward-guardduty-to-central-prod`**
   - Captures: GuardDuty Finding events
   - Event Pattern: `{"source":["aws.guardduty"],"detail-type":["GuardDuty Finding"]}`
   - Target: Central account event bus (arn:aws:events:us-east-1:172327596604:event-bus/centralized-security-events)
   - State: ENABLED

2. **EventBridge Rule: `forward-securityhub-to-central-prod`** (Updated)
   - Removed Compliance.Status filter
   - Now captures ALL SecurityHub findings (compliance + threats)

3. **EventBridge Target: `central_bus_guardduty`**
   - Forwards GuardDuty findings to central account
   - Uses existing EventBridge IAM role

### Central Account (172327596604)
**File:** `cross-account-implementation/terraform/central-account/main.tf`

1. **EventBridge Rule: `cloud-custodian-cross-account-guardduty-prod`**
   - Listens on: centralized-security-events custom event bus
   - Captures: GuardDuty findings from member account (813185901390)
   - Event Pattern: `{"source":["aws.guardduty"],"account":["813185901390"],"detail-type":["GuardDuty Finding"]}`
   - State: ENABLED

2. **EventBridge Target: `lambda_cross_account_guardduty`**
   - Triggers: cloud-custodian-cross-account-executor-prod Lambda
   - On: GuardDuty findings

3. **Lambda Permission: `allow_eventbridge_cross_account_guardduty`**
   - Allows EventBridge to invoke Lambda for GuardDuty findings

4. **EventBridge Rules: SecurityHub rules** (Updated)
   - `custodian_local_securityhub_trigger` - Removed Compliance.Status filter
   - `custodian_cross_account_securityhub_trigger` - Removed Compliance.Status filter
   - Now capture all SecurityHub findings (not just compliance FAILED)

## Cloud Custodian Policies Ready

**File:** `aws-guardduty-findings-remediate.yml` (Already uploaded to S3)

1. **guardduty-findings-remediation**
   - Archives findings
   - Sends notifications for HIGH/CRITICAL severity

2. **guardduty-backdoor-ec2-isolation**
   - Quarantines EC2 instances with backdoor/C&C activity
   - Tags, isolates network, stops instance

3. **guardduty-cryptocurrency-ec2-termination**
   - Terminates EC2 instances doing crypto mining
   - Immediate termination with notification

4. **guardduty-unauthorized-iam-remediation**
   - Disables compromised IAM user access keys
   - Tags user as COMPROMISED

## Event Flow After Deployment

```
GuardDuty Finding (Member Account)
    ↓ (seconds)
EventBridge: forward-guardduty-to-central-prod (Member)
    ↓
EventBridge: centralized-security-events (Central)
    ↓
EventBridge: cloud-custodian-cross-account-guardduty-prod (Central)
    ↓
Lambda: cloud-custodian-cross-account-executor-prod
    ↓
Cloud Custodian Policy Execution
    ↓
Auto-Remediation (terminate/isolate/disable)
```

## Deployment Command

```bash
# Member Account
cd cross-account-implementation/terraform/member-account
terraform init
terraform plan
terraform apply

# Central Account
cd ../central-account
terraform init
terraform plan
terraform apply
```

## Testing After Deployment

```bash
# Generate GuardDuty sample finding
aws guardduty create-sample-findings \
  --detector-id 52cd128303789eb9a3b21ddaf2f5cc1b \
  --finding-types 'CryptoCurrency:EC2/BitcoinTool.B!DNS' \
  --region us-east-1

# Monitor Lambda logs (should trigger within seconds)
aws logs tail /aws/lambda/cloud-custodian-cross-account-executor-prod \
  --follow --region us-east-1
```

## Key Changes Summary

| Component | Change | Impact |
|-----------|--------|--------|
| Member EventBridge | Added GuardDuty rule | Real-time finding forwarding |
| Member EventBridge | Removed SecurityHub filter | Captures threat findings |
| Central EventBridge | Added GuardDuty rule | Triggers Lambda on GuardDuty findings |
| Central EventBridge | Removed SecurityHub filters | Captures all finding types |
| Lambda Permissions | Added GuardDuty permission | Allows GuardDuty event invocation |
| Policies | Created GuardDuty policies | Auto-remediation for threats |
| Policy Mapping | Added GuardDuty mappings | Routes findings to correct policies |

## Benefits

- ⚡ **Real-time**: Seconds instead of up to 15 minutes
- 🎯 **Direct**: GuardDuty → Lambda (no SecurityHub delay)
- 🔒 **Comprehensive**: Backdoor, crypto mining, compromised credentials
- 🤖 **Automated**: Quarantine, terminate, disable - all automatic
- 📊 **Dual Path**: Still captures SecurityHub findings for compliance

## Files Modified (Ready to Deploy)

- ✅ `cross-account-implementation/terraform/member-account/main.tf`
- ✅ `cross-account-implementation/terraform/central-account/main.tf`
- ✅ `cross-account-implementation/policies/aws-guardduty-findings-remediate.yml`
- ✅ `config/policy-mapping.json`
- ✅ All files uploaded to S3
- ✅ All files committed to git

## Next Action

**Run your Terraform pipeline to apply these changes!**

Once deployed, GuardDuty findings will trigger Lambda within seconds for instant threat response.
