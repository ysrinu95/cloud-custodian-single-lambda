# EC2 Security Policies - Demo Scenarios

This document provides step-by-step demo scenarios for testing each Cloud Custodian EC2 security policy.

---

## Prerequisites

- AWS CLI configured with appropriate credentials
- Member account profile: `member-account`
- Region: `us-east-1`
- Required permissions: EC2, EBS, AMI management

---

## Policy 1: AMI Publicly Accessible

**Policy Name:** `ami-publicly-accessible`  
**Trigger:** Realtime (EventBridge) / Periodic  
**Detection:** Amazon Machine Images (AMIs) that are publicly accessible

### Demo Scenario

#### Step 1: Create a Private AMI
```bash
# Launch a test EC2 instance first (if needed)
INSTANCE_ID=$(aws ec2 run-instances \
  --profile member-account \
  --region us-east-1 \
  --image-id ami-0c02fb55b34c3f0e7 \
  --instance-type t2.micro \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=test-ami-source}]' \
  --query 'Instances[0].InstanceId' --output text)

# Wait for instance to be running
aws ec2 wait instance-running --profile member-account --instance-ids $INSTANCE_ID

# Create AMI from instance
AMI_ID=$(aws ec2 create-image \
  --profile member-account \
  --region us-east-1 \
  --instance-id $INSTANCE_ID \
  --name "test-public-ami-demo-$(date +%s)" \
  --description "Test AMI for public access demo" \
  --query 'ImageId' --output text)

echo "Created AMI: $AMI_ID"
```

#### Step 2: Make AMI Public (Trigger Policy)
```bash
# Make AMI publicly accessible
aws ec2 modify-image-attribute \
  --profile member-account \
  --region us-east-1 \
  --image-id $AMI_ID \
  --launch-permission "Add=[{Group=all}]"

echo "✓ AMI is now public - Policy should trigger"
```

#### Step 3: Verify Detection
```bash
# Check AMI permissions
aws ec2 describe-images \
  --profile member-account \
  --region us-east-1 \
  --image-ids $AMI_ID \
  --query 'Images[0].{ImageId:ImageId,Public:Public,Name:Name}'

# Check CloudWatch Logs for Lambda execution
# Check SQS queue for notification
# Check email for alert
```

#### Step 4: Verify Remediation
```bash
# Cloud Custodian will automatically remove public access
# Verify AMI is now private
aws ec2 describe-images \
  --profile member-account \
  --region us-east-1 \
  --image-ids $AMI_ID \
  --query 'Images[0].Public'
```

#### Cleanup
```bash
# Deregister AMI
aws ec2 deregister-image --profile member-account --region us-east-1 --image-id $AMI_ID

# Terminate source instance
aws ec2 terminate-instances --profile member-account --region us-east-1 --instance-ids $INSTANCE_ID
```

---

## Policy 2: EBS Snapshot Not Encrypted

**Policy Name:** `ebs-snapshot-unencrypted`  
**Trigger:** Realtime (EventBridge) / Periodic  
**Detection:** EBS snapshots that are not encrypted

### Demo Scenario

#### Step 1: Create Unencrypted Volume
```bash
# Create an unencrypted EBS volume
VOLUME_ID=$(aws ec2 create-volume \
  --profile member-account \
  --region us-east-1 \
  --availability-zone us-east-1a \
  --size 8 \
  --volume-type gp3 \
  --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value=test-unencrypted-volume}]' \
  --query 'VolumeId' --output text)

echo "Created unencrypted volume: $VOLUME_ID"

# Wait for volume to be available
aws ec2 wait volume-available --profile member-account --region us-east-1 --volume-ids $VOLUME_ID
```

