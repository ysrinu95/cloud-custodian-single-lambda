#!/bin/bash
# Clean up existing resources that conflict with Terraform

set -e

echo "🧹 Cleaning up existing AWS resources that conflict with Terraform..."

# Delete existing IAM role if it exists
echo "Checking CloudCustodianExecutionRole..."
if aws iam get-role --role-name CloudCustodianExecutionRole 2>/dev/null; then
  echo "  Detaching policies..."
  for policy in $(aws iam list-attached-role-policies --role-name CloudCustodianExecutionRole --query 'AttachedPolicies[].PolicyArn' --output text); do
    aws iam detach-role-policy --role-name CloudCustodianExecutionRole --policy-arn "$policy"
  done
  
  for policy in $(aws iam list-role-policies --role-name CloudCustodianExecutionRole --query 'PolicyNames[]' --output text); do
    aws iam delete-role-policy --role-name CloudCustodianExecutionRole --policy-name "$policy"
  done
  
  echo "  Deleting role..."
  aws iam delete-role --role-name CloudCustodianExecutionRole
  echo "  ✅ Role deleted"
else
  echo "  Role doesn't exist, skipping"
fi

# Delete existing S3 bucket if it exists (only if empty or with --force flag)
echo "Checking S3 bucket aikyam-cloud-custodian-data..."
if aws s3 ls s3://aikyam-cloud-custodian-data 2>/dev/null; then
  echo "  ⚠️  Bucket exists. Import it or delete manually if needed"
  echo "     To delete: aws s3 rb s3://aikyam-cloud-custodian-data --force"
else
  echo "  Bucket doesn't exist, skipping"
fi

# Delete existing SQS queue if it exists
echo "Checking SQS queue custodian-mailer-queue..."
QUEUE_URL=$(aws sqs get-queue-url --queue-name custodian-mailer-queue --query 'QueueUrl' --output text 2>/dev/null || echo "")
if [ -n "$QUEUE_URL" ]; then
  echo "  Deleting queue..."
  aws sqs delete-queue --queue-url "$QUEUE_URL"
  echo "  ✅ Queue deleted"
else
  echo "  Queue doesn't exist, skipping"
fi

echo ""
echo "✅ Cleanup complete! You can now run terraform apply"
