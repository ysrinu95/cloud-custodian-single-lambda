#!/bin/bash

# Script to delete all non-S3 resources from central and member accounts
# This keeps S3 buckets and related EventBridge rules but removes test resources

set -e

CENTRAL_ACCOUNT="172327596604"
MEMBER_ACCOUNT="813185901390"
REGION="us-east-1"

echo "=========================================="
echo "Cleaning up non-S3 resources"
echo "=========================================="

# Function to delete resources in member account
cleanup_member_account() {
    echo ""
    echo "Switching to MEMBER account ($MEMBER_ACCOUNT)..."
    export AWS_ACCESS_KEY_ID=$MEMBER_AWS_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY=$MEMBER_AWS_SECRET_ACCESS_KEY
    export AWS_SESSION_TOKEN=$MEMBER_AWS_SESSION_TOKEN
    
    echo "Current account: $(aws sts get-caller-identity --query Account --output text)"
    
    # Delete ALB resources
    echo ""
    echo "Deleting ALB resources in member account..."
    
    # Get all ALBs with prefix "test-alb"
    ALBS=$(aws elbv2 describe-load-balancers --region $REGION --query 'LoadBalancers[?starts_with(LoadBalancerName, `test-alb`)].LoadBalancerArn' --output text)
    
    if [ ! -z "$ALBS" ]; then
        for ALB_ARN in $ALBS; do
            echo "  Deleting ALB: $ALB_ARN"
            
            # Delete listeners first
            LISTENERS=$(aws elbv2 describe-listeners --load-balancer-arn $ALB_ARN --region $REGION --query 'Listeners[].ListenerArn' --output text)
            for LISTENER_ARN in $LISTENERS; do
                echo "    Deleting listener: $LISTENER_ARN"
                aws elbv2 delete-listener --listener-arn $LISTENER_ARN --region $REGION 2>/dev/null || true
            done
            
            # Delete ALB
            aws elbv2 delete-load-balancer --load-balancer-arn $ALB_ARN --region $REGION 2>/dev/null || true
            echo "    ALB deleted"
        done
    else
        echo "  No ALBs found with prefix 'test-alb'"
    fi
    
    # Delete target groups
    echo ""
    echo "Deleting target groups in member account..."
    TARGET_GROUPS=$(aws elbv2 describe-target-groups --region $REGION --query 'TargetGroups[?starts_with(TargetGroupName, `test-tg`)].TargetGroupArn' --output text)
    
    if [ ! -z "$TARGET_GROUPS" ]; then
        # Wait for ALB deletion to complete
        sleep 5
        
        for TG_ARN in $TARGET_GROUPS; do
            echo "  Deleting target group: $TG_ARN"
            aws elbv2 delete-target-group --target-group-arn $TG_ARN --region $REGION 2>/dev/null || true
        done
    else
        echo "  No target groups found with prefix 'test-tg'"
    fi
    
    # Delete EC2 instances
    echo ""
    echo "Deleting EC2 instances in member account..."
    INSTANCES=$(aws ec2 describe-instances --region $REGION \
        --filters "Name=instance-state-name,Values=running,stopped,stopping" \
        --query 'Reservations[].Instances[?Tags[?Key==`Name` && starts_with(Value, `test-`)]].InstanceId' --output text)
    
    if [ ! -z "$INSTANCES" ]; then
        echo "  Terminating instances: $INSTANCES"
        aws ec2 terminate-instances --instance-ids $INSTANCES --region $REGION
    else
        echo "  No test EC2 instances found"
    fi
    
    # Delete AMIs
    echo ""
    echo "Deleting AMIs in member account..."
    AMIS=$(aws ec2 describe-images --region $REGION --owners self \
        --query 'Images[?starts_with(Name, `test-`)].ImageId' --output text)
    
    if [ ! -z "$AMIS" ]; then
        for AMI_ID in $AMIS; do
            echo "  Deregistering AMI: $AMI_ID"
            
            # Get snapshots before deregistering
            SNAPSHOTS=$(aws ec2 describe-images --region $REGION --image-ids $AMI_ID \
                --query 'Images[].BlockDeviceMappings[].Ebs.SnapshotId' --output text)
            
            # Deregister AMI
            aws ec2 deregister-image --image-id $AMI_ID --region $REGION
            
            # Delete associated snapshots
            for SNAPSHOT_ID in $SNAPSHOTS; do
                echo "    Deleting snapshot: $SNAPSHOT_ID"
                aws ec2 delete-snapshot --snapshot-id $SNAPSHOT_ID --region $REGION 2>/dev/null || true
            done
        done
    else
        echo "  No test AMIs found"
    fi
    
    # Delete security groups (except default)
    echo ""
    echo "Deleting security groups in member account..."
    SGS=$(aws ec2 describe-security-groups --region $REGION \
        --query 'SecurityGroups[?GroupName!=`default` && starts_with(GroupName, `test-`)].GroupId' --output text)
    
    if [ ! -z "$SGS" ]; then
        # Wait for instances to terminate
        sleep 10
        
        for SG_ID in $SGS; do
            echo "  Deleting security group: $SG_ID"
            aws ec2 delete-security-group --group-id $SG_ID --region $REGION 2>/dev/null || true
        done
    else
        echo "  No test security groups found"
    fi
    
    echo ""
    echo "Member account cleanup complete!"
}