#### Step 2: Create Unencrypted Snapshot (Trigger Policy)
```bash
# Create snapshot of unencrypted volume
SNAPSHOT_ID=$(aws ec2 create-snapshot \
  --profile member-account \
  --region us-east-1 \
  --volume-id $VOLUME_ID \
  --description "Test unencrypted snapshot for demo" \
  --tag-specifications 'ResourceType=snapshot,Tags=[{Key=Name,Value=test-unencrypted-snapshot}]' \
  --query 'SnapshotId' --output text)

echo "✓ Created unencrypted snapshot: $SNAPSHOT_ID - Policy should trigger"
```

#### Step 3: Verify Detection
```bash
# Check snapshot encryption status
aws ec2 describe-snapshots \
  --profile member-account \
  --region us-east-1 \
  --snapshot-ids $SNAPSHOT_ID \
  --query 'Snapshots[0].{SnapshotId:SnapshotId,Encrypted:Encrypted,VolumeSize:VolumeSize}'

# Monitor CloudWatch Logs and email notifications
```

#### Cleanup
```bash
# Delete snapshot
aws ec2 delete-snapshot --profile member-account --region us-east-1 --snapshot-id $SNAPSHOT_ID

# Delete volume
aws ec2 delete-volume --profile member-account --region us-east-1 --volume-id $VOLUME_ID
```

---

## Policy 3: EBS Snapshot Publicly Accessible

**Policy Name:** `ebs-snapshot-public`  
**Trigger:** Realtime (EventBridge) / Periodic  
**Detection:** EBS snapshots that are publicly accessible

### Demo Scenario

#### Step 1: Create a Snapshot
```bash
# Use the volume from previous demo or create new one
VOLUME_ID=$(aws ec2 create-volume \
  --profile member-account \
  --region us-east-1 \
  --availability-zone us-east-1a \
  --size 8 \
  --volume-type gp3 \
  --query 'VolumeId' --output text)

aws ec2 wait volume-available --profile member-account --region us-east-1 --volume-ids $VOLUME_ID

SNAPSHOT_ID=$(aws ec2 create-snapshot \
  --profile member-account \
  --region us-east-1 \
  --volume-id $VOLUME_ID \
  --description "Test snapshot for public access demo" \
  --query 'SnapshotId' --output text)

# Wait for snapshot to complete
aws ec2 wait snapshot-completed --profile member-account --region us-east-1 --snapshot-ids $SNAPSHOT_ID
```

#### Step 2: Make Snapshot Public (Trigger Policy)
```bash
# Make snapshot publicly accessible
aws ec2 modify-snapshot-attribute \
  --profile member-account \
  --region us-east-1 \
  --snapshot-id $SNAPSHOT_ID \
  --create-volume-permission "Add=[{Group=all}]"

echo "✓ Snapshot is now public - Policy should trigger"
```

#### Step 3: Verify Detection
```bash
# Check snapshot permissions
aws ec2 describe-snapshot-attribute \
  --profile member-account \
  --region us-east-1 \
  --snapshot-id $SNAPSHOT_ID \
  --attribute createVolumePermission

# Monitor for notifications
```

#### Step 4: Verify Remediation
```bash
# Cloud Custodian will automatically remove public access
# Verify snapshot is now private
aws ec2 describe-snapshot-attribute \
  --profile member-account \
  --region us-east-1 \
  --snapshot-id $SNAPSHOT_ID \
  --attribute createVolumePermission
```

#### Cleanup
```bash
aws ec2 delete-snapshot --profile member-account --region us-east-1 --snapshot-id $SNAPSHOT_ID
aws ec2 delete-volume --profile member-account --region us-east-1 --volume-id $VOLUME_ID
```

---

## Policy 4: EC2 Instance with Unencrypted EBS Volume

**Policy Name:** `ec2-unencrypted-ebs-volume`  
**Trigger:** CloudTrail / Periodic  
**Detection:** EC2 instances with unencrypted EBS volumes attached

### Demo Scenario

