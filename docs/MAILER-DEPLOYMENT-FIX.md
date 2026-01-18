# Cloud Custodian Mailer - Deployment Fix

## Root Cause
The `create_mailer_lambda` variable was set to `false` (default), so Terraform **never created**:
- ❌ EventBridge schedule rule (`cloud-custodian-mailer-schedule`)
- ❌ EventBridge target (Lambda trigger)
- ❌ Lambda permission for EventBridge
- ❌ CloudWatch Log Group

This is why:
1. Lambda exists but has never been invoked
2. No log group `/aws/lambda/cloud-custodian-mailer`
3. No emails being sent despite 12 messages in SQS queue

## Solution

### 1. Enable Mailer in Terraform

Created `terraform/central/terraform.tfvars`:
```hcl
create_mailer_lambda = true
mailer_from_address = "ysrinu95@gmail.com"
```

### 2. Deploy EventBridge Schedule

```bash
cd terraform/central

# Initialize if needed
terraform init

# Plan to see what will be created
terraform plan

# Apply to create EventBridge schedule and related resources
terraform apply

# Confirm the following resources are created:
# ✅ aws_cloudwatch_event_rule.mailer_schedule[0]
# ✅ aws_cloudwatch_event_target.mailer_schedule[0]
# ✅ aws_lambda_permission.allow_eventbridge_mailer[0]
# ✅ aws_cloudwatch_log_group.mailer_logs[0]
```

### 3. Verify Deployment

```bash
cd scripts
chmod +x validate-mailer-deployment.sh
./validate-mailer-deployment.sh us-east-1
```

Expected output:
```
✅ Lambda exists: cloud-custodian-mailer
✅ EventBridge rule exists: cloud-custodian-mailer-schedule
   State: ENABLED
   Schedule: rate(5 minutes)
✅ EventBridge target configured
✅ EventBridge has permission to invoke Lambda
✅ Log group exists: /aws/lambda/cloud-custodian-mailer
📬 12 messages waiting in queue
   Lambda should process within 5 minutes
```

### 4. Monitor Execution

```bash
# Watch Lambda logs (will show activity when schedule triggers)
aws logs tail /aws/lambda/cloud-custodian-mailer --follow --region us-east-1

# Check queue messages decreasing
watch -n 5 'aws sqs get-queue-attributes \
  --queue-url https://sqs.us-east-1.amazonaws.com/172327596604/aikyam-cloud-custodian-periodic-notifications \
  --attribute-names ApproximateNumberOfMessages \
  --region us-east-1 \
  --query "Attributes.ApproximateNumberOfMessages"'
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Every 5 Minutes                          │
│                                                             │
│   EventBridge Rule                                          │
│   (cloud-custodian-mailer-schedule)                        │
│   rate(5 minutes)                                          │
└────────────────────┬────────────────────────────────────────┘
                     │ Triggers
                     ▼
┌─────────────────────────────────────────────────────────────┐
│   Lambda: cloud-custodian-mailer                           │
│   - Polls SQS queue                                        │
│   - Reads policy violation messages                        │
│   - Sends emails via SES                                   │
└────────────────────┬────────────────────────────────────────┘
                     │ Reads from
                     ▼
┌─────────────────────────────────────────────────────────────┐
│   SQS Queue                                                 │
│   aikyam-cloud-custodian-periodic-notifications            │
│   - 12 messages waiting                                    │
│   - Sent by periodic policy executions                     │
└─────────────────────────────────────────────────────────────┘
```

## Timeline

1. **Periodic policies run** (GitHub Actions workflow) ✅
   - 14 policies executed successfully
   - 12 SQS messages sent to queue

2. **Messages waiting in SQS** ✅
   - Queue: `aikyam-cloud-custodian-periodic-notifications`
   - Status: 12 messages available

3. **EventBridge trigger MISSING** ❌
   - Expected: Lambda invoked every 5 minutes
   - Actual: Lambda NEVER invoked (no log group)
   - Reason: `create_mailer_lambda = false` in Terraform

4. **After Terraform apply** (PENDING)
   - EventBridge schedule created
   - Lambda will be invoked every 5 minutes
   - Queue messages will be processed
   - Emails will be sent

## Expected Behavior After Fix

- **First 5 minutes**: EventBridge triggers Lambda
- **Lambda execution**: Reads 12 messages from SQS
- **Email delivery**: 12 notification emails sent
- **Queue status**: 0 messages remaining
- **Log group**: `/aws/lambda/cloud-custodian-mailer` created with execution logs

## Troubleshooting

If emails still not received after Terraform apply:

1. **Check SES Configuration**:
   ```bash
   aws ses get-account-sending-enabled --region us-east-1
   aws ses list-verified-email-addresses --region us-east-1
   ```

2. **Check Lambda Logs**:
   ```bash
   aws logs tail /aws/lambda/cloud-custodian-mailer --region us-east-1
   ```

3. **Manually Trigger Lambda**:
   ```bash
   aws lambda invoke --function-name cloud-custodian-mailer \
     --region us-east-1 /tmp/output.json
   cat /tmp/output.json
   ```
