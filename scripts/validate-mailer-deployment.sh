#!/bin/bash

# Script to validate cloud-custodian-mailer deployment and configuration
# Checks EventBridge schedule, Lambda, SQS, and CloudWatch logs

set -e

REGION="${1:-us-east-1}"
LAMBDA_NAME="cloud-custodian-mailer"
SCHEDULE_RULE="cloud-custodian-mailer-schedule"
PERIODIC_QUEUE="aikyam-cloud-custodian-periodic-notifications"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Cloud Custodian Mailer - Deployment Validation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Region: $REGION"
echo "Expected Architecture:"
echo "  • EventBridge Schedule (rate: 5 minutes)"
echo "  • Lambda polls SQS queue when triggered"
echo "  • CloudWatch Logs: /aws/lambda/$LAMBDA_NAME"
echo ""

ISSUES_FOUND=0

# 1. Check Lambda Function
echo "1️⃣  Lambda Function"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

LAMBDA_CONFIG=$(aws lambda get-function-configuration --function-name "$LAMBDA_NAME" --region "$REGION" 2>&1)
if [ $? -ne 0 ]; then
  echo "❌ Lambda function not found: $LAMBDA_NAME"
  echo "$LAMBDA_CONFIG"
  ISSUES_FOUND=$((ISSUES_FOUND + 1))
  echo ""
else
  echo "✅ Lambda exists: $LAMBDA_NAME"
  
  LAMBDA_STATE=$(echo "$LAMBDA_CONFIG" | jq -r '.State')
  LAMBDA_RUNTIME=$(echo "$LAMBDA_CONFIG" | jq -r '.Runtime')
  LAMBDA_TIMEOUT=$(echo "$LAMBDA_CONFIG" | jq -r '.Timeout')
  LAMBDA_MEMORY=$(echo "$LAMBDA_CONFIG" | jq -r '.MemorySize')
  LAMBDA_UPDATED=$(echo "$LAMBDA_CONFIG" | jq -r '.LastModified')
  
  echo "   State: $LAMBDA_STATE"
  echo "   Runtime: $LAMBDA_RUNTIME"
  echo "   Timeout: ${LAMBDA_TIMEOUT}s"
  echo "   Memory: ${LAMBDA_MEMORY}MB"
  echo "   Last Modified: $LAMBDA_UPDATED"
  
  # Check environment variables
  QUEUE_URL=$(echo "$LAMBDA_CONFIG" | jq -r '.Environment.Variables.QUEUE_URL // "NOT_SET"')
  FROM_ADDRESS=$(echo "$LAMBDA_CONFIG" | jq -r '.Environment.Variables.FROM_ADDRESS // "NOT_SET"')
  LOG_LEVEL=$(echo "$LAMBDA_CONFIG" | jq -r '.Environment.Variables.LOG_LEVEL // "INFO"')
  
  echo ""
  echo "   Environment Variables:"
  echo "   • QUEUE_URL: $QUEUE_URL"
  echo "   • FROM_ADDRESS: $FROM_ADDRESS"
  echo "   • LOG_LEVEL: $LOG_LEVEL"
  
  if [ "$QUEUE_URL" == "NOT_SET" ]; then
    echo ""
    echo "   ⚠️  QUEUE_URL not configured in Lambda environment"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
  fi
  
  if [ "$FROM_ADDRESS" == "NOT_SET" ]; then
    echo ""
    echo "   ⚠️  FROM_ADDRESS not configured in Lambda environment"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
  fi
  
  echo ""
fi

# 2. Check EventBridge Schedule Rule
echo "2️⃣  EventBridge Schedule"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

RULE_CONFIG=$(aws events describe-rule --name "$SCHEDULE_RULE" --region "$REGION" 2>&1)
if [ $? -ne 0 ]; then
  echo "❌ EventBridge rule not found: $SCHEDULE_RULE"
  echo "$RULE_CONFIG"
  echo ""
  echo "   The Lambda will NOT run automatically!"
  echo "   Terraform should create: aws_cloudwatch_event_rule.mailer_schedule"
  ISSUES_FOUND=$((ISSUES_FOUND + 1))
  echo ""
else
  echo "✅ EventBridge rule exists: $SCHEDULE_RULE"
  
  RULE_STATE=$(echo "$RULE_CONFIG" | jq -r '.State')
  SCHEDULE=$(echo "$RULE_CONFIG" | jq -r '.ScheduleExpression')
  
  echo "   State: $RULE_STATE"
  echo "   Schedule: $SCHEDULE"
  
  if [ "$RULE_STATE" != "ENABLED" ]; then
    echo ""
    echo "   ⚠️  Rule is DISABLED - Lambda will not be triggered!"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
  fi
  
  if [ "$SCHEDULE" != "rate(5 minutes)" ]; then
    echo ""
    echo "   ⚠️  Unexpected schedule (expected: rate(5 minutes))"
  fi
  
  echo ""
