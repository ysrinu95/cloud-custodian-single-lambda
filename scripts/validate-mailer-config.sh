#!/bin/bash

# Script to validate cloud-custodian-mailer Lambda configuration
# Checks SQS queues, event source mappings, and policy configurations

set -e

REGION="${1:-us-east-1}"
CENTRAL_ACCOUNT="172327596604"
LAMBDA_NAME="cloud-custodian-mailer"
PERIODIC_QUEUE="aikyam-cloud-custodian-periodic-notifications"
REALTIME_QUEUE="aikyam-cloud-custodian-realtime-notifications"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Cloud Custodian Mailer Configuration Validation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Account: $CENTRAL_ACCOUNT"
echo "Region: $REGION"
echo "Lambda: $LAMBDA_NAME"
echo ""

# 1. Check Lambda function exists
echo "1️⃣  Checking Lambda Function..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

LAMBDA_CONFIG=$(aws lambda get-function-configuration \
  --function-name "$LAMBDA_NAME" \
  --region "$REGION" 2>&1)

if [ $? -ne 0 ]; then
  echo "❌ Lambda function $LAMBDA_NAME not found!"
  echo "$LAMBDA_CONFIG"
  exit 1
fi

echo "✅ Lambda function exists"
LAMBDA_STATE=$(echo "$LAMBDA_CONFIG" | jq -r '.State')
LAMBDA_RUNTIME=$(echo "$LAMBDA_CONFIG" | jq -r '.Runtime')
echo "   - State: $LAMBDA_STATE"
echo "   - Runtime: $LAMBDA_RUNTIME"
echo ""

# 2. Check SQS Queues
echo "2️⃣  Checking SQS Queues..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check periodic queue
PERIODIC_QUEUE_URL=$(aws sqs get-queue-url --queue-name "$PERIODIC_QUEUE" --region "$REGION" --query 'QueueUrl' --output text 2>/dev/null || echo "")

if [ -z "$PERIODIC_QUEUE_URL" ]; then
  echo "❌ Periodic queue not found: $PERIODIC_QUEUE"
  PERIODIC_EXISTS=false
else
  echo "✅ Periodic queue: $PERIODIC_QUEUE"
  PERIODIC_ATTRS=$(aws sqs get-queue-attributes --queue-url "$PERIODIC_QUEUE_URL" --attribute-names All --region "$REGION")
  PERIODIC_MESSAGES=$(echo "$PERIODIC_ATTRS" | jq -r '.Attributes.ApproximateNumberOfMessages // "0"')
  echo "   - Messages waiting: $PERIODIC_MESSAGES"
  PERIODIC_EXISTS=true
fi

# Check realtime queue
REALTIME_QUEUE_URL=$(aws sqs get-queue-url --queue-name "$REALTIME_QUEUE" --region "$REGION" --query 'QueueUrl' --output text 2>/dev/null || echo "")

if [ -z "$REALTIME_QUEUE_URL" ]; then
  echo "⚠️  Realtime queue not found: $REALTIME_QUEUE"
  REALTIME_EXISTS=false
else
  echo "✅ Realtime queue: $REALTIME_QUEUE"
  REALTIME_ATTRS=$(aws sqs get-queue-attributes --queue-url "$REALTIME_QUEUE_URL" --attribute-names All --region "$REGION")
  REALTIME_MESSAGES=$(echo "$REALTIME_ATTRS" | jq -r '.Attributes.ApproximateNumberOfMessages // "0"')
  echo "   - Messages waiting: $REALTIME_MESSAGES"
  REALTIME_EXISTS=true
fi

echo ""

# 3. Check Event Source Mappings
echo "3️⃣  Checking SQS Event Source Mappings..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

EVENT_SOURCE_MAPPINGS=$(aws lambda list-event-source-mappings \
  --function-name "$LAMBDA_NAME" \
  --region "$REGION" 2>/dev/null || echo '{"EventSourceMappings":[]}')

MAPPING_COUNT=$(echo "$EVENT_SOURCE_MAPPINGS" | jq '.EventSourceMappings | length')