#### Step 1: Launch EC2 with Unencrypted Volume (Trigger Policy)
```bash
# Launch instance with unencrypted root volume
INSTANCE_ID=$(aws ec2 run-instances \
  --profile member-account \
  --region us-east-1 \
  --image-id ami-0c02fb55b34c3f0e7 \
  --instance-type t2.micro \
  --block-device-mappings '[
    {
      "DeviceName": "/dev/xvda",
      "Ebs": {
        "VolumeSize": 8,
        "VolumeType": "gp3",
        "Encrypted": false,
        "DeleteOnTermination": true
      }
    }
  ]' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=test-unencrypted-ebs}]' \
  --query 'Instances[0].InstanceId' --output text)

echo "✓ Launched instance with unencrypted volume: $INSTANCE_ID - Policy should trigger"
```

#### Step 2: Verify Detection
```bash
# Check instance volumes
aws ec2 describe-instances \
  --profile member-account \
  --region us-east-1 \
  --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].BlockDeviceMappings[*].Ebs.{VolumeId:VolumeId}'

# Check volume encryption status
VOLUME_ID=$(aws ec2 describe-instances \
  --profile member-account \
  --region us-east-1 \
  --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.VolumeId' --output text)

aws ec2 describe-volumes \
  --profile member-account \
  --region us-east-1 \
  --volume-ids $VOLUME_ID \
  --query 'Volumes[0].{VolumeId:VolumeId,Encrypted:Encrypted,Size:Size}'

# Monitor notifications
```

#### Cleanup
```bash
aws ec2 terminate-instances --profile member-account --region us-east-1 --instance-ids $INSTANCE_ID
```

---

## Policy 5: EC2 IMDSv1 Enabled

**Policy Name:** `ec2-imdsv1-enabled`  
**Trigger:** CloudTrail / Periodic  
**Detection:** EC2 instances with IMDSv1 enabled (should use IMDSv2 only)

### Demo Scenario

#### Step 1: Launch EC2 with IMDSv1 (Trigger Policy)
```bash
# Launch instance with IMDSv1 enabled (optional tokens)
INSTANCE_ID=$(aws ec2 run-instances \
  --profile member-account \
  --region us-east-1 \
  --image-id ami-0c02fb55b34c3f0e7 \
  --instance-type t2.micro \
  --metadata-options "HttpTokens=optional,HttpPutResponseHopLimit=1" \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=test-imdsv1-enabled}]' \
  --query 'Instances[0].InstanceId' --output text)

echo "✓ Launched instance with IMDSv1 enabled: $INSTANCE_ID - Policy should trigger"
```

#### Step 2: Verify Detection
```bash
# Check IMDS configuration
aws ec2 describe-instances \
  --profile member-account \
  --region us-east-1 \
  --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].MetadataOptions.{HttpTokens:HttpTokens,HttpPutResponseHopLimit:HttpPutResponseHopLimit}'

# Monitor for notifications
```

#### Step 3: Verify Remediation
```bash
# Cloud Custodian will enforce IMDSv2
# Verify configuration changed
aws ec2 describe-instances \
  --profile member-account \
  --region us-east-1 \
  --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].MetadataOptions.HttpTokens'
# Should show "required"
```

#### Cleanup
```bash
aws ec2 terminate-instances --profile member-account --region us-east-1 --instance-ids $INSTANCE_ID
```

---

## Policy 6: EC2 Instance with Public IP (Auto-Terminate)

**Policy Name:** `ec2-stop-instances-on-launch`  
**Trigger:** Realtime (EventBridge - RunInstances)  
**Detection:** EC2 instances launched with public IP address  
**Action:** Automatic termination

### Demo Scenario

