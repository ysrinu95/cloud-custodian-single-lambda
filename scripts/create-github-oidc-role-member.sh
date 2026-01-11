#!/bin/bash
# Create GitHub OIDC Role in Member Account for Terraform Deployments

set -e

MEMBER_ACCOUNT_ID="813185901390"
ROLE_NAME="GitHubActions-CloudCustodian-Role"
GITHUB_ORG="ysrinu95"
GITHUB_REPO="cloud-custodian-single-lambda"

echo "🔐 Creating GitHub OIDC provider and role in Member Account ${MEMBER_ACCOUNT_ID}..."

# Create OIDC Provider (if not exists)
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 \
  --tags Key=ManagedBy,Value=Terraform Key=Purpose,Value=GitHubActions \
  2>/dev/null || echo "OIDC provider already exists"

# Get OIDC Provider ARN
OIDC_PROVIDER_ARN=$(aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[?contains(Arn, 'token.actions.githubusercontent.com')].Arn" --output text)

echo "OIDC Provider ARN: ${OIDC_PROVIDER_ARN}"

# Create Trust Policy
cat > /tmp/github-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${OIDC_PROVIDER_ARN}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:${GITHUB_ORG}/${GITHUB_REPO}:*"
        }
      }
    }
  ]
}
EOF

# Create IAM Role
aws iam create-role \
  --role-name ${ROLE_NAME} \
  --assume-role-policy-document file:///tmp/github-trust-policy.json \
  --description "GitHub Actions role for Cloud Custodian member account deployments" \
  --tags Key=ManagedBy,Value=Manual Key=Purpose,Value=GitHubActions \
  || echo "Role already exists"

# Attach policies
echo "📋 Attaching policies..."

aws iam attach-role-policy \
  --role-name ${ROLE_NAME} \
  --policy-arn arn:aws:iam::aws:policy/PowerUserAccess

aws iam attach-role-policy \
  --role-name ${ROLE_NAME} \
  --policy-arn arn:aws:iam::aws:policy/IAMFullAccess

echo "✅ GitHub OIDC role created successfully!"
echo "Role ARN: arn:aws:iam::${MEMBER_ACCOUNT_ID}:role/${ROLE_NAME}"

# Cleanup
rm -f /tmp/github-trust-policy.json
