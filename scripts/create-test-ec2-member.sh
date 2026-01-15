#!/bin/bash
# ============================================================================
# Create a Test Public EC2 Instance in Member Account
# ============================================================================
# This creates a test EC2 instance to trigger Cloud Custodian policies

PROFILE="member-account"
REGION="us-east-1"
INSTANCE_TYPE="t2.micro"
AMI_ID="ami-0c02fb55b34c3f0e7"  # Amazon Linux 2023 AMI
KEY_NAME="test-key"
INSTANCE_NAME="test-public-ec2-custodian"

echo "Creating test public EC2 instance in member account..."
echo "Profile: ${PROFILE}"
echo "Region: ${REGION}"
echo ""

# Get default VPC
echo "Getting default VPC..."
VPC_ID=$(aws ec2 --profile ${PROFILE} --region ${REGION} describe-vpcs \
  --filters "Name=is-default,Values=true" \
  --query 'Vpcs[0].VpcId' --output text)

if [ "$VPC_ID" == "None" ] || [ -z "$VPC_ID" ]; then
  echo "No default VPC found. Creating one..."
  VPC_ID=$(aws ec2 --profile ${PROFILE} --region ${REGION} create-default-vpc \
    --query 'Vpc.VpcId' --output text)
fi

echo "Using VPC: ${VPC_ID}"

# Get a public subnet
echo "Getting public subnet..."
SUBNET_ID=$(aws ec2 --profile ${PROFILE} --region ${REGION} describe-subnets \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=default-for-az,Values=true" \
  --query 'Subnets[0].SubnetId' --output text)

echo "Using Subnet: ${SUBNET_ID}"

# Create or get security group that allows SSH and is too permissive (for testing)
echo "Creating security group with overly permissive rules (for testing)..."
SG_NAME="test-public-sg-custodian"
SG_ID=$(aws ec2 --profile ${PROFILE} --region ${REGION} describe-security-groups \
  --filters "Name=group-name,Values=${SG_NAME}" "Name=vpc-id,Values=${VPC_ID}" \
  --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)

if [ "$SG_ID" == "None" ] || [ -z "$SG_ID" ]; then
  echo "Creating new security group..."
  SG_ID=$(aws ec2 --profile ${PROFILE} --region ${REGION} create-security-group \
    --group-name ${SG_NAME} \
    --description "Test security group with public access for Cloud Custodian testing" \
    --vpc-id ${VPC_ID} \
    --query 'GroupId' --output text)
  
  # Add overly permissive rules (will trigger security policies)
  echo "Adding SSH access from anywhere (0.0.0.0/0)..."
  aws ec2 --profile ${PROFILE} --region ${REGION} authorize-security-group-ingress \
    --group-id ${SG_ID} \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0 2>/dev/null || echo "Rule already exists"
  
  echo "Adding HTTP access from anywhere (0.0.0.0/0)..."
  aws ec2 --profile ${PROFILE} --region ${REGION} authorize-security-group-ingress \
    --group-id ${SG_ID} \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0 2>/dev/null || echo "Rule already exists"
else
  echo "Using existing security group: ${SG_ID}"
fi

# Check if key pair exists, if not create one
echo "Checking for key pair..."
KEY_EXISTS=$(aws ec2 --profile ${PROFILE} --region ${REGION} describe-key-pairs \
  --key-names ${KEY_NAME} --query 'KeyPairs[0].KeyName' --output text 2>/dev/null)

if [ "$KEY_EXISTS" != "${KEY_NAME}" ]; then
  echo "Creating key pair..."
  aws ec2 --profile ${PROFILE} --region ${REGION} create-key-pair \
    --key-name ${KEY_NAME} \
    --query 'KeyMaterial' --output text > ~/.ssh/${KEY_NAME}.pem 2>/dev/null || true
  chmod 400 ~/.ssh/${KEY_NAME}.pem 2>/dev/null || true
  echo "Key pair created and saved to ~/.ssh/${KEY_NAME}.pem"
fi

# Launch EC2 instance
echo ""
echo "Launching EC2 instance..."
INSTANCE_ID=$(aws ec2 --profile ${PROFILE} --region ${REGION} run-instances \
  --image-id ${AMI_ID} \
  --instance-type ${INSTANCE_TYPE} \
  --key-name ${KEY_NAME} \
  --subnet-id ${SUBNET_ID} \
  --security-group-ids ${SG_ID} \
  --associate-public-ip-address \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${INSTANCE_NAME}},{Key=Environment,Value=test},{Key=Purpose,Value=custodian-testing}]" \
  --query 'Instances[0].InstanceId' --output text)

if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" == "None" ]; then
  echo "❌ Failed to create instance"
  exit 1
fi

echo "✅ Instance created: ${INSTANCE_ID}"
echo ""
echo "Waiting for instance to be running..."
aws ec2 --profile ${PROFILE} --region ${REGION} wait instance-running --instance-ids ${INSTANCE_ID}

# Get instance details
echo ""
echo "Instance Details:"
aws ec2 --profile ${PROFILE} --region ${REGION} describe-instances \
  --instance-ids ${INSTANCE_ID} \
  --query 'Reservations[0].Instances[0].{InstanceId:InstanceId,State:State.Name,PublicIP:PublicIpAddress,PrivateIP:PrivateIpAddress,InstanceType:InstanceType}' \
  --output table

echo ""
echo "=== Test Instance Created Successfully ==="
echo ""
echo "Instance ID: ${INSTANCE_ID}"
echo "Security Group: ${SG_ID} (with 0.0.0.0/0 access)"
echo ""
echo "This instance should trigger Cloud Custodian policies for:"
echo "  - Public EC2 instance detection"
echo "  - Overly permissive security group (0.0.0.0/0)"
echo "  - Unencrypted EBS volumes (if policy exists)"
echo ""
echo "Monitor CloudTrail for 'RunInstances' event"
echo "Check Security Hub for findings"
echo "Watch central account Lambda logs for policy execution"
echo ""
echo "To terminate this instance later:"
echo "  aws ec2 --profile ${PROFILE} --region ${REGION} terminate-instances --instance-ids ${INSTANCE_ID}"
