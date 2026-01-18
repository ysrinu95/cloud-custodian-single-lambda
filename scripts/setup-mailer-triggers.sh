#!/bin/bash

# Script to configure SQS triggers for cloud-custodian-mailer Lambda
# Creates event source mappings for both periodic and realtime queues

set -e

REGION="${1:-us-east-1}"
CENTRAL_ACCOUNT="172327596604"
LAMBDA_NAME="cloud-custodian-mailer"
PERIODIC_QUEUE="aikyam-cloud-custodian-periodic-notifications"
REALTIME_QUEUE="aikyam-cloud-custodian-realtime-notifications"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Cloud Custodian Mailer - Configure SQS Triggers"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Account: $CENTRAL_ACCOUNT"
echo "Region: $REGION"
echo "Lambda: $LAMBDA_NAME"
echo ""

# 1. Verify Lambda exists
echo "1️⃣  Verifying Lambda function..."
if ! aws lambda get-function --function-name "$LAMBDA_NAME" --region "$REGION" &>/dev/null; then
  echo "❌ Lambda function $LAMBDA_NAME not found!"
  exit 1
fi
echo "✅ Lambda function exists"
echo ""

# 2. Get queue ARNs
echo "2️⃣  Getting SQS queue ARNs..."

PERIODIC_QUEUE_URL=$(aws sqs get-queue-url --queue-name "$PERIODIC_QUEUE" --region "$REGION" --query 'QueueUrl' --output text 2>/dev/null || echo "")
if [ -z "$PERIODIC_QUEUE_URL" ]; then
  echo "❌ Periodic queue not found: $PERIODIC_QUEUE"
  PERIODIC_QUEUE_ARN=""
else
  PERIODIC_QUEUE_ARN=$(aws sqs get-queue-attributes --queue-url "$PERIODIC_QUEUE_URL" --attribute-names QueueArn --region "$REGION" --query 'Attributes.QueueArn' --output text)
  echo "✅ Periodic queue: $PERIODIC_QUEUE"
  echo "   ARN: $PERIODIC_QUEUE_ARN"
fi

REALTIME_QUEUE_URL=$(aws sqs get-queue-url --queue-name "$REALTIME_QUEUE" --region "$REGION" --query 'QueueUrl' --output text 2>/dev/null || echo "")
if [ -z "$REALTIME_QUEUE_URL" ]; then
  echo "⚠️  Realtime queue not found: $REALTIME_QUEUE"
  REALTIME_QUEUE_ARN=""
else
  REALTIME_QUEUE_ARN=$(aws sqs get-queue-attributes --queue-url "$REALTIME_QUEUE_URL" --attribute-names QueueArn --region "$REGION" --query 'Attributes.QueueArn' --output text)
  echo "✅ Realtime queue: $REALTIME_QUEUE"
  echo "   ARN: $REALTIME_QUEUE_ARN"
fi
echo ""

# 3. Check existing event source mappings
echo "3️⃣  Checking existing event source mappings..."
EXISTING_MAPPINGS=$(aws lambda list-event-source-mappings --function-name "$LAMBDA_NAME" --region "$REGION" 2>/dev/null || echo '{"EventSourceMappings":[]}')
MAPPING_COUNT=$(echo "$EXISTING_MAPPINGS" | jq '.EventSourceMappings | length')

if [ "$MAPPING_COUNT" -gt 0 ]; then
  echo "Found $MAPPING_COUNT existing mapping(s):"
  echo "$EXISTING_MAPPINGS" | jq -r '.EventSourceMappings[] | "  - Queue: " + (.EventSourceArn | split(":") | last) + " (State: " + .State + ")"'
  echo ""
fi

# Check if periodic queue mapping exists
HAS_PERIODIC=false
if [ -n "$PERIODIC_QUEUE_ARN" ]; then
  if echo "$EXISTING_MAPPINGS" | jq -e ".EventSourceMappings[] | select(.EventSourceArn | contains(\"$PERIODIC_QUEUE\"))" > /dev/null 2>&1; then
    HAS_PERIODIC=true
    PERIODIC_STATE=$(echo "$EXISTING_MAPPINGS" | jq -r ".EventSourceMappings[] | select(.EventSourceArn | contains(\"$PERIODIC_QUEUE\")) | .State")
    echo "⚠️  Periodic queue mapping already exists (State: $PERIODIC_STATE)"
  fi
fi

# Check if realtime queue mapping exists
HAS_REALTIME=false
if [ -n "$REALTIME_QUEUE_ARN" ]; then
  if echo "$EXISTING_MAPPINGS" | jq -e ".EventSourceMappings[] | select(.EventSourceArn | contains(\"$REALTIME_QUEUE\"))" > /dev/null 2>&1; then
    HAS_REALTIME=true
    REALTIME_STATE=$(echo "$EXISTING_MAPPINGS" | jq -r ".EventSourceMappings[] | select(.EventSourceArn | contains(\"$REALTIME_QUEUE\")) | .State")
    echo "⚠️  Realtime queue mapping already exists (State: $REALTIME_STATE)"
  fi
