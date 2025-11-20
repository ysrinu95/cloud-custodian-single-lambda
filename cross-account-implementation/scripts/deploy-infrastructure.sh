#!/bin/bash

##############################################################################
# Script: deploy-infrastructure.sh
# Description: Automated deployment of cross-account Cloud Custodian infrastructure
# Usage: ./deploy-infrastructure.sh
##############################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}\n"
}

print_step() {
    echo -e "\n${GREEN}► STEP $1: $2${NC}\n"
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    local missing_tools=()
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        missing_tools+=("aws-cli")
    fi
    
    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        missing_tools+=("terraform")
    fi
    
    # Check jq
    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        missing_tools+=("python3")
    fi
    
    # Check zip
    if ! command -v zip &> /dev/null; then
        missing_tools+=("zip")
    fi
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        echo ""
        echo "Please install:"
        for tool in "${missing_tools[@]}"; do
            echo "  - $tool"
        done
        exit 1
    fi
    
    print_success "All prerequisites installed"
}

# Load member account configuration
load_member_config() {
    print_header "Loading Member Account Configuration"
    
    CONFIG_FILE="member-account-config.json"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Member account configuration not found: $CONFIG_FILE"
        print_info "Please run create-member-account.sh first"
        exit 1
    fi
    
    MEMBER_ACCOUNT_ID=$(jq -r '.member_account_id' "$CONFIG_FILE")
    CENTRAL_ACCOUNT_ID=$(jq -r '.central_account_id' "$CONFIG_FILE")
    MEMBER_ACCOUNT_NAME=$(jq -r '.member_account_name' "$CONFIG_FILE")
    
    print_info "Member Account ID: $MEMBER_ACCOUNT_ID"
    print_info "Central Account ID: $CENTRAL_ACCOUNT_ID"
    print_info "Member Account Name: $MEMBER_ACCOUNT_NAME"
    
    print_success "Configuration loaded successfully"
}

# Configure AWS CLI profiles
configure_profiles() {
    print_header "Configuring AWS CLI Profiles"
    
    # Check if profiles already exist
    if aws configure list --profile member-test &> /dev/null; then
        print_info "Profile 'member-test' already exists"
    else
        print_info "Creating AWS CLI profile for member account..."
        
        # Create profile configuration
        aws configure set role_arn "arn:aws:iam::${MEMBER_ACCOUNT_ID}:role/OrganizationAccountAccessRole" --profile member-test
        aws configure set source_profile default --profile member-test
        aws configure set region us-east-1 --profile member-test
        
        print_success "Profile 'member-test' created"
    fi
    
    # Test member account access
    print_info "Testing member account access..."
    if aws sts get-caller-identity --profile member-test &> /dev/null; then
        print_success "Successfully authenticated to member account"
    else
        print_warning "Unable to access member account immediately (role propagation may take a few minutes)"
        print_info "Waiting 30 seconds for role propagation..."
        sleep 30
    fi
}

# Build Lambda deployment package
build_lambda_package() {
    print_header "Building Lambda Deployment Package"
    
    cd ../lambda
    
    print_info "Creating Lambda deployment package..."
    
    # Remove old package if exists
    rm -f lambda-function.zip
    
    # Create deployment package
    zip -r lambda-function.zip \
        lambda_handler.py \
        cross_account_executor.py \
        policy_executor.py \
        validator.py \
        requirements.txt
    
    print_success "Lambda package created: lambda-function.zip"
    
    # Copy to terraform directory
    cp lambda-function.zip ../terraform/central-account/
    print_success "Package copied to terraform directory"
    
    cd ../scripts
}

