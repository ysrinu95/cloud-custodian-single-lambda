#!/bin/bash

# Quick fix script to manually create EventBridge schedule for cloud-custodian-mailer
# Use this as a temporary fix until Terraform apply is run

set -e

REGION="${1:-us-east-1}"
LAMBDA_NAME="cloud-custodian-mailer"
RULE_NAME="cloud-custodian-mailer-schedule"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Manual EventBridge Schedule Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "⚠️  WARNING: This is a temporary manual fix"
echo "   Proper solution: Run terraform apply in central account"
echo ""

# Get Lambda ARN
LAMBDA_ARN=$(aws lambda get-function --function-name "$LAMBDA_NAME" --region "$REGION" --query 'Configuration.FunctionArn' --output text)
echo "✅ Lambda ARN: $LAMBDA_ARN"
echo ""

# 1. Create EventBridge Rule
echo "1️⃣  Creating EventBridge rule..."
aws events put-rule \
  --name "$RULE_NAME" \
  --description "Trigger c7n-mailer Lambda every 5 minutes to process SQS queue" \
  --schedule-expression "rate(5 minutes)" \
  --state ENABLED \
  --region "$REGION" \
  --tags Key=Name,Value="$RULE_NAME" Key=terraform,Value="True" Key=oid-owned,Value="True"

RULE_ARN=$(aws events describe-rule --name "$RULE_NAME" --region "$REGION" --query 'Arn' --output text)
echo "✅ Rule created: $RULE_ARN"
echo ""

# 2. Add Lambda as target
echo "2️⃣  Adding Lambda as EventBridge target..."
aws events put-targets \
  --rule "$RULE_NAME" \
  --region "$REGION" \
  --targets "Id"="1","Arn"="$LAMBDA_ARN"

echo "✅ Target added"
echo ""

# 3. Grant EventBridge permission to invoke Lambda
echo "3️⃣  Granting EventBridge permission to invoke Lambda..."
aws lambda add-permission \
  --function-name "$LAMBDA_NAME" \
  --statement-id "AllowExecutionFromEventBridge" \
  --action "lambda:InvokeFunction" \
  --principal "events.amazonaws.com" \
  --source-arn "$RULE_ARN" \
  --region "$REGION" 2>&1 || echo "   (Permission may already exist)"

echo "✅ Permission granted"
echo ""

# 4. Create CloudWatch Log Group
echo "4️⃣  Creating CloudWatch Log Group..."
aws logs create-log-group \
  --log-group-name "/aws/lambda/$LAMBDA_NAME" \
  --region "$REGION" 2>&1 || echo "   (Log group may already exist)"

aws logs put-retention-policy \
  --log-group-name "/aws/lambda/$LAMBDA_NAME" \
  --retention-in-days 7 \
  --region "$REGION" 2>&1 || echo "   (Retention policy may already be set)"

echo "✅ Log group created/verified"
echo ""

# Verify
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Verification"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "EventBridge Rule:"
aws events describe-rule --name "$RULE_NAME" --region "$REGION" --query '[Name,State,ScheduleExpression]' --output table
echo ""

echo "EventBridge Targets:"
aws events list-targets-by-rule --rule "$RULE_NAME" --region "$REGION" --query 'Targets[*].[Id,Arn]' --output table
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Setup complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "The Lambda will now run every 5 minutes automatically."
echo "Monitor with:"
echo "  aws logs tail /aws/lambda/$LAMBDA_NAME --follow --region $REGION"
echo ""
echo "⚠️  IMPORTANT: These resources were created manually."
echo "   When you run terraform apply, it will import or recreate them."
echo "   No conflicts should occur as names match Terraform config."
echo ""
