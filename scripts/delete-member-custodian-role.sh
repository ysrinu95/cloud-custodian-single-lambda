#!/bin/bash
set -e

MEMBER_ACCOUNT_ID="813185901390"
ROLE_NAME="CloudCustodianExecutionRole"

echo "🔍 Checking IAM role in member account: $MEMBER_ACCOUNT_ID"

# Check if role exists
if ! aws iam get-role --role-name $ROLE_NAME 2>/dev/null; then
  echo "✅ Role $ROLE_NAME does not exist. Nothing to delete."
  exit 0
fi

echo "🗑️  Deleting IAM role: $ROLE_NAME"

# List and detach all managed policies
echo "📎 Detaching managed policies..."
MANAGED_POLICIES=$(aws iam list-attached-role-policies --role-name $ROLE_NAME --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
if [ -n "$MANAGED_POLICIES" ]; then
  for policy_arn in $MANAGED_POLICIES; do
    echo "  ➖ Detaching: $policy_arn"
    aws iam detach-role-policy --role-name $ROLE_NAME --policy-arn $policy_arn
  done
else
  echo "  ℹ️  No managed policies attached"
fi

# List and delete all inline policies
echo "📝 Deleting inline policies..."
INLINE_POLICIES=$(aws iam list-role-policies --role-name $ROLE_NAME --query 'PolicyNames' --output text 2>/dev/null || echo "")
if [ -n "$INLINE_POLICIES" ]; then
  for policy_name in $INLINE_POLICIES; do
    echo "  ➖ Deleting: $policy_name"
    aws iam delete-role-policy --role-name $ROLE_NAME --policy-name $policy_name
  done
else
  echo "  ℹ️  No inline policies found"
fi

# Delete the role
echo "🗑️  Deleting role: $ROLE_NAME"
aws iam delete-role --role-name $ROLE_NAME

echo "✅ Successfully deleted role: $ROLE_NAME from account $MEMBER_ACCOUNT_ID"