# Deploy Member Account Infrastructure
deploy_member_account() {
    print_step "1" "Deploying Member Account Infrastructure"
    
    cd ../terraform/member-account
    
    print_info "Initializing Terraform..."
    terraform init -upgrade
    
    print_info "Creating terraform.tfvars..."
    cat > terraform.tfvars << EOF
central_account_id = "$CENTRAL_ACCOUNT_ID"
member_account_id  = "$MEMBER_ACCOUNT_ID"
region            = "us-east-1"
environment       = "dev"
EOF
    
    print_info "Planning deployment..."
    terraform plan -out=tfplan
    
    print_warning "Review the plan above. Press Enter to continue with deployment or Ctrl+C to cancel..."
    read
    
    print_info "Applying infrastructure..."
    AWS_PROFILE=member-test terraform apply tfplan
    
    print_success "Member account infrastructure deployed!"
    
    # Save outputs
    terraform output -json > member-outputs.json
    
    EXECUTION_ROLE_ARN=$(terraform output -raw custodian_execution_role_arn)
    EVENTBRIDGE_RULE_ARN=$(terraform output -raw eventbridge_rule_arn)
    
    print_info "Execution Role ARN: $EXECUTION_ROLE_ARN"
    print_info "EventBridge Rule ARN: $EVENTBRIDGE_RULE_ARN"
    
    cd ../../scripts
}

# Deploy Central Account Infrastructure
deploy_central_account() {
    print_step "2" "Deploying Central Account Infrastructure"
    
    cd ../terraform/central-account
    
    print_info "Initializing Terraform..."
    terraform init -upgrade
    
    print_info "Creating terraform.tfvars..."
    cat > terraform.tfvars << EOF
central_account_id  = "$CENTRAL_ACCOUNT_ID"
member_account_ids  = ["$MEMBER_ACCOUNT_ID"]
region             = "us-east-1"
environment        = "dev"
policy_bucket_name = "custodian-policies-${CENTRAL_ACCOUNT_ID}"
EOF
    
    print_info "Planning deployment..."
    terraform plan -out=tfplan
    
    print_warning "Review the plan above. Press Enter to continue with deployment or Ctrl+C to cancel..."
    read
    
    print_info "Applying infrastructure..."
    terraform apply tfplan
    
    print_success "Central account infrastructure deployed!"
    
    # Save outputs
    terraform output -json > central-outputs.json
    
    LAMBDA_FUNCTION_NAME=$(terraform output -raw lambda_function_name)
    EVENT_BUS_ARN=$(terraform output -raw event_bus_arn)
    POLICY_BUCKET=$(terraform output -raw policy_bucket_name)
    
    print_info "Lambda Function: $LAMBDA_FUNCTION_NAME"
    print_info "Event Bus ARN: $EVENT_BUS_ARN"
    print_info "Policy Bucket: $POLICY_BUCKET"
    
    cd ../../scripts
}

# Upload policies to S3
upload_policies() {
    print_step "3" "Uploading Cloud Custodian Policies"
    
    cd ../policies
    
    POLICY_BUCKET=$(cd ../terraform/central-account && terraform output -raw policy_bucket_name)
    
    print_info "Uploading policies to S3 bucket: $POLICY_BUCKET"
    
    # Upload individual policy files
    for policy_file in *.yml; do
        if [ -f "$policy_file" ]; then
            print_info "Uploading $policy_file..."
            aws s3 cp "$policy_file" "s3://${POLICY_BUCKET}/policies/${policy_file}"
        fi
    done
    
    # Upload policy mapping
    if [ -f "policy-mapping.json" ]; then
        print_info "Uploading policy-mapping.json..."
        aws s3 cp policy-mapping.json "s3://${POLICY_BUCKET}/config/policy-mapping.json"
    fi
    
    print_success "All policies uploaded successfully"
    
    cd ../scripts
}