if [ "$MAPPING_COUNT" -eq 0 ]; then
  echo "❌ NO event source mappings configured!"
  echo "   The Lambda will NOT process ANY messages!"
  echo ""
  echo "   To fix, create event source mappings for both queues."
  echo ""
  HAS_PERIODIC_MAPPING=false
  HAS_REALTIME_MAPPING=false
else
  echo "Found $MAPPING_COUNT event source mapping(s):"
  echo ""
  
  HAS_PERIODIC_MAPPING=false
  HAS_REALTIME_MAPPING=false
  
  echo "$EVENT_SOURCE_MAPPINGS" | jq -r '.EventSourceMappings[] | 
    "Queue: " + (.EventSourceArn | split(":") | last) + 
    "\n  State: " + .State + 
    "\n  Enabled: " + (.State == "Enabled" | tostring) +
    "\n  Batch Size: " + (.BatchSize | tostring) +
    "\n  UUID: " + .UUID + "\n"'
  
  # Check for periodic queue mapping
  if echo "$EVENT_SOURCE_MAPPINGS" | jq -e ".EventSourceMappings[] | select(.EventSourceArn | contains(\"$PERIODIC_QUEUE\"))" > /dev/null 2>&1; then
    HAS_PERIODIC_MAPPING=true
    PERIODIC_STATE=$(echo "$EVENT_SOURCE_MAPPINGS" | jq -r ".EventSourceMappings[] | select(.EventSourceArn | contains(\"$PERIODIC_QUEUE\")) | .State")
    
    if [ "$PERIODIC_STATE" == "Enabled" ]; then
      echo "✅ Periodic queue mapping: ENABLED"
    else
      echo "⚠️  Periodic queue mapping: $PERIODIC_STATE (should be Enabled)"
    fi
  else
    echo "❌ No mapping for periodic queue: $PERIODIC_QUEUE"
  fi
  
  # Check for realtime queue mapping
  if echo "$EVENT_SOURCE_MAPPINGS" | jq -e ".EventSourceMappings[] | select(.EventSourceArn | contains(\"$REALTIME_QUEUE\"))" > /dev/null 2>&1; then
    HAS_REALTIME_MAPPING=true
    REALTIME_STATE=$(echo "$EVENT_SOURCE_MAPPINGS" | jq -r ".EventSourceMappings[] | select(.EventSourceArn | contains(\"$REALTIME_QUEUE\")) | .State")
    
    if [ "$REALTIME_STATE" == "Enabled" ]; then
      echo "✅ Realtime queue mapping: ENABLED"
    else
      echo "⚠️  Realtime queue mapping: $REALTIME_STATE (should be Enabled)"
    fi
  else
    echo "⚠️  No mapping for realtime queue: $REALTIME_QUEUE"
  fi
fi

echo ""

# 4. Check Policy Configurations
echo "4️⃣  Validating Policy Queue Configurations..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cd "$(dirname "$0")/../c7n/policies"

echo "Checking periodic policies..."
WRONG_QUEUE_POLICIES=()

