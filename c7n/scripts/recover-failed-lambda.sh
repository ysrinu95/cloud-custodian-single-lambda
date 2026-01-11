#!/bin/bash
# Manual recovery script for failed c7n-mailer Lambda
# Run this if the Lambda is stuck in Failed state

set -e

LAMBDA_NAME="cloud-custodian-mailer"
REGION="us-east-1"

echo "🔍 Checking current Lambda state..."

# Get current state
CURRENT_STATE=$(aws lambda get-function --function-name $LAMBDA_NAME --region $REGION --query 'Configuration.State' --output text 2>/dev/null || echo "NOT_FOUND")

echo "Current state: $CURRENT_STATE"

if [ "$CURRENT_STATE" = "NOT_FOUND" ]; then
    echo "❌ Lambda function does not exist"
    echo "💡 Run the regular deploy script: ./scripts/deploy-mailer.sh"
    exit 1
fi

if [ "$CURRENT_STATE" = "Failed" ]; then
    echo "❌ Lambda is in Failed state"
    
    # Get more details
    echo "📋 Getting failure details..."
    aws lambda get-function --function-name $LAMBDA_NAME --region $REGION --query 'Configuration.[State,StateReason,StateReasonCode,LastUpdateStatus]' --output table
    
    echo ""
    echo "🗑️  Deleting failed Lambda function..."
    
    if aws lambda delete-function --function-name $LAMBDA_NAME --region $REGION; then
        echo "✅ Lambda deleted successfully"
        echo "⏳ Waiting 15 seconds for deletion to fully propagate..."
        sleep 15
        
        # Verify deletion
        VERIFY_STATE=$(aws lambda get-function --function-name $LAMBDA_NAME --region $REGION --query 'Configuration.State' --output text 2>/dev/null || echo "NOT_FOUND")
        
        if [ "$VERIFY_STATE" = "NOT_FOUND" ]; then
            echo "✅ Deletion confirmed"
            echo ""
            echo "🔄 Now run the deploy script to recreate:"
            echo "   cd c7n && ./scripts/deploy-mailer.sh"
        else
            echo "⚠️  Lambda still exists (state: $VERIFY_STATE)"
            echo "⏳ Waiting another 10 seconds..."
            sleep 10
            echo "💡 Try running the deploy script now: ./scripts/deploy-mailer.sh"
        fi
    else
        echo "❌ Failed to delete Lambda"
        echo "💡 Check if you have the correct AWS credentials and permissions"
        exit 1
    fi
    
elif [ "$CURRENT_STATE" = "Pending" ]; then
    echo "⏳ Lambda is in Pending state - waiting for activation"
    echo "💡 This usually takes 2-10 minutes for first deployment"
    echo ""
    echo "🔄 Monitoring state (will check every 15 seconds for 5 minutes)..."
    
    for i in {1..20}; do
        sleep 15
        NEW_STATE=$(aws lambda get-function --function-name $LAMBDA_NAME --region $REGION --query 'Configuration.State' --output text)
        echo "   Check $i/20: $NEW_STATE"
        
        if [ "$NEW_STATE" = "Active" ]; then
            echo "✅ Lambda is now Active!"
            echo "🔄 Run deploy script to complete configuration: ./scripts/deploy-mailer.sh"
            exit 0
        fi
        
        if [ "$NEW_STATE" = "Failed" ]; then
            echo "❌ Lambda entered Failed state"
            echo "🔄 Run this script again to delete and retry"
            exit 1
        fi
    done
    
    echo "⚠️  Lambda still Pending after 5 minutes"
    echo "💡 You can:"
    echo "   1. Wait longer (first deployment can take 10+ minutes)"
    echo "   2. Check AWS Lambda console for more details"
    echo "   3. Run: aws lambda get-function --function-name $LAMBDA_NAME --region $REGION"
    
elif [ "$CURRENT_STATE" = "Active" ]; then
    echo "✅ Lambda is Active and healthy!"
    echo "💡 If you need to update configuration, run: ./scripts/deploy-mailer.sh"
    
else
    echo "⚠️  Lambda is in unexpected state: $CURRENT_STATE"
    echo "📋 Full details:"
    aws lambda get-function --function-name $LAMBDA_NAME --region $REGION --query 'Configuration' --output table
fi
