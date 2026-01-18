#!/bin/bash

# Script to diagnose c7n-mailer Lambda and SQS queue status
# This checks if the mailer Lambda is receiving and processing messages

set -e

REGION="${1:-us-east-1}"
QUEUE_NAME="aikyam-cloud-custodian-realtime-notifications"
LAMBDA_NAME="cloud-custodian-mailer"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Cloud Custodian Mailer Diagnostic"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 1. Check SQS Queue Status
echo "📬 Checking SQS Queue Status..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

QUEUE_URL=$(aws sqs get-queue-url --queue-name "$QUEUE_NAME" --region "$REGION" --query 'QueueUrl' --output text 2>/dev/null || echo "")

if [ -z "$QUEUE_URL" ]; then
  echo "❌ Queue $QUEUE_NAME not found in region $REGION"
  exit 1
fi

echo "✅ Queue URL: $QUEUE_URL"
echo ""

# Get queue attributes
QUEUE_ATTRS=$(aws sqs get-queue-attributes \
  --queue-url "$QUEUE_URL" \
  --attribute-names All \
  --region "$REGION")

APPROX_MESSAGES=$(echo "$QUEUE_ATTRS" | jq -r '.Attributes.ApproximateNumberOfMessages // "0"')
APPROX_NOT_VISIBLE=$(echo "$QUEUE_ATTRS" | jq -r '.Attributes.ApproximateNumberOfMessagesNotVisible // "0"')
APPROX_DELAYED=$(echo "$QUEUE_ATTRS" | jq -r '.Attributes.ApproximateNumberOfMessagesDelayed // "0"')

echo "📊 Queue Statistics:"
echo "   - Messages Available: $APPROX_MESSAGES"
echo "   - Messages In Flight: $APPROX_NOT_VISIBLE"
echo "   - Messages Delayed: $APPROX_DELAYED"
echo ""

if [ "$APPROX_MESSAGES" -gt 0 ]; then
  echo "⚠️  WARNING: $APPROX_MESSAGES messages are waiting to be processed!"
  echo "   This suggests the Lambda is NOT consuming messages."
  echo ""
fi

# 2. Check Lambda Function Status
echo "🔧 Checking Lambda Function..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

LAMBDA_CONFIG=$(aws lambda get-function-configuration \
  --function-name "$LAMBDA_NAME" \
  --region "$REGION" 2>/dev/null || echo "")

if [ -z "$LAMBDA_CONFIG" ]; then
  echo "❌ Lambda function $LAMBDA_NAME not found in region $REGION"
  exit 1
fi

echo "✅ Lambda function exists"
echo ""

LAMBDA_STATE=$(echo "$LAMBDA_CONFIG" | jq -r '.State')
LAMBDA_LAST_UPDATE=$(echo "$LAMBDA_CONFIG" | jq -r '.LastUpdateStatus')
LAMBDA_RUNTIME=$(echo "$LAMBDA_CONFIG" | jq -r '.Runtime')
LAMBDA_TIMEOUT=$(echo "$LAMBDA_CONFIG" | jq -r '.Timeout')

echo "📋 Lambda Configuration:"
echo "   - State: $LAMBDA_STATE"
echo "   - Last Update Status: $LAMBDA_LAST_UPDATE"
echo "   - Runtime: $LAMBDA_RUNTIME"
echo "   - Timeout: ${LAMBDA_TIMEOUT}s"
echo ""

# Check for SQS trigger
echo "🔗 Checking SQS Event Source Mapping..."
EVENT_SOURCE_MAPPINGS=$(aws lambda list-event-source-mappings \
  --function-name "$LAMBDA_NAME" \
  --region "$REGION" \
  --query "EventSourceMappings[?contains(EventSourceArn, '$QUEUE_NAME')]")

MAPPING_COUNT=$(echo "$EVENT_SOURCE_MAPPINGS" | jq '. | length')

if [ "$MAPPING_COUNT" -eq 0 ]; then
  echo "❌ ERROR: No SQS trigger configured for $QUEUE_NAME"
  echo "   The Lambda will NOT process messages!"
  echo ""
  echo "   To fix this, run:"
  echo "   aws lambda create-event-source-mapping \\"
  echo "     --function-name $LAMBDA_NAME \\"
  echo "     --event-source-arn <QUEUE_ARN> \\"
  echo "     --batch-size 10 \\"
  echo "     --region $REGION"
  echo ""
else
  echo "✅ SQS trigger configured"
  
  MAPPING_STATE=$(echo "$EVENT_SOURCE_MAPPINGS" | jq -r '.[0].State')
  MAPPING_ENABLED=$(echo "$EVENT_SOURCE_MAPPINGS" | jq -r '.[0].State == "Enabled"')
  MAPPING_BATCH_SIZE=$(echo "$EVENT_SOURCE_MAPPINGS" | jq -r '.[0].BatchSize')
  
  echo "   - State: $MAPPING_STATE"
  echo "   - Batch Size: $MAPPING_BATCH_SIZE"
  echo ""
  
  if [ "$MAPPING_STATE" != "Enabled" ]; then
    echo "⚠️  WARNING: Event source mapping is NOT enabled!"
    echo "   State: $MAPPING_STATE"
    echo ""
  fi
fi

# 3. Check Recent Lambda Invocations
echo "📊 Checking Recent Lambda Invocations (last 15 minutes)..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

START_TIME=$(date -u -d '15 minutes ago' '+%Y-%m-%dT%H:%M:%S')
END_TIME=$(date -u '+%Y-%m-%dT%H:%M:%S')

