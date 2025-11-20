#!/bin/bash

##############################################################################
# Script: test-event-forwarding.sh
# Description: Test EventBridge event forwarding from member to central account
##############################################################################

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

# Load config
CONFIG_FILE="member-account-config.json"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: $CONFIG_FILE not found"
    exit 1
fi

MEMBER_ACCOUNT_ID=$(jq -r '.member_account_id' "$CONFIG_FILE")
CENTRAL_ACCOUNT_ID=$(jq -r '.central_account_id' "$CONFIG_FILE")

print_header "Testing Cross-Account Event Forwarding"

print_info "Member Account: $MEMBER_ACCOUNT_ID"
print_info "Central Account: $CENTRAL_ACCOUNT_ID"

# Send test event from member account
print_info "Sending test event from member account..."

aws events put-events \
    --entries '[
        {
            "Source": "aws.cloudtrail",
            "DetailType": "AWS API Call via CloudTrail",
            "Detail": "{\"eventName\":\"RunInstances\",\"awsRegion\":\"us-east-1\",\"sourceIPAddress\":\"10.0.0.1\",\"userAgent\":\"aws-cli\",\"requestParameters\":{\"instancesSet\":{\"items\":[{\"instanceId\":\"i-test123\"}]}}}",
            "EventBusName": "default"
        }
    ]' \
    --profile member-test

print_success "Test event sent from member account"

# Wait for event processing
print_info "Waiting 10 seconds for event to be forwarded and processed..."
sleep 10

# Check Lambda logs in central account
print_info "Checking Lambda logs in central account..."

LOG_GROUP="/aws/lambda/cloud-custodian-executor-dev"

if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP" &> /dev/null; then
    print_info "Fetching recent Lambda invocations..."
    
    aws logs tail "$LOG_GROUP" \
        --since 2m \
        --format short \
        --filter-pattern "RunInstances"
    
    print_success "Test completed! Check logs above for event processing"
else
    print_info "Lambda has not been invoked yet or logs not available"
fi

print_header "Event Forwarding Test Summary"

echo "✓ Test event sent from member account"
echo "✓ Event should be forwarded to central account EventBridge"
echo "✓ Central Lambda should process the event"
echo ""
echo "To view full logs:"
echo "  aws logs tail /aws/lambda/cloud-custodian-executor-dev --follow"
