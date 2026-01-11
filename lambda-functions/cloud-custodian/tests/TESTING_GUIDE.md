# Security Hub Notification Testing Guide

## Problem Statement

The Security Hub notification email shows unrendered Jinja2 template syntax instead of actual finding data:
```
**Severity:** {{ event.detail.findings[0].Severity.Label or "High" }}
**Compliance:** {{ event.detail.findings[0].Compliance.Status or "FAILED" }}
```

## Root Cause

The `event` object containing Security Hub finding data is not being passed correctly through the notification pipeline. We need to:
1. Understand what Cloud Custodian actually writes to SQS
2. Verify the SQS message structure contains the event data
3. Ensure realtime_notifier receives and uses the event data in Jinja2 templates

## Testing Approach

### Step 1: Capture Real SQS Message Structure

**Via Jenkins (Recommended):**
1. Go to Jenkins job: `cloud-custodian-demo`
2. Select scenario: `capture-sqs-message-structure`
3. Click "Build with Parameters"
4. This will:
   - Invoke Lambda with Security Hub test event
   - Cloud Custodian processes event and writes to SQS
   - Realtime notifier logs the exact SQS message structure
5. Check CloudWatch Logs:
   - Log Group: `/aws/lambda/cloud-custodian-cross-account-executor`
   - Search for: `RAW SQS MESSAGE BODY` or `DECODED CUSTODIAN DATA STRUCTURE`
   - Copy the JSON structure

**Via AWS CLI:**
```bash
# 1. Invoke Lambda with test event
aws lambda invoke \
    --function-name cloud-custodian-cross-account-executor \
    --payload file://terraform/ad-hoc/lambda_functions/cloud-custodian/tests/data/securityhub.json \
    --region us-east-1 \
    /tmp/response.json

# 2. Wait 10 seconds for processing
sleep 10

# 3. Check CloudWatch Logs
aws logs tail /aws/lambda/cloud-custodian-cross-account-executor \
    --since 5m \
    --follow \
    --region us-east-1
```

### Step 2: Save Real SQS Message Format

Once you capture the SQS message from CloudWatch logs:

```bash
# Save the decoded message structure
cat > terraform/ad-hoc/lambda_functions/cloud-custodian/tests/data/real_sqs_message.json << 'EOF'
{
  "policy": {...},
  "account": "...",
  "region": "...",
  "action": {...},
  "resources": [...],
  "event": {...}  # <-- This is the critical part!
}
EOF
```

### Step 3: Run Unit Tests

**Via Jenkins:**
1. Go to Jenkins job: `cloud-custodian-demo`
2. Select scenario: `test-securityhub-notification`
3. Click "Build with Parameters"
4. Tests will:
   - Load Security Hub test event
   - Simulate Cloud Custodian SQS message
   - Test Jinja2 template rendering
   - Validate email content generation

**Locally (if needed):**
```bash
cd terraform/ad-hoc/lambda_functions/cloud-custodian/tests

# Create virtual environment
python3 -m venv test_venv
source test_venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Run tests
pytest test_securityhub_notification.py -v -s
```

## What the Tests Validate

1. ✅ **Event Structure**: Security Hub event has required fields
2. ✅ **Jinja2 Rendering**: Template renders with `event.detail.findings[0]...` syntax
3. ✅ **No Unrendered Syntax**: Output has no `{{ }}` template markers
4. ✅ **Actual Data**: Real Security Hub values (CRITICAL, FAILED, etc.) appear
5. ✅ **Message Encoding**: SQS message encodes/decodes correctly
6. ✅ **Complete Flow**: End-to-end from SQS to SNS notification

## Expected vs Actual Behavior

### Expected (What Should Happen)
```
**Severity:** CRITICAL
**Compliance:** FAILED
**Status:** NEW
**Title:** Config.1 AWS Config should be enabled
```

### Actual (Current Problem)
```
**Severity:** {{ event.detail.findings[0].Severity.Label or "High" }}
**Compliance:** {{ event.detail.findings[0].Compliance.Status or "FAILED" }}
```

## Key Investigation Points

1. **Does Cloud Custodian include `event` in SQS message?**
   - Check: `p.data['event']` in cross_account_executor.py
   - Verify: Cloud Custodian's notify action serializes p.data to SQS

2. **Is the event structure correct?**
   - Should be: Full EventBridge event with `detail.findings[0]...`
   - Not just: The `detail` portion

3. **Does realtime_notifier receive the event?**
   - Check: `custodian_data.get('event')` in realtime_notifier.py
   - Verify: Event is passed to Jinja2 template context

## Debug Logging Added

The Lambda now logs:
- 🔍 **RAW SQS MESSAGE BODY**: Base64+gzip encoded message
- 📋 **DECODED CUSTODIAN DATA**: Full JSON structure after decoding
- 📋 **Event Context**: Whether event field exists and its structure
- ⚠️ **Missing Event**: Warning if event is not in custodian_data

## Files Modified

1. **realtime_notifier.py** (v41)
   - Added extensive SQS message logging
   - Log raw message body (first 500 chars)
   - Log decoded JSON structure (first 2000 chars)
   - Log event field details if present

2. **cross_account_executor.py** (v38)
   - Set `p.data['event'] = raw_event` (full event, not just detail)
   - This ensures Cloud Custodian has event to write to SQS

3. **cloud-custodian-demo.groovy**
   - Added `capture-sqs-message-structure` scenario
   - Added `test-securityhub-notification` scenario
   - Automated testing from Jenkins

4. **test_securityhub_notification.py**
   - Comprehensive unit tests
   - Tests Jinja2 rendering with event context
   - Validates complete notification flow

## Next Steps

1. **Deploy v41**: `terraform apply` in cloud-custodian directory
2. **Capture Real Data**: Run `capture-sqs-message-structure` scenario
3. **Analyze Logs**: Check if `event` field is in custodian_data
4. **Update Tests**: Use real SQS message format in test fixtures
5. **Fix Issues**: Based on what we find in the logs

## Troubleshooting

### If event is NOT in SQS message:
- Cloud Custodian's notify action may not serialize `p.data['event']`
- Solution: Store event data in resource metadata or use custom notify action

### If event IS in SQS but wrong structure:
- Check if we're storing full event vs just detail portion
- Verify template expects correct structure

### If event is in SQS but template doesn't render:
- Check Jinja2 template context in realtime_notifier
- Verify event is passed to `Template.render(**context)`

## Contact

For questions or issues, check:
- CloudWatch Logs: `/aws/lambda/cloud-custodian-cross-account-executor`
- Jenkins Job: `cloud-custodian-demo`
- Test Data: `terraform/ad-hoc/lambda_functions/cloud-custodian/tests/data/securityhub.json`
