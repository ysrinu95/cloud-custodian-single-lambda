#!/bin/bash

##############################################################################
# Script: create-member-account.sh
# Description: Creates a new AWS member account using AWS Organizations
# Usage: ./create-member-account.sh <member-email> <account-name>
##############################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

# Check arguments
if [ $# -lt 2 ]; then
    print_error "Usage: $0 <member-email> <account-name>"
    echo ""
    echo "Example:"
    echo "  $0 aws-member-test@example.com \"Cloud Custodian Test Member\""
    exit 1
fi

MEMBER_EMAIL=$1
ACCOUNT_NAME=$2
ROLE_NAME="OrganizationAccountAccessRole"

print_header "AWS Organizations Member Account Creation"

# Step 1: Check if AWS Organizations is enabled
print_info "Checking AWS Organizations status..."

ORG_STATUS=$(aws organizations describe-organization 2>&1 || echo "NOT_ENABLED")

if [[ "$ORG_STATUS" == *"NOT_ENABLED"* ]] || [[ "$ORG_STATUS" == *"AWSOrganizationsNotInUseException"* ]]; then
    print_warning "AWS Organizations is not enabled in this account"
    read -p "Do you want to enable AWS Organizations? (yes/no): " ENABLE_ORG
    
    if [[ "$ENABLE_ORG" == "yes" ]]; then
        print_info "Enabling AWS Organizations..."
        aws organizations create-organization --feature-set ALL
        print_success "AWS Organizations enabled successfully"
    else
        print_error "AWS Organizations is required to create member accounts"
        exit 1
    fi
else
    print_success "AWS Organizations is already enabled"
    CURRENT_ORG_ID=$(echo "$ORG_STATUS" | jq -r '.Organization.Id')
    print_info "Organization ID: $CURRENT_ORG_ID"
fi

# Step 2: Get current account ID (central account)
print_info "Getting central account ID..."
CENTRAL_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
print_success "Central Account ID: $CENTRAL_ACCOUNT_ID"

# Step 3: Create member account
print_info "Creating member account..."
print_info "  Email: $MEMBER_EMAIL"
print_info "  Name: $ACCOUNT_NAME"
print_info "  Role: $ROLE_NAME"

CREATE_RESPONSE=$(aws organizations create-account \
    --email "$MEMBER_EMAIL" \
    --account-name "$ACCOUNT_NAME" \
    --role-name "$ROLE_NAME" \
    --output json)

REQUEST_ID=$(echo "$CREATE_RESPONSE" | jq -r '.CreateAccountStatus.Id')
print_info "Account creation request ID: $REQUEST_ID"

# Step 4: Wait for account creation to complete
print_info "Waiting for account creation to complete (this may take 2-5 minutes)..."

while true; do
    STATUS_RESPONSE=$(aws organizations describe-create-account-status \
        --create-account-request-id "$REQUEST_ID" \
        --output json)
    
    STATUS=$(echo "$STATUS_RESPONSE" | jq -r '.CreateAccountStatus.State')
    
    if [ "$STATUS" == "SUCCEEDED" ]; then
        print_success "Member account created successfully!"
        MEMBER_ACCOUNT_ID=$(echo "$STATUS_RESPONSE" | jq -r '.CreateAccountStatus.AccountId')
        MEMBER_ACCOUNT_NAME=$(echo "$STATUS_RESPONSE" | jq -r '.CreateAccountStatus.AccountName')
        break
    elif [ "$STATUS" == "FAILED" ]; then
        print_error "Account creation failed"
        FAILURE_REASON=$(echo "$STATUS_RESPONSE" | jq -r '.CreateAccountStatus.FailureReason')
        print_error "Reason: $FAILURE_REASON"
        exit 1
    else
        echo -n "."
        sleep 10
    fi
done

# Step 5: Display account information
print_header "Member Account Created"
echo -e "${GREEN}Account ID:${NC}       $MEMBER_ACCOUNT_ID"
echo -e "${GREEN}Account Name:${NC}     $MEMBER_ACCOUNT_NAME"
echo -e "${GREEN}Email:${NC}            $MEMBER_EMAIL"
echo -e "${GREEN}Access Role:${NC}      $ROLE_NAME"
echo -e "${GREEN}Central Account:${NC}  $CENTRAL_ACCOUNT_ID"

# Step 6: Save account information to file
CONFIG_FILE="member-account-config.json"
print_info "Saving account configuration to $CONFIG_FILE..."

cat > "$CONFIG_FILE" << EOF
{
  "member_account_id": "$MEMBER_ACCOUNT_ID",
  "member_account_name": "$MEMBER_ACCOUNT_NAME",
  "member_account_email": "$MEMBER_EMAIL",
  "central_account_id": "$CENTRAL_ACCOUNT_ID",
  "access_role_name": "$ROLE_NAME",
  "access_role_arn": "arn:aws:iam::${MEMBER_ACCOUNT_ID}:role/${ROLE_NAME}",
  "created_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

print_success "Configuration saved to $CONFIG_FILE"

# Step 7: Test access to member account
print_info "Testing access to member account..."

ASSUME_ROLE_OUTPUT=$(aws sts assume-role \
    --role-arn "arn:aws:iam::${MEMBER_ACCOUNT_ID}:role/${ROLE_NAME}" \
    --role-session-name "test-session" \
    --output json 2>&1 || echo "FAILED")

if [[ "$ASSUME_ROLE_OUTPUT" == *"FAILED"* ]]; then
    print_warning "Unable to assume role immediately (this is normal)"
    print_info "Role propagation may take a few minutes"
else
    print_success "Successfully assumed role in member account"
fi

# Step 8: Display next steps
print_header "Next Steps"

echo "1. Configure AWS CLI profile for member account:"
echo ""
echo "   Add to ~/.aws/config:"
echo ""
echo "   [profile member-test]"
echo "   role_arn = arn:aws:iam::${MEMBER_ACCOUNT_ID}:role/${ROLE_NAME}"
echo "   source_profile = default"
echo "   region = us-east-1"
echo ""
echo "2. Test member account access:"
echo ""
echo "   aws sts get-caller-identity --profile member-test"
echo ""
echo "3. Deploy member account infrastructure:"
echo ""
echo "   cd cross-account-implementation/terraform/member-account"
echo "   terraform init"
echo "   terraform apply \\"
echo "     -var=\"central_account_id=$CENTRAL_ACCOUNT_ID\" \\"
echo "     -var=\"member_account_id=$MEMBER_ACCOUNT_ID\""
echo ""
echo "4. Deploy central account infrastructure:"
echo ""
echo "   cd cross-account-implementation/terraform/central-account"
echo "   terraform init"
echo "   terraform apply \\"
echo "     -var=\"member_account_ids=[\\\"$MEMBER_ACCOUNT_ID\\\"]\" \\"
echo "     -var=\"central_account_id=$CENTRAL_ACCOUNT_ID\""
echo ""

print_success "Member account creation completed!"
print_info "Configuration saved to: $CONFIG_FILE"
