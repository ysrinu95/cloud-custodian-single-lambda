#!/bin/bash

##############################################################################
# Script: test-s3-remediation.sh
# Description: Test cross-account S3 remediation (block public access)
##############################################################################

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

# Load config
CONFIG_FILE="member-account-config.json"
if [ ! -f "$CONFIG_FILE" ]; then
    print_error "$CONFIG_FILE not found"
    exit 1
fi

MEMBER_ACCOUNT_ID=$(jq -r '.member_account_id' "$CONFIG_FILE")

print_header "Testing Cross-Account S3 Remediation"

print_info "Member Account: $MEMBER_ACCOUNT_ID"
print_info "Region: us-east-1"

# Create bucket with public access
BUCKET_NAME="test-public-bucket-$(date +%s)"

print_info "Creating S3 bucket: $BUCKET_NAME"

aws s3api create-bucket \
    --bucket "$BUCKET_NAME" \
    --region us-east-1 \
    --profile member-test

print_success "Bucket created: $BUCKET_NAME"

# Remove public access block
print_info "Removing public access block (making bucket vulnerable)..."

aws s3api delete-public-access-block \
    --bucket "$BUCKET_NAME" \
    --profile member-test

print_success "Public access block removed"

# Check initial state
print_info "Checking initial bucket configuration..."

INITIAL_CONFIG=$(aws s3api get-public-access-block \
    --bucket "$BUCKET_NAME" \
    --profile member-test 2>&1 || echo "NO_BLOCK")

if [[ "$INITIAL_CONFIG" == *"NO_BLOCK"* ]] || [[ "$INITIAL_CONFIG" == *"NoSuchPublicAccessBlockConfiguration"* ]]; then
    print_warning "Bucket is currently PUBLIC (no access block configured)"
else
    echo "$INITIAL_CONFIG"
fi

echo ""
echo "Bucket Details:"
echo "  Bucket Name: $BUCKET_NAME"
echo "  Public Access: ENABLED (vulnerable)"
echo "  Account: $MEMBER_ACCOUNT_ID"
echo ""

# Wait for CloudTrail
print_warning "Waiting 15 seconds for CloudTrail to log the CreateBucket event..."
sleep 15

# Monitor for remediation
print_info "Monitoring bucket configuration (Cloud Custodian should block public access)..."
print_info "Checking every 10 seconds for up to 2 minutes..."

for i in {1..12}; do
    CHECK_RESULT=$(aws s3api get-public-access-block \
        --bucket "$BUCKET_NAME" \
        --profile member-test 2>&1 || echo "NO_BLOCK")
    
    if [[ "$CHECK_RESULT" == *"BlockPublicAcls"* ]]; then
        BLOCK_PUBLIC_ACLS=$(echo "$CHECK_RESULT" | jq -r '.PublicAccessBlockConfiguration.BlockPublicAcls')
        IGNORE_PUBLIC_ACLS=$(echo "$CHECK_RESULT" | jq -r '.PublicAccessBlockConfiguration.IgnorePublicAcls')
        BLOCK_PUBLIC_POLICY=$(echo "$CHECK_RESULT" | jq -r '.PublicAccessBlockConfiguration.BlockPublicPolicy')
        RESTRICT_PUBLIC_BUCKETS=$(echo "$CHECK_RESULT" | jq -r '.PublicAccessBlockConfiguration.RestrictPublicBuckets')
        
        echo "  Check $i/12: BlockPublicAcls=$BLOCK_PUBLIC_ACLS, IgnorePublicAcls=$IGNORE_PUBLIC_ACLS"
        
        if [ "$BLOCK_PUBLIC_ACLS" == "true" ] && \
           [ "$IGNORE_PUBLIC_ACLS" == "true" ] && \
           [ "$BLOCK_PUBLIC_POLICY" == "true" ] && \
           [ "$RESTRICT_PUBLIC_BUCKETS" == "true" ]; then
            print_success "All public access blocks enabled by Cloud Custodian!"
            break
        fi
    else
        echo "  Check $i/12: No public access block configured yet"
    fi
    
    sleep 10
done

# Final configuration check
FINAL_CONFIG=$(aws s3api get-public-access-block \
    --bucket "$BUCKET_NAME" \
    --profile member-test 2>&1 || echo "NO_BLOCK")

print_header "S3 Remediation Test Results"

echo "Bucket Name: $BUCKET_NAME"
echo "Account: $MEMBER_ACCOUNT_ID"
echo ""

if [[ "$FINAL_CONFIG" != *"NO_BLOCK"* ]] && [[ "$FINAL_CONFIG" != *"NoSuchPublicAccessBlockConfiguration"* ]]; then
    echo "Final Configuration:"
    echo "$FINAL_CONFIG" | jq -r '.PublicAccessBlockConfiguration | to_entries | map("  \(.key): \(.value)") | .[]'
    echo ""
    
    BLOCK_PUBLIC_ACLS=$(echo "$FINAL_CONFIG" | jq -r '.PublicAccessBlockConfiguration.BlockPublicAcls')
    
    if [ "$BLOCK_PUBLIC_ACLS" == "true" ]; then
        print_success "✓ Cross-account remediation successful!"
        echo ""
        echo "The S3 bucket's public access was automatically blocked"
        echo "by Cloud Custodian running in the central account."
    else
        print_warning "Public access block partially configured"
    fi
else
    print_warning "Public access block not yet configured"
    echo ""
    echo "Possible reasons:"
    echo "  - CloudTrail event not yet processed (wait 5-15 minutes)"
    echo "  - EventBridge rule not forwarding events"
    echo "  - Lambda execution failed"
    echo ""
    echo "Check Lambda logs:"
    echo "  aws logs tail /aws/lambda/cloud-custodian-executor-dev --follow"
fi

echo ""
echo "To manually delete test bucket:"
echo "  aws s3 rb s3://$BUCKET_NAME --force --profile member-test"
