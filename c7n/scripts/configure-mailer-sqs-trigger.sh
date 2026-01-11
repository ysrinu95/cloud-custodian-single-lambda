#!/bin/bash
# Configure c7n-mailer Lambda to use SQS event source mapping instead of scheduled rule
# Run this after deploying c7n-mailer with: c7n-mailer --config config/mailer.yml --update-lambda

set -euo pipefail

LAMBDA_NAME="cloud-custodian-mailer"
QUEUE_URL="https://sqs.us-east-1.amazonaws.com/757541135089/cloud-custodian-mailer-queue-dev"
REGION="us-east-1"
EVENT_RULE_NAME="custodian-mailer"

echo "🔧 Configuring c7n-mailer to use SQS event source mapping"

# Get queue ARN from URL
ACCOUNT_ID=$(echo "$QUEUE_URL" | cut -d'/' -f4)
QUEUE_NAME=$(echo "$QUEUE_URL" | cut -d'/' -f5)
QUEUE_ARN="arn:aws:sqs:${REGION}:${ACCOUNT_ID}:${QUEUE_NAME}"

echo "📋 Configuration:"
echo "  Lambda: $LAMBDA_NAME"
echo "  Queue ARN: $QUEUE_ARN"
echo "  Region: $REGION"
echo ""

# Step 1: Check if event source mapping already exists
echo "1️⃣ Checking for existing event source mappings..."
EXISTING_UUID=$(aws lambda list-event-source-mappings \
  --function-name "$LAMBDA_NAME" \
  --region "$REGION" \
  --query "EventSourceMappings[?EventSourceArn=='$QUEUE_ARN'].UUID" \
  --output text 2>/dev/null || echo "")

if [ -n "$EXISTING_UUID" ]; then
  echo "  ✅ Event source mapping already exists (UUID: $EXISTING_UUID)"
else
  echo "  ➕ Creating new event source mapping..."
  
  # Create event source mapping
  aws lambda create-event-source-mapping \
    --function-name "$LAMBDA_NAME" \
    --event-source-arn "$QUEUE_ARN" \
    --batch-size 10 \
    --enabled \
    --region "$REGION"
  
  echo "  ✅ Event source mapping created"
fi

# Step 2: Remove EventBridge scheduled rule (if exists)
echo ""
echo "2️⃣ Removing scheduled EventBridge rule..."

if aws events describe-rule --name "$EVENT_RULE_NAME" --region "$REGION" >/dev/null 2>&1; then
  echo "  🗑️ Found rule '$EVENT_RULE_NAME', removing..."
  
  # Remove targets first
  TARGET_IDS=$(aws events list-targets-by-rule \
    --rule "$EVENT_RULE_NAME" \
    --region "$REGION" \
    --query 'Targets[].Id' \
    --output text 2>/dev/null || echo "")
  
  if [ -n "$TARGET_IDS" ]; then
    for TARGET_ID in $TARGET_IDS; do
      aws events remove-targets \
        --rule "$EVENT_RULE_NAME" \
        --ids "$TARGET_ID" \
        --region "$REGION" 2>/dev/null || true
    done
    echo "  ✅ Removed targets"
  fi
  
  # Delete the rule
  aws events delete-rule \
    --name "$EVENT_RULE_NAME" \
    --region "$REGION" 2>/dev/null || true
  
  echo "  ✅ Removed EventBridge rule"
else
  echo "  ℹ️ No scheduled rule found (already removed or not created)"
fi

# Step 3: Verify configuration
echo ""
echo "3️⃣ Verifying configuration..."

MAPPING_STATE=$(aws lambda list-event-source-mappings \
  --function-name "$LAMBDA_NAME" \
  --region "$REGION" \
  --query "EventSourceMappings[?EventSourceArn=='$QUEUE_ARN'].State" \
  --output text)

if [ "$MAPPING_STATE" = "Enabled" ]; then
  echo "  ✅ Event source mapping is active"
else
  echo "  ⚠️ Event source mapping state: $MAPPING_STATE"
fi

echo ""
echo "✅ Configuration complete!"
echo ""
echo "📊 Summary:"
echo "  - Lambda '$LAMBDA_NAME' will now be triggered by SQS messages"
echo "  - Lambda invokes only when messages exist in the queue"
echo "  - Scheduled EventBridge rule removed"
echo ""
echo "💡 Next steps:"
echo "  - Test by sending a message to the SQS queue"
echo "  - Monitor Lambda CloudWatch Logs for invocations"
echo "  - Check SQS queue metrics for message processing"