# Function to delete resources in central account
cleanup_central_account() {
    echo ""
    echo "=========================================="
    echo "Switching to CENTRAL account ($CENTRAL_ACCOUNT)..."
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
    
    echo "Current account: $(aws sts get-caller-identity --query Account --output text)"
    
    # Delete EC2 instances
    echo ""
    echo "Deleting EC2 instances in central account..."
    INSTANCES=$(aws ec2 describe-instances --region $REGION \
        --filters "Name=instance-state-name,Values=running,stopped,stopping" \
        --query 'Reservations[].Instances[?Tags[?Key==`Name` && starts_with(Value, `test-`)]].InstanceId' --output text)
    
    if [ ! -z "$INSTANCES" ]; then
        echo "  Terminating instances: $INSTANCES"
        aws ec2 terminate-instances --instance-ids $INSTANCES --region $REGION
    else
        echo "  No test EC2 instances found"
    fi
    
    # Delete AMIs
    echo ""
    echo "Deleting AMIs in central account..."
    AMIS=$(aws ec2 describe-images --region $REGION --owners self \
        --query 'Images[?starts_with(Name, `test-`)].ImageId' --output text)
    
    if [ ! -z "$AMIS" ]; then
        for AMI_ID in $AMIS; do
            echo "  Deregistering AMI: $AMI_ID"
            
            # Get snapshots before deregistering
            SNAPSHOTS=$(aws ec2 describe-images --region $REGION --image-ids $AMI_ID \
                --query 'Images[].BlockDeviceMappings[].Ebs.SnapshotId' --output text)
            
            # Deregister AMI
            aws ec2 deregister-image --image-id $AMI_ID --region $REGION
            
            # Delete associated snapshots
            for SNAPSHOT_ID in $SNAPSHOTS; do
                echo "    Deleting snapshot: $SNAPSHOT_ID"
                aws ec2 delete-snapshot --snapshot-id $SNAPSHOT_ID --region $REGION 2>/dev/null || true
            done
        done
    else
        echo "  No test AMIs found"
    fi
    
    # Delete security groups (except default)
    echo ""
    echo "Deleting security groups in central account..."
    SGS=$(aws ec2 describe-security-groups --region $REGION \
        --query 'SecurityGroups[?GroupName!=`default` && starts_with(GroupName, `test-`)].GroupId' --output text)
    
    if [ ! -z "$SGS" ]; then
        # Wait for instances to terminate
        sleep 10
        
        for SG_ID in $SGS; do
            echo "  Deleting security group: $SG_ID"
            aws ec2 delete-security-group --group-id $SG_ID --region $REGION 2>/dev/null || true
        done
    else
        echo "  No test security groups found"
    fi
    
    echo ""
    echo "Central account cleanup complete!"
}

# Main execution
echo ""
echo "This script will delete the following resources from both accounts:"
echo "  - EC2 instances (with 'test-' prefix)"
echo "  - Application Load Balancers (with 'test-alb' prefix)"
echo "  - Target Groups (with 'test-tg' prefix)"
echo "  - AMIs (with 'test-' prefix)"
echo "  - Security Groups (with 'test-' prefix)"
echo ""
echo "S3 buckets and EventBridge rules will NOT be deleted."
echo ""
read -p "Continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

# Run cleanup for both accounts
cleanup_member_account
cleanup_central_account

echo ""
echo "=========================================="
echo "Cleanup complete!"
echo "=========================================="
echo ""
echo "Summary:"
echo "  - All test resources deleted from member account ($MEMBER_ACCOUNT)"
echo "  - All test resources deleted from central account ($CENTRAL_ACCOUNT)"
echo "  - S3 buckets preserved"
echo "  - EventBridge rules preserved"
echo ""