# Get invocation count
INVOCATION_COUNT=$(aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --dimensions Name=FunctionName,Value="$LAMBDA_NAME" \
  --start-time "$START_TIME" \
  --end-time "$END_TIME" \
  --period 900 \
  --statistics Sum \
  --region "$REGION" \
  --query 'Datapoints[0].Sum' \
  --output text 2>/dev/null || echo "0")

# Get error count
ERROR_COUNT=$(aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Errors \
  --dimensions Name=FunctionName,Value="$LAMBDA_NAME" \
  --start-time "$START_TIME" \
  --end-time "$END_TIME" \
  --period 900 \
  --statistics Sum \
  --region "$REGION" \
  --query 'Datapoints[0].Sum' \
  --output text 2>/dev/null || echo "0")

echo "   - Total Invocations: ${INVOCATION_COUNT:-0}"
echo "   - Errors: ${ERROR_COUNT:-0}"
echo ""

if [ "${INVOCATION_COUNT:-0}" == "0" ] || [ "$INVOCATION_COUNT" == "None" ]; then
  echo "❌ Lambda has NOT been invoked in the last 15 minutes!"
  echo "   Possible causes:"
  echo "   1. SQS trigger is disabled"
  echo "   2. No permissions to consume from SQS"
  echo "   3. Lambda execution role issues"
  echo ""
fi

# 4. Check CloudWatch Logs
echo "📋 Checking Recent CloudWatch Logs..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

LOG_GROUP="/aws/lambda/$LAMBDA_NAME"

# Check if log group exists
aws logs describe-log-groups \
  --log-group-name-prefix "$LOG_GROUP" \
  --region "$REGION" \
  --query "logGroups[?logGroupName=='$LOG_GROUP'].logGroupName" \
  --output text > /dev/null 2>&1

if [ $? -eq 0 ]; then
  echo "✅ Log group exists: $LOG_GROUP"
  echo ""
  
  # Get latest log stream
  LATEST_STREAM=$(aws logs describe-log-streams \
    --log-group-name "$LOG_GROUP" \
    --order-by LastEventTime \
    --descending \
    --max-items 1 \
    --region "$REGION" \
    --query 'logStreams[0].logStreamName' \
    --output text 2>/dev/null || echo "")
  
  if [ -n "$LATEST_STREAM" ] && [ "$LATEST_STREAM" != "None" ]; then
    echo "📄 Latest Log Stream: $LATEST_STREAM"
    echo ""
    echo "Recent log entries:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    aws logs get-log-events \
      --log-group-name "$LOG_GROUP" \
      --log-stream-name "$LATEST_STREAM" \
      --limit 20 \
      --region "$REGION" \
      --query 'events[].message' \
      --output text 2>/dev/null | tail -20
    
    echo ""
  else
    echo "⚠️  No log streams found - Lambda may never have been invoked"
    echo ""
  fi
else
  echo "❌ Log group does not exist: $LOG_GROUP"
  echo ""
fi

# 5. Check Lambda Environment Variables
echo "🔐 Checking Lambda Environment Variables..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

ENV_VARS=$(aws lambda get-function-configuration \
  --function-name "$LAMBDA_NAME" \
  --region "$REGION" \
  --query 'Environment.Variables' 2>/dev/null || echo "{}")

if [ "$ENV_VARS" != "{}" ] && [ "$ENV_VARS" != "null" ]; then
  echo "$ENV_VARS" | jq -r 'to_entries[] | "   - \(.key): \(.value | tostring | .[0:50])..."'
  echo ""
else
  echo "⚠️  No environment variables configured"
  echo ""
fi

# 6. Summary and Recommendations
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Summary & Recommendations"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ "$APPROX_MESSAGES" -gt 0 ] && [ "${INVOCATION_COUNT:-0}" == "0" ]; then
  echo "🔴 PROBLEM IDENTIFIED:"
  echo "   - Messages are in SQS queue: $APPROX_MESSAGES"
  echo "   - Lambda has NOT been invoked"
  echo ""
  echo "   Likely cause: SQS trigger not configured or disabled"
  echo ""
  echo "   SOLUTION: Configure the SQS trigger for the Lambda function"
  echo "   Run: cd scripts && ./configure-mailer-sqs-trigger.sh"
  echo ""
elif [ "${ERROR_COUNT:-0}" -gt 0 ]; then
  echo "🔴 PROBLEM IDENTIFIED:"
  echo "   - Lambda is being invoked but encountering errors"
  echo "   - Check the CloudWatch logs above for error details"
  echo ""
  echo "   Common issues:"
  echo "   1. Missing SES configuration"
  echo "   2. Invalid email templates"
  echo "   3. IAM permission issues"
  echo "   4. SMTP configuration errors"
  echo ""
else
  echo "✅ Everything appears to be configured correctly"
  echo ""
  if [ "$APPROX_MESSAGES" -gt 0 ]; then
    echo "⚠️  Note: Messages are still in queue, Lambda may be processing slowly"
  fi
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📎 Quick Commands:"
echo ""
echo "View full logs:"
echo "  aws logs tail /aws/lambda/$LAMBDA_NAME --follow --region $REGION"
echo ""
echo "Manually invoke Lambda:"
echo "  aws lambda invoke --function-name $LAMBDA_NAME --region $REGION /tmp/output.json"
echo ""
echo "Purge SQS queue (if needed):"
echo "  aws sqs purge-queue --queue-url $QUEUE_URL --region $REGION"
echo ""