#### Step 1: Launch Public EC2 Instance (Trigger Policy)
```bash
# Get default VPC and public subnet
VPC_ID=$(aws ec2 describe-vpcs \
  --profile member-account \
  --region us-east-1 \
  --filters "Name=is-default,Values=true" \
  --query 'Vpcs[0].VpcId' --output text)

SUBNET_ID=$(aws ec2 describe-subnets \
  --profile member-account \
  --region us-east-1 \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'Subnets[0].SubnetId' --output text)

# Launch instance with public IP
INSTANCE_ID=$(aws ec2 run-instances \
  --profile member-account \
  --region us-east-1 \
  --image-id ami-0c02fb55b34c3f0e7 \
  --instance-type t2.micro \
  --subnet-id $SUBNET_ID \
  --associate-public-ip-address \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=test-public-ip-auto-terminate},{Key=Purpose,Value=demo}]' \
  --query 'Instances[0].InstanceId' --output text)

echo "✓ Launched instance with public IP: $INSTANCE_ID - Policy will auto-terminate"
```

#### Step 2: Verify Detection and Termination
```bash
# Check instance status immediately
aws ec2 describe-instances \
  --profile member-account \
  --region us-east-1 \
  --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].{InstanceId:InstanceId,State:State.Name,PublicIP:PublicIpAddress}'

# Wait a few moments for policy to execute
sleep 30

# Verify instance is terminated or terminating
aws ec2 describe-instances \
  --profile member-account \
  --region us-east-1 \
  --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].State.Name'
# Should show "terminated" or "terminating"

# Check CloudWatch Logs for Lambda execution
# Check email for termination notification
```

#### Step 3: Verify Notification Received
```bash
# Check SQS queue for notification message
aws sqs receive-message \
  --profile default \
  --region us-east-1 \
  --queue-url https://sqs.us-east-1.amazonaws.com/172327596604/aikyam-cloud-custodian-realtime-notifications \
  --max-number-of-messages 10

# Email notification should include:
# - Instance ID
# - Public IP address
# - Created by user
# - Termination action taken
```

---

## Testing All Policies Together

### Complete End-to-End Demo Script

```bash
#!/bin/bash
# Complete demo of all EC2 security policies

PROFILE="member-account"
REGION="us-east-1"

echo "=== EC2 Security Policies Demo ==="
echo ""

# 1. Public EC2 Instance (Auto-terminate)
echo "1. Testing: EC2 with Public IP (Auto-terminate)..."
INSTANCE_ID=$(aws ec2 run-instances \
  --profile $PROFILE --region $REGION \
  --image-id ami-0c02fb55b34c3f0e7 \
  --instance-type t2.micro \
  --associate-public-ip-address \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=demo-public-ec2}]' \
  --query 'Instances[0].InstanceId' --output text)
echo "   Created instance: $INSTANCE_ID (will be auto-terminated)"

sleep 5

# 2. Unencrypted Volume
echo ""
echo "2. Testing: Unencrypted EBS Volume..."
VOLUME_ID=$(aws ec2 create-volume \
  --profile $PROFILE --region $REGION \
  --availability-zone ${REGION}a \
  --size 8 --volume-type gp3 \
  --query 'VolumeId' --output text)
echo "   Created volume: $VOLUME_ID"

# 3. Unencrypted Snapshot
echo ""
echo "3. Testing: Unencrypted Snapshot..."
aws ec2 wait volume-available --profile $PROFILE --region $REGION --volume-ids $VOLUME_ID
SNAPSHOT_ID=$(aws ec2 create-snapshot \
  --profile $PROFILE --region $REGION \
  --volume-id $VOLUME_ID \
  --description "Demo unencrypted snapshot" \
  --query 'SnapshotId' --output text)
echo "   Created snapshot: $SNAPSHOT_ID"

# 4. Public Snapshot
echo ""
echo "4. Testing: Public Snapshot..."
aws ec2 wait snapshot-completed --profile $PROFILE --region $REGION --snapshot-ids $SNAPSHOT_ID
aws ec2 modify-snapshot-attribute \
  --profile $PROFILE --region $REGION \
  --snapshot-id $SNAPSHOT_ID \
  --create-volume-permission "Add=[{Group=all}]"
echo "   Made snapshot public"

# 5. IMDSv1 Instance
echo ""
echo "5. Testing: IMDSv1 Enabled..."
IMDS_INSTANCE=$(aws ec2 run-instances \
  --profile $PROFILE --region $REGION \
  --image-id ami-0c02fb55b34c3f0e7 \
  --instance-type t2.micro \
  --metadata-options "HttpTokens=optional" \
  --no-associate-public-ip-address \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=demo-imdsv1}]' \
  --query 'Instances[0].InstanceId' --output text)
echo "   Created instance with IMDSv1: $IMDS_INSTANCE"

echo ""
echo "=== Demo Complete ==="
echo "Monitor CloudWatch Logs and email for policy notifications"
echo ""
echo "Cleanup commands:"
echo "aws ec2 terminate-instances --profile $PROFILE --instance-ids $IMDS_INSTANCE"
echo "aws ec2 delete-snapshot --profile $PROFILE --snapshot-id $SNAPSHOT_ID"
echo "aws ec2 delete-volume --profile $PROFILE --volume-id $VOLUME_ID"
```