fi
echo ""

# 4. Create event source mappings
echo "4️⃣  Creating event source mappings..."
echo ""

# Create periodic queue mapping
if [ "$HAS_PERIODIC" == "false" ] && [ -n "$PERIODIC_QUEUE_ARN" ]; then
  echo "📌 Creating mapping for PERIODIC queue..."
  
  PERIODIC_RESULT=$(aws lambda create-event-source-mapping \
    --function-name "$LAMBDA_NAME" \
    --event-source-arn "$PERIODIC_QUEUE_ARN" \
    --batch-size 10 \
    --enabled \
    --region "$REGION" 2>&1)
  
  if [ $? -eq 0 ]; then
    PERIODIC_UUID=$(echo "$PERIODIC_RESULT" | jq -r '.UUID')
    echo "✅ Created periodic queue mapping: $PERIODIC_UUID"
    echo "   Queue: $PERIODIC_QUEUE"
    echo "   Batch Size: 10"
    echo "   State: Enabled"
  else
    echo "❌ Failed to create periodic queue mapping:"
    echo "$PERIODIC_RESULT"
  fi
  echo ""
elif [ "$HAS_PERIODIC" == "true" ]; then
  echo "⏭️  Skipping periodic queue (already configured)"
  echo ""
else
  echo "⏭️  Skipping periodic queue (queue not found)"
  echo ""
fi

# Create realtime queue mapping
if [ "$HAS_REALTIME" == "false" ] && [ -n "$REALTIME_QUEUE_ARN" ]; then
  echo "📌 Creating mapping for REALTIME queue..."
  
  REALTIME_RESULT=$(aws lambda create-event-source-mapping \
    --function-name "$LAMBDA_NAME" \
    --event-source-arn "$REALTIME_QUEUE_ARN" \
    --batch-size 10 \
    --enabled \
    --region "$REGION" 2>&1)
  
  if [ $? -eq 0 ]; then
    REALTIME_UUID=$(echo "$REALTIME_RESULT" | jq -r '.UUID')
    echo "✅ Created realtime queue mapping: $REALTIME_UUID"
    echo "   Queue: $REALTIME_QUEUE"
    echo "   Batch Size: 10"
    echo "   State: Enabled"
  else
    echo "❌ Failed to create realtime queue mapping:"
    echo "$REALTIME_RESULT"
  fi
  echo ""
elif [ "$HAS_REALTIME" == "true" ]; then
  echo "⏭️  Skipping realtime queue (already configured)"
  echo ""
else
  echo "⏭️  Skipping realtime queue (queue not found)"
  echo ""
fi

# 5. Verify configuration
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "5️⃣  Verifying final configuration..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

FINAL_MAPPINGS=$(aws lambda list-event-source-mappings --function-name "$LAMBDA_NAME" --region "$REGION")
FINAL_COUNT=$(echo "$FINAL_MAPPINGS" | jq '.EventSourceMappings | length')

echo "Total event source mappings: $FINAL_COUNT"
echo ""

if [ "$FINAL_COUNT" -gt 0 ]; then
  echo "$FINAL_MAPPINGS" | jq -r '.EventSourceMappings[] | 
    "Queue: " + (.EventSourceArn | split(":") | last) + 
    "\n  UUID: " + .UUID +
    "\n  State: " + .State + 
    "\n  Batch Size: " + (.BatchSize | tostring) +
    "\n  Last Modified: " + .LastModified + "\n"'
fi

# Check if periodic messages exist
if [ -n "$PERIODIC_QUEUE_URL" ]; then
  PERIODIC_MESSAGES=$(aws sqs get-queue-attributes --queue-url "$PERIODIC_QUEUE_URL" --attribute-names ApproximateNumberOfMessages --region "$REGION" --query 'Attributes.ApproximateNumberOfMessages' --output text 2>/dev/null || echo "0")
  
  if [ "$PERIODIC_MESSAGES" -gt 0 ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📬 $PERIODIC_MESSAGES messages waiting in periodic queue"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "The Lambda should automatically process these messages within a few seconds."
    echo "Monitor progress with:"
    echo ""
    echo "  # Watch Lambda logs (will create log group on first invocation)"
    echo "  aws logs tail /aws/lambda/$LAMBDA_NAME --follow --region $REGION"
    echo ""
    echo "  # Check queue message count"
    echo "  aws sqs get-queue-attributes --queue-url $PERIODIC_QUEUE_URL \\"
    echo "    --attribute-names ApproximateNumberOfMessages --region $REGION"
    echo ""
  fi
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Configuration complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next steps:"
echo "1. Wait 10-30 seconds for Lambda to process existing messages"
echo "2. Check your email for notifications"
echo "3. If no emails arrive, check CloudWatch logs for errors:"
echo "   aws logs tail /aws/lambda/$LAMBDA_NAME --follow --region $REGION"
echo ""
