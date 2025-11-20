#!/bin/bash

##############################################################################
# Script: test-ec2-remediation.sh
# Description: Test cross-account EC2 remediation (terminate public instances)
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

print_header "Testing Cross-Account EC2 Remediation"

print_info "Member Account: $MEMBER_ACCOUNT_ID"
print_info "Region: us-east-1"

# Get latest Amazon Linux 2 AMI
print_info "Finding latest Amazon Linux 2 AMI..."
AMI_ID=$(aws ec2 describe-images \
    --owners amazon \
    --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
    --output text \
    --region us-east-1 \
    --profile member-test)

print_info "Using AMI: $AMI_ID"

# Launch EC2 instance with public IP
print_info "Launching EC2 instance with public IP in member account..."

INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type t2.micro \
    --associate-public-ip-address \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=Test-Public-Instance},{Key=Environment,Value=Test}]' \
    --region us-east-1 \
    --profile member-test \
    --query 'Instances[0].InstanceId' \
    --output text)

print_success "EC2 instance launched: $INSTANCE_ID"

# Wait for instance to be running
print_info "Waiting for instance to reach 'running' state..."
aws ec2 wait instance-running \
    --instance-ids "$INSTANCE_ID" \
    --region us-east-1 \
    --profile member-test

print_success "Instance is now running"

# Get instance details
print_info "Retrieving instance details..."
INSTANCE_INFO=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region us-east-1 \
    --profile member-test \
    --query 'Reservations[0].Instances[0].[PublicIpAddress,State.Name]' \
    --output text)

PUBLIC_IP=$(echo "$INSTANCE_INFO" | cut -f1)
STATE=$(echo "$INSTANCE_INFO" | cut -f2)

echo ""
echo "Instance Details:"
echo "  Instance ID: $INSTANCE_ID"
echo "  Public IP: $PUBLIC_IP"
echo "  State: $STATE"
echo ""

# Wait for CloudTrail to log the event
print_warning "Waiting 15 seconds for CloudTrail to log the RunInstances event..."
sleep 15

# Monitor for remediation
print_info "Monitoring instance state (Cloud Custodian should terminate it)..."
print_info "Checking every 10 seconds for up to 2 minutes..."

for i in {1..12}; do
    CURRENT_STATE=$(aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --region us-east-1 \
        --profile member-test \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text)
    
    echo "  Check $i/12: State = $CURRENT_STATE"
    
    if [ "$CURRENT_STATE" == "terminated" ] || [ "$CURRENT_STATE" == "terminating" ]; then
        print_success "Instance is being terminated by Cloud Custodian!"
        break
    fi
    
    sleep 10
done

# Final state check
FINAL_STATE=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region us-east-1 \
    --profile member-test \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text)

print_header "EC2 Remediation Test Results"

echo "Instance ID: $INSTANCE_ID"
echo "Initial State: running (with public IP: $PUBLIC_IP)"
echo "Final State: $FINAL_STATE"
echo ""

if [ "$FINAL_STATE" == "terminated" ] || [ "$FINAL_STATE" == "terminating" ]; then
    print_success "✓ Cross-account remediation successful!"
    echo ""
    echo "The EC2 instance with a public IP was automatically terminated"
    echo "by Cloud Custodian running in the central account."
else
    print_warning "Instance is still $FINAL_STATE"
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
echo "To manually terminate (if needed):"
echo "  aws ec2 terminate-instances --instance-ids $INSTANCE_ID --profile member-test"