fi

# 3. Check EventBridge Target
echo "3️⃣  EventBridge Target (Lambda)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

TARGETS=$(aws events list-targets-by-rule --rule "$SCHEDULE_RULE" --region "$REGION" 2>&1)
if [ $? -ne 0 ]; then
  echo "⚠️  Could not list targets for rule: $SCHEDULE_RULE"
  echo "$TARGETS"
  echo ""
else
  TARGET_COUNT=$(echo "$TARGETS" | jq '.Targets | length')
  
  if [ "$TARGET_COUNT" -eq 0 ]; then
    echo "❌ No targets configured for EventBridge rule"
    echo "   The schedule exists but won't trigger anything!"
    echo "   Terraform should create: aws_cloudwatch_event_target.mailer_schedule"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
    echo ""
  else
    echo "✅ EventBridge target configured"
    
    TARGET_ARN=$(echo "$TARGETS" | jq -r '.Targets[0].Arn')
    TARGET_ID=$(echo "$TARGETS" | jq -r '.Targets[0].Id')
    
    echo "   Target: $TARGET_ID"
    echo "   ARN: $TARGET_ARN"
    
    if [[ "$TARGET_ARN" != *"$LAMBDA_NAME"* ]]; then
      echo ""
      echo "   ⚠️  Target ARN doesn't match Lambda function name"
      ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
    echo ""
  fi
fi

# 4. Check Lambda Permission for EventBridge
echo "4️⃣  Lambda Invocation Permission"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

POLICY=$(aws lambda get-policy --function-name "$LAMBDA_NAME" --region "$REGION" 2>&1)
if [ $? -ne 0 ]; then
  echo "⚠️  Could not retrieve Lambda policy"
  echo "$POLICY"
  echo ""
else
  HAS_EVENTBRIDGE_PERMISSION=$(echo "$POLICY" | jq -r '.Policy' | jq 'fromjson | .Statement[] | select(.Principal.Service == "events.amazonaws.com") | .Sid' 2>/dev/null || echo "")
  
  if [ -z "$HAS_EVENTBRIDGE_PERMISSION" ]; then
    echo "❌ No permission for EventBridge to invoke Lambda"
    echo "   EventBridge schedule will fail to trigger Lambda!"
    echo "   Terraform should create: aws_lambda_permission.allow_eventbridge_mailer"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
    echo ""
  else
    echo "✅ EventBridge has permission to invoke Lambda"
    echo "   Statement ID: $HAS_EVENTBRIDGE_PERMISSION"
    echo ""
  fi
fi

# 5. Check CloudWatch Log Group
echo "5️⃣  CloudWatch Log Group"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

LOG_GROUP=$(aws logs describe-log-groups \
  --log-group-name-prefix "/aws/lambda/$LAMBDA_NAME" \
  --region "$REGION" \
  --query "logGroups[?logGroupName=='/aws/lambda/$LAMBDA_NAME']" 2>/dev/null || echo "[]")

LOG_GROUP_EXISTS=$(echo "$LOG_GROUP" | jq 'length > 0')

if [ "$LOG_GROUP_EXISTS" == "false" ]; then
  echo "⚠️  Log group does not exist: /aws/lambda/$LAMBDA_NAME"
  echo "   This confirms Lambda has NEVER been invoked"
  echo "   Terraform should create: aws_cloudwatch_log_group.mailer_logs"
  echo ""