for policy_file in periodic/*.yml; do
  if [ -f "$policy_file" ]; then
    # Check if policy uses realtime queue instead of periodic
    if grep -q "$REALTIME_QUEUE" "$policy_file" 2>/dev/null; then
      WRONG_QUEUE_POLICIES+=("$policy_file")
    fi
  fi
done

if [ ${#WRONG_QUEUE_POLICIES[@]} -gt 0 ]; then
  echo "❌ Found ${#WRONG_QUEUE_POLICIES[@]} periodic policies using WRONG queue:"
  echo ""
  for policy in "${WRONG_QUEUE_POLICIES[@]}"; do
    echo "   - $policy"
    echo "     Uses: $REALTIME_QUEUE"
    echo "     Should use: $PERIODIC_QUEUE"
    echo ""
  done
  echo "   These policies will send notifications to the wrong queue!"
  echo ""
else
  echo "✅ All periodic policies use correct queue: $PERIODIC_QUEUE"
  echo ""
fi

# 5. Check Recent Lambda Invocations
echo "5️⃣  Checking Recent Lambda Activity (last 30 minutes)..."
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

echo "   - Invocations: ${INVOCATION_COUNT:-0}"
echo "   - Errors: ${ERROR_COUNT:-0}"
echo ""

if [ "${INVOCATION_COUNT:-0}" == "0" ] || [ "$INVOCATION_COUNT" == "None" ]; then
  echo "⚠️  Lambda has NOT been invoked recently"
  echo ""
fi

# 6. Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Summary & Required Actions"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

ISSUES_FOUND=0

# Check for missing event source mappings
if [ "$HAS_PERIODIC_MAPPING" == "false" ] && [ "$PERIODIC_EXISTS" == "true" ]; then
  echo "🔴 ISSUE: Missing event source mapping for periodic queue"
  echo "   Action required:"
  echo "   aws lambda create-event-source-mapping \\"
  echo "     --function-name $LAMBDA_NAME \\"
  echo "     --event-source-arn arn:aws:sqs:$REGION:$CENTRAL_ACCOUNT:$PERIODIC_QUEUE \\"
  echo "     --batch-size 10 \\"
  echo "     --region $REGION"
  echo ""
  ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

if [ "$HAS_REALTIME_MAPPING" == "false" ] && [ "$REALTIME_EXISTS" == "true" ]; then
  echo "⚠️  INFO: No event source mapping for realtime queue"
  echo "   If you want to process realtime events, create mapping:"
  echo "   aws lambda create-event-source-mapping \\"
  echo "     --function-name $LAMBDA_NAME \\"
  echo "     --event-source-arn arn:aws:sqs:$REGION:$CENTRAL_ACCOUNT:$REALTIME_QUEUE \\"
  echo "     --batch-size 10 \\"
  echo "     --region $REGION"
  echo ""
fi

# Check for wrong queue configurations
if [ ${#WRONG_QUEUE_POLICIES[@]} -gt 0 ]; then
  echo "🔴 ISSUE: ${#WRONG_QUEUE_POLICIES[@]} policies using wrong queue"
  echo "   Action required: Fix queue URLs in periodic policies"
  echo "   Run: cd c7n/policies/periodic && sed -i 's/$REALTIME_QUEUE/$PERIODIC_QUEUE/g' *.yml"
  echo ""
  ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

# Check for messages waiting
if [ "${PERIODIC_MESSAGES:-0}" -gt 0 ]; then
  echo "⚠️  INFO: $PERIODIC_MESSAGES messages waiting in periodic queue"
  if [ "$HAS_PERIODIC_MAPPING" == "true" ]; then
    echo "   Lambda should process these automatically"
  else
    echo "   Messages will NOT be processed (no event source mapping)"
  fi
  echo ""
fi

if [ "${REALTIME_MESSAGES:-0}" -gt 0 ]; then
  echo "⚠️  INFO: $REALTIME_MESSAGES messages waiting in realtime queue"
  if [ "$HAS_REALTIME_MAPPING" == "true" ]; then
    echo "   Lambda should process these automatically"
  else
    echo "   Messages will NOT be processed (no event source mapping)"
  fi
  echo ""
fi

if [ $ISSUES_FOUND -eq 0 ]; then
  echo "✅ Configuration looks good!"
  echo ""
  echo "   - Lambda function: OK"
  echo "   - SQS queues: OK"
  echo "   - Event source mappings: OK"
  echo "   - Policy configurations: OK"
  echo ""
else
  echo "Found $ISSUES_FOUND critical issue(s) that need to be fixed."
  echo ""
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📎 Useful Commands:"
echo ""
echo "View Lambda logs:"
echo "  aws logs tail /aws/lambda/$LAMBDA_NAME --follow --region $REGION"
echo ""
echo "Check queue messages:"
echo "  aws sqs get-queue-attributes --queue-url $PERIODIC_QUEUE_URL --attribute-names All --region $REGION"
echo ""
echo "Manually trigger Lambda:"
echo "  aws lambda invoke --function-name $LAMBDA_NAME --region $REGION /tmp/output.json"
echo ""
