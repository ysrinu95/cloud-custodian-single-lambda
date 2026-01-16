#!/bin/bash
set -e

# Cleanup test VPCs created by Cloud Custodian testing
# This script removes VPCs, their dependencies (subnets, IGWs, security groups, etc.)

REGION="${AWS_REGION:-us-east-1}"
PROFILE="${AWS_PROFILE:-member-account}"

echo "🧹 Cleaning up Cloud Custodian test VPCs..."
echo "Region: $REGION"
echo "Profile: $PROFILE"
echo ""

# Get all custodian test VPCs
VPC_IDS=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=custodian-test-vpc" \
  --query 'Vpcs[*].VpcId' \
  --output text \
  --region $REGION \
  --profile $PROFILE)

if [ -z "$VPC_IDS" ]; then
  echo "✅ No test VPCs found to clean up"
  exit 0
fi

echo "Found VPCs to delete: $VPC_IDS"
echo ""

for VPC_ID in $VPC_IDS; do
  echo "🗑️  Deleting VPC: $VPC_ID"
  
  # 1. Terminate EC2 instances
  echo "  → Terminating EC2 instances..."
  INSTANCE_IDS=$(aws ec2 describe-instances \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=instance-state-name,Values=running,stopped,stopping" \
    --query 'Reservations[*].Instances[*].InstanceId' \
    --output text \
    --region $REGION \
    --profile $PROFILE)
  
  if [ -n "$INSTANCE_IDS" ]; then
    for INSTANCE_ID in $INSTANCE_IDS; do
      echo "    Terminating instance: $INSTANCE_ID"
      aws ec2 terminate-instances \
        --instance-ids $INSTANCE_ID \
        --region $REGION \
        --profile $PROFILE || echo "    ⚠️  Failed to terminate instance $INSTANCE_ID"
    done
    
    echo "    ⏳ Waiting for instances to terminate..."
    aws ec2 wait instance-terminated \
      --instance-ids $INSTANCE_IDS \
      --region $REGION \
      --profile $PROFILE || echo "    ⚠️  Timeout waiting for instances to terminate"
  fi
  
  # 2. Release Elastic IPs
  echo "  → Releasing Elastic IPs..."
  ALLOCATION_IDS=$(aws ec2 describe-addresses \
    --filters "Name=domain,Values=vpc" \
    --query "Addresses[?NetworkInterfaceId!=null]|[?starts_with(NetworkInterfaceId, 'eni-')].AllocationId" \
    --output text \
    --region $REGION \
    --profile $PROFILE)
  
  for ALLOC_ID in $ALLOCATION_IDS; do
    # Check if EIP is associated with our VPC
    EIP_VPC=$(aws ec2 describe-addresses \
      --allocation-ids $ALLOC_ID \
      --query 'Addresses[0].InstanceId' \
      --output text \
      --region $REGION \
      --profile $PROFILE 2>/dev/null)
    
    if [ "$EIP_VPC" != "None" ]; then
      echo "    Releasing EIP: $ALLOC_ID"
      aws ec2 release-address \
        --allocation-id $ALLOC_ID \
        --region $REGION \
        --profile $PROFILE || echo "    ⚠️  Failed to release EIP $ALLOC_ID"
    fi
  done
  
  # 3. Delete network interfaces
  echo "  → Deleting network interfaces..."
  ENI_IDS=$(aws ec2 describe-network-interfaces \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'NetworkInterfaces[*].NetworkInterfaceId' \
    --output text \
    --region $REGION \
    --profile $PROFILE)
  
  for ENI_ID in $ENI_IDS; do
    # Check if ENI is attached
    ATTACHMENT_ID=$(aws ec2 describe-network-interfaces \
      --network-interface-ids $ENI_ID \
      --query 'NetworkInterfaces[0].Attachment.AttachmentId' \
      --output text \
      --region $REGION \
      --profile $PROFILE)
    
    if [ "$ATTACHMENT_ID" != "None" ] && [ -n "$ATTACHMENT_ID" ]; then
      echo "    Detaching ENI: $ENI_ID"
      aws ec2 detach-network-interface \
        --attachment-id $ATTACHMENT_ID \
        --region $REGION \
        --profile $PROFILE --force || echo "    ⚠️  Failed to detach ENI $ENI_ID"
      sleep 5
    fi
    
    echo "    Deleting ENI: $ENI_ID"
    aws ec2 delete-network-interface \
      --network-interface-id $ENI_ID \
      --region $REGION \
      --profile $PROFILE || echo "    ⚠️  Failed to delete ENI $ENI_ID"
  done
  
  # 4. Delete subnets
  echo "  → Deleting subnets..."
  SUBNET_IDS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'Subnets[*].SubnetId' \
    --output text \
    --region $REGION \
    --profile $PROFILE)
  
  for SUBNET_ID in $SUBNET_IDS; do
    echo "    Deleting subnet: $SUBNET_ID"
    aws ec2 delete-subnet \
      --subnet-id $SUBNET_ID \
      --region $REGION \
      --profile $PROFILE || echo "    ⚠️  Failed to delete subnet $SUBNET_ID"
  done
  
  # 5. Detach and delete internet gateways
  echo "  → Detaching and deleting internet gateways..."
  IGW_IDS=$(aws ec2 describe-internet-gateways \
    --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
    --query 'InternetGateways[*].InternetGatewayId' \
    --output text \
    --region $REGION \
    --profile $PROFILE)
  
  for IGW_ID in $IGW_IDS; do
    echo "    Detaching IGW: $IGW_ID"
    aws ec2 detach-internet-gateway \
      --internet-gateway-id $IGW_ID \
      --vpc-id $VPC_ID \
      --region $REGION \
      --profile $PROFILE || echo "    ⚠️  Failed to detach IGW $IGW_ID"
    
    echo "    Deleting IGW: $IGW_ID"
    aws ec2 delete-internet-gateway \
      --internet-gateway-id $IGW_ID \
      --region $REGION \
      --profile $PROFILE || echo "    ⚠️  Failed to delete IGW $IGW_ID"
  done
  
  # 6. Delete route table associations and custom route tables
  echo "  → Deleting custom route tables..."
  RT_IDS=$(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' \
    --output text \
    --region $REGION \
    --profile $PROFILE)
  
  for RT_ID in $RT_IDS; do
    echo "    Deleting route table: $RT_ID"
    aws ec2 delete-route-table \
      --route-table-id $RT_ID \
      --region $REGION \
      --profile $PROFILE || echo "    ⚠️  Failed to delete route table $RT_ID"
  done
  
  # 7. Delete security groups (except default)
  echo "  → Deleting security groups..."
  SG_IDS=$(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
    --output text \
    --region $REGION \
    --profile $PROFILE)
  
  for SG_ID in $SG_IDS; do
    echo "    Deleting security group: $SG_ID"
    aws ec2 delete-security-group \
      --group-id $SG_ID \
      --region $REGION \
      --profile $PROFILE || echo "    ⚠️  Failed to delete security group $SG_ID"
  done
  
  # 8. Delete network ACLs (except default)
  echo "  → Deleting network ACLs..."
  NACL_IDS=$(aws ec2 describe-network-acls \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'NetworkAcls[?IsDefault==`false`].NetworkAclId' \
    --output text \
    --region $REGION \
    --profile $PROFILE)
  
  for NACL_ID in $NACL_IDS; do
    echo "    Deleting network ACL: $NACL_ID"
    aws ec2 delete-network-acl \
      --network-acl-id $NACL_ID \
      --region $REGION \
      --profile $PROFILE || echo "    ⚠️  Failed to delete network ACL $NACL_ID"
  done
  
  # 9. Finally, delete the VPC
  echo "  → Deleting VPC..."
  aws ec2 delete-vpc \
    --vpc-id $VPC_ID \
    --region $REGION \
    --profile $PROFILE
  
  echo "✅ VPC $VPC_ID deleted successfully"
  echo ""
done

echo "✅ All test VPCs cleaned up successfully!"