# Verify deployment
verify_deployment() {
    print_step "4" "Verifying Deployment"
    
    print_info "Checking member account resources..."
    
    # Check IAM role
    if aws iam get-role \
        --role-name CloudCustodianExecutionRole \
        --profile member-test &> /dev/null; then
        print_success "✓ IAM Execution Role exists"
    else
        print_error "✗ IAM Execution Role not found"
    fi
    
    # Check EventBridge rule
    if aws events describe-rule \
        --name forward-to-central-account \
        --profile member-test &> /dev/null; then
        print_success "✓ EventBridge forwarding rule exists"
    else
        print_error "✗ EventBridge forwarding rule not found"
    fi
    
    print_info "Checking central account resources..."
    
    # Check Lambda function
    if aws lambda get-function \
        --function-name cloud-custodian-executor-dev &> /dev/null; then
        print_success "✓ Lambda function exists"
    else
        print_error "✗ Lambda function not found"
    fi
    
    # Check EventBridge custom bus
    if aws events describe-event-bus \
        --name centralized-security-events-dev &> /dev/null; then
        print_success "✓ EventBridge custom bus exists"
    else
        print_error "✗ EventBridge custom bus not found"
    fi
    
    # Check S3 bucket
    POLICY_BUCKET=$(cd ../terraform/central-account && terraform output -raw policy_bucket_name)
    if aws s3 ls "s3://${POLICY_BUCKET}" &> /dev/null; then
        print_success "✓ S3 policy bucket exists"
    else
        print_error "✗ S3 policy bucket not found"
    fi
    
    print_success "Deployment verification completed"
}

# Display summary
display_summary() {
    print_header "Deployment Summary"
    
    echo -e "${GREEN}Member Account (${MEMBER_ACCOUNT_ID}):${NC}"
    echo "  ✓ IAM Execution Role: CloudCustodianExecutionRole"
    echo "  ✓ EventBridge Rule: forward-to-central-account"
    echo "  ✓ Forwarding events to central account"
    echo ""
    
    echo -e "${GREEN}Central Account (${CENTRAL_ACCOUNT_ID}):${NC}"
    echo "  ✓ EventBridge Custom Bus: centralized-security-events-dev"
    echo "  ✓ Lambda Function: cloud-custodian-executor-dev"
    echo "  ✓ S3 Policy Bucket: $POLICY_BUCKET"
    echo "  ✓ CloudWatch Logs: /aws/lambda/cloud-custodian-executor-dev"
    echo ""
    
    echo -e "${GREEN}Policies Deployed:${NC}"
    echo "  ✓ EC2: Terminate public instances"
    echo "  ✓ S3: Block public bucket access"
    echo "  ✓ Security Hub: HIGH/CRITICAL findings notifications"
    echo ""
}

# Display next steps
display_next_steps() {
    print_header "Next Steps - Testing"
    
    echo "1. Test Event Forwarding:"
    echo ""
    echo "   cd ../scripts"
    echo "   ./test-event-forwarding.sh"
    echo ""
    echo "2. Test EC2 Remediation:"
    echo ""
    echo "   cd ../scripts"
    echo "   ./test-ec2-remediation.sh"
    echo ""
    echo "3. Test S3 Remediation:"
    echo ""
    echo "   cd ../scripts"
    echo "   ./test-s3-remediation.sh"
    echo ""
    echo "4. Monitor Lambda Logs:"
    echo ""
    echo "   aws logs tail /aws/lambda/cloud-custodian-executor-dev --follow"
    echo ""
    echo "5. View Deployment Outputs:"
    echo ""
    echo "   cat ../terraform/member-account/member-outputs.json"
    echo "   cat ../terraform/central-account/central-outputs.json"
    echo ""
}

# Main execution flow
main() {
    print_header "Cloud Custodian Cross-Account Infrastructure Deployment"
    
    print_info "This script will deploy:"
    print_info "  1. Member account infrastructure (EventBridge + IAM)"
    print_info "  2. Central account infrastructure (Lambda + EventBridge + S3)"
    print_info "  3. Upload Cloud Custodian policies"
    print_info "  4. Verify deployment"
    echo ""
    
    # Step 0: Prerequisites
    check_prerequisites
    
    # Step 1: Load configuration
    load_member_config
    
    # Step 2: Configure profiles
    configure_profiles
    
    # Step 3: Build Lambda package
    build_lambda_package
    
    # Step 4: Deploy member account
    deploy_member_account
    
    # Step 5: Deploy central account
    deploy_central_account
    
    # Step 6: Upload policies
    upload_policies
    
    # Step 7: Verify deployment
    verify_deployment
    
    # Display summary and next steps
    display_summary
    display_next_steps
    
    print_header "Deployment Completed Successfully!"
}

# Run main function
main
