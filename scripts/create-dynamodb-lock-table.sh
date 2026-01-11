#!/bin/bash

# Script to create DynamoDB table for Terraform state locking
# Usage: ./create-dynamodb-lock-table.sh [region]

set -e

REGION="${1:-us-east-1}"
TABLE_NAME="terraform-state-lock"

echo "Creating DynamoDB table for Terraform state locking..."
echo "Region: $REGION"
echo "Table: $TABLE_NAME"

# Check if table already exists
if aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$REGION" 2>/dev/null; then
    echo "✅ Table '$TABLE_NAME' already exists"
    exit 0
fi

# Create the table
echo "📦 Creating DynamoDB table..."
aws dynamodb create-table \
    --table-name "$TABLE_NAME" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$REGION" \
    --tags \
        Key=Name,Value=terraform-state-lock \
        Key=Purpose,Value=terraform-state-locking \
        Key=ManagedBy,Value=cloud-custodian

echo "⏳ Waiting for table to be active..."
aws dynamodb wait table-exists --table-name "$TABLE_NAME" --region "$REGION"

echo "✅ DynamoDB table created successfully!"
echo ""
echo "Table Details:"
aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$REGION" --query 'Table.[TableName,TableStatus,BillingModeSummary.BillingMode]' --output table