---

## Monitoring Policy Execution

### Check CloudWatch Logs
```bash
# View Lambda function logs
aws logs tail /aws/lambda/aikyam-cloud-custodian-main \
  --profile default \
  --region us-east-1 \
  --follow

# View mailer logs
aws logs tail /aws/lambda/aikyam-cloud-custodian-mailer \
  --profile default \
  --region us-east-1 \
  --follow
```

### Check SQS Queue
```bash
# Check for pending notifications
aws sqs get-queue-attributes \
  --profile default \
  --region us-east-1 \
  --queue-url https://sqs.us-east-1.amazonaws.com/172327596604/aikyam-cloud-custodian-realtime-notifications \
  --attribute-names ApproximateNumberOfMessages
```

### Check EventBridge Rules
```bash
# List active rules
aws events list-rules \
  --profile member-account \
  --region us-east-1 \
  --name-prefix aikyam-cloud-custodian

# Check rule targets
aws events list-targets-by-rule \
  --profile member-account \
  --region us-east-1 \
  --rule aikyam-cloud-custodian-forward-security-events-to-central
```

---

## Expected Outcomes

| Policy | Detection Time | Notification | Auto-Remediation |
|--------|---------------|--------------|------------------|
| AMI Public | < 5 minutes | ✅ Email + SQS | ✅ Remove permissions |
| Snapshot Unencrypted | < 5 minutes | ✅ Email + SQS | ❌ Manual |
| Snapshot Public | < 5 minutes | ✅ Email + SQS | ✅ Remove permissions |
| EC2 Unencrypted Volume | < 5 minutes | ✅ Email + SQS | ❌ Manual |
| IMDSv1 Enabled | < 5 minutes | ✅ Email + SQS | ✅ Enforce IMDSv2 |
| Public EC2 Instance | < 1 minute | ✅ Email + SQS | ✅ Auto-terminate |

---

## Troubleshooting

### Policy Not Triggering
1. Check EventBridge rule is enabled in member account
2. Verify IAM role has permissions to forward events to central account
3. Check Lambda execution role has required permissions
4. Review CloudWatch Logs for errors

### Notifications Not Received
1. Verify SQS queue exists and has proper permissions
2. Check mailer Lambda is subscribed to SQS queue
3. Verify email address in policy configuration
4. Check SES email verification status

### Remediation Not Working
1. Verify Lambda execution role has remediation permissions
2. Check CloudWatch Logs for permission errors
3. Ensure resources are in the correct account/region
4. Review IAM policies for required actions

---

## Additional Resources

- [Cloud Custodian Documentation](https://cloudcustodian.io/docs/)
- [AWS Security Hub Best Practices](https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-standards-fsbp-controls.html)
- [EC2 Security Best Practices](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-security.html)