else
  echo "✅ Log group exists: /aws/lambda/$LAMBDA_NAME"
  
  RETENTION=$(echo "$LOG_GROUP" | jq -r '.[0].retentionInDays // "Never expire"')
  CREATION=$(echo "$LOG_GROUP" | jq -r '.[0].creationTime // 0')
  SIZE_BYTES=$(echo "$LOG_GROUP" | jq -r '.[0].storedBytes // 0')
  
  if [ "$CREATION" != "0" ]; then
    CREATION_DATE=$(date -d @$((CREATION / 1000)) '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r $((CREATION / 1000)) '+%Y-%m-%d %H:%M:%S')
    echo "   Created: $CREATION_DATE"
  fi
  
  echo "   Retention: $RETENTION days"
  echo "   Size: $SIZE_BYTES bytes"
  
  # Check for recent log streams
  RECENT_STREAMS=$(aws logs describe-log-streams \
    --log-group-name "/aws/lambda/$LAMBDA_NAME" \
    --region "$REGION" \
    --order-by LastEventTime \
    --descending \
    --max-items 1 \
    --query 'logStreams[0].lastEventTime' \
    --output text 2>/dev/null || echo "0")
  
  if [ "$RECENT_STREAMS" != "0" ] && [ "$RECENT_STREAMS" != "None" ]; then
    LAST_EVENT=$(date -d @$((RECENT_STREAMS / 1000)) '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r $((RECENT_STREAMS / 1000)) '+%Y-%m-%d %H:%M:%S')
    echo "   Last Event: $LAST_EVENT"
    echo ""
    echo "   ✅ Lambda has been invoked recently"
  else
    echo ""
    echo "   ⚠️  No log streams found - Lambda may not be executing"
  fi
  echo ""
fi

# 6. Check SQS Queue
echo "6️⃣  SQS Queue Status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

QUEUE_URL=$(aws sqs get-queue-url --queue-name "$PERIODIC_QUEUE" --region "$REGION" --query 'QueueUrl' --output text 2>/dev/null || echo "")

if [ -z "$QUEUE_URL" ]; then
  echo "❌ Queue not found: $PERIODIC_QUEUE"
  ISSUES_FOUND=$((ISSUES_FOUND + 1))
  echo ""
else
  echo "✅ Queue exists: $PERIODIC_QUEUE"
  
  QUEUE_ATTRS=$(aws sqs get-queue-attributes --queue-url "$QUEUE_URL" --attribute-names All --region "$REGION")
  
  MSG_AVAILABLE=$(echo "$QUEUE_ATTRS" | jq -r '.Attributes.ApproximateNumberOfMessages // "0"')
  MSG_INFLIGHT=$(echo "$QUEUE_ATTRS" | jq -r '.Attributes.ApproximateNumberOfMessagesNotVisible // "0"')
  MSG_DELAYED=$(echo "$QUEUE_ATTRS" | jq -r '.Attributes.ApproximateNumberOfMessagesDelayed // "0"')
  
  echo "   Messages Available: $MSG_AVAILABLE"
  echo "   Messages In-Flight: $MSG_INFLIGHT"
  echo "   Messages Delayed: $MSG_DELAYED"
  
  if [ "$MSG_AVAILABLE" -gt 0 ]; then
    echo ""
    echo "   📬 $MSG_AVAILABLE messages waiting to be processed"
    echo "   Lambda should process these within 5 minutes"
  fi
  echo ""
fi

# 7. Check Recent Lambda Invocations
echo "7️⃣  Recent Lambda Activity (last 30 minutes)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

START_TIME=$(date -u -d '30 minutes ago' '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date -u -v-30M '+%Y-%m-%dT%H:%M:%S')
END_TIME=$(date -u '+%Y-%m-%dT%H:%M:%S')

INVOCATION_COUNT=$(aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --dimensions Name=FunctionName,Value="$LAMBDA_NAME" \
  --start-time "$START_TIME" \
  --end-time "$END_TIME" \
  --period 1800 \
  --statistics Sum \
  --region "$REGION" \
  --query 'Datapoints[0].Sum' \
  --output text 2>/dev/null || echo "0")

ERROR_COUNT=$(aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Errors \
  --dimensions Name=FunctionName,Value="$LAMBDA_NAME" \
  --start-time "$START_TIME" \
  --end-time "$END_TIME" \
  --period 1800 \
  --statistics Sum \
  --region "$REGION" \
  --query 'Datapoints[0].Sum' \
  --output text 2>/dev/null || echo "0")

echo "   Invocations: ${INVOCATION_COUNT:-0}"
echo "   Errors: ${ERROR_COUNT:-0}"
echo ""

if [ "${INVOCATION_COUNT:-0}" == "0" ] || [ "$INVOCATION_COUNT" == "None" ]; then
  echo "⚠️  Lambda has NOT been invoked in last 30 minutes"
  echo "   Expected: ~6 invocations (every 5 minutes)"
  echo "   This suggests EventBridge schedule is not working!"
  echo ""
fi

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ $ISSUES_FOUND -eq 0 ]; then
  echo "✅ Deployment appears correct!"
  echo ""
  echo "   All components configured properly:"
  echo "   • Lambda function deployed"
  echo "   • EventBridge schedule (5 minutes)"
  echo "   • EventBridge target configured"
  echo "   • Lambda permission granted"
  echo "   • CloudWatch log group exists"
  echo ""
  
  if [ "${MSG_AVAILABLE:-0}" -gt 0 ]; then
    echo "   📬 $MSG_AVAILABLE messages waiting in queue"
    echo "   Next scheduled run: within 5 minutes"
    echo ""
    echo "   Monitor with:"
    echo "   aws logs tail /aws/lambda/$LAMBDA_NAME --follow --region $REGION"
  fi
else
  echo "❌ Found $ISSUES_FOUND issue(s)"
  echo ""
  echo "   Run Terraform apply to fix:"
  echo "   cd terraform/central"
  echo "   terraform apply -target=aws_cloudwatch_event_rule.mailer_schedule"
  echo "   terraform apply -target=aws_cloudwatch_event_target.mailer_schedule"
  echo "   terraform apply -target=aws_lambda_permission.allow_eventbridge_mailer"
  echo ""
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
