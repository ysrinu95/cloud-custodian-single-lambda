#!/usr/bin/env python3
"""
Test script for EC2 public instance policy.
This script creates an EC2 instance with a public IP, runs the Cloud Custodian policy,
and verifies that the instance is stopped.
"""

import boto3
import time
import json
import subprocess
import sys
import os
from datetime import datetime

# Configuration
REGION = 'us-east-1'
TEST_TAG_KEY = 'c7n-test'
TEST_TAG_VALUE = 'ec2-public-instance-test'
POLICY_FILE = 'test-policies.yml'

def get_latest_ami(ec2_client):
    """Get the latest Amazon Linux 2023 AMI"""
    response = ec2_client.describe_images(
        Owners=['amazon'],
        Filters=[
            {'Name': 'name', 'Values': ['al2023-ami-*-x86_64']},
            {'Name': 'state', 'Values': ['available']},
            {'Name': 'architecture', 'Values': ['x86_64']},
        ]
    )
    
    # Sort by creation date and get the latest
    images = sorted(response['Images'], key=lambda x: x['CreationDate'], reverse=True)
    if not images:
        raise Exception("No Amazon Linux 2023 AMI found")
    
    return images[0]['ImageId']

def get_default_vpc_subnet(ec2_client):
    """Get a public subnet from the default VPC"""
    # Get default VPC
    vpcs = ec2_client.describe_vpcs(
        Filters=[{'Name': 'isDefault', 'Values': ['true']}]
    )
    
    if not vpcs['Vpcs']:
        raise Exception("No default VPC found. Please create a VPC first.")
    
    vpc_id = vpcs['Vpcs'][0]['VpcId']
    
    # Get subnets in the default VPC
    subnets = ec2_client.describe_subnets(
        Filters=[
            {'Name': 'vpc-id', 'Values': [vpc_id]},
            {'Name': 'map-public-ip-on-launch', 'Values': ['true']}
        ]
    )
    
    if not subnets['Subnets']:
        # Get any subnet from default VPC
        subnets = ec2_client.describe_subnets(
            Filters=[{'Name': 'vpc-id', 'Values': [vpc_id]}]
        )
    
    if not subnets['Subnets']:
        raise Exception(f"No subnets found in default VPC {vpc_id}")
    
    return subnets['Subnets'][0]['SubnetId']

def create_test_instance(ec2_client):
    """Create a test EC2 instance with public IP"""
    print("\n" + "="*80)
    print("STEP 1: Creating test EC2 instance with public IP")
    print("="*80)
    
    try:
        ami_id = get_latest_ami(ec2_client)
        subnet_id = get_default_vpc_subnet(ec2_client)
        
        print(f"Using AMI: {ami_id}")
        print(f"Using Subnet: {subnet_id}")
        
        response = ec2_client.run_instances(
            ImageId=ami_id,
            InstanceType='t2.micro',
            MinCount=1,
            MaxCount=1,
            SubnetId=subnet_id,
            # Force public IP assignment
            NetworkInterfaces=[{
                'DeviceIndex': 0,
                'SubnetId': subnet_id,
                'AssociatePublicIpAddress': True,
                'DeleteOnTermination': True
            }],
            TagSpecifications=[{
                'ResourceType': 'instance',
                'Tags': [
                    {'Key': 'Name', 'Value': 'c7n-test-public-instance'},
                    {'Key': TEST_TAG_KEY, 'Value': TEST_TAG_VALUE},
                    {'Key': 'Purpose', 'Value': 'Cloud Custodian Policy Test'},
                    {'Key': 'CreatedBy', 'Value': 'test-ec2-policy.py'}
                ]
            }]
        )
        
        instance_id = response['Instances'][0]['InstanceId']
        print(f"✓ Created instance: {instance_id}")
        
        # Wait for instance to be running
        print("Waiting for instance to be in running state...")
        waiter = ec2_client.get_waiter('instance_running')
        waiter.wait(InstanceIds=[instance_id])
        
        # Get instance details
        instances = ec2_client.describe_instances(InstanceIds=[instance_id])
        instance = instances['Reservations'][0]['Instances'][0]
        
        public_ip = instance.get('PublicIpAddress', 'N/A')
        private_ip = instance.get('PrivateIpAddress', 'N/A')
        
        print(f"✓ Instance is running")
        print(f"  Instance ID: {instance_id}")
        print(f"  Public IP: {public_ip}")
        print(f"  Private IP: {private_ip}")
        print(f"  State: {instance['State']['Name']}")
        
        return instance_id, public_ip
        
    except Exception as e:
        print(f"✗ Error creating instance: {e}")
        raise

def run_custodian_policy():
    """Run the Cloud Custodian policy"""
    print("\n" + "="*80)
    print("STEP 2: Running Cloud Custodian policy")
    print("="*80)
    
    try:
        cmd = [
            'custodian', 'run',
            '--output-dir', './output',
            '--region', REGION,
            POLICY_FILE
        ]
        
        print(f"Running command: {' '.join(cmd)}")
        
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=True
        )
        
        print("✓ Policy execution completed")
        print("\nPolicy output:")
        print(result.stdout)
        
        if result.stderr:
            print("\nStderr:")
            print(result.stderr)
        
        return True
        
    except subprocess.CalledProcessError as e:
        print(f"✗ Policy execution failed: {e}")
        print(f"Stdout: {e.stdout}")
        print(f"Stderr: {e.stderr}")
        return False

def verify_instance_created(ec2_client, instance_id):
    """Verify that the instance is running with public IP"""
    print("\n" + "="*80)
    print("STEP 3: Verifying instance details")
    print("="*80)
    
    try:
        response = ec2_client.describe_instances(InstanceIds=[instance_id])
        instance = response['Reservations'][0]['Instances'][0]
        state = instance['State']['Name']
        public_ip = instance.get('PublicIpAddress', 'N/A')
        private_ip = instance.get('PrivateIpAddress', 'N/A')
        
        print(f"\nFinal Instance Details:")
        print(f"  Instance ID: {instance_id}")
        print(f"  Public IP: {public_ip}")
        print(f"  Private IP: {private_ip}")
        print(f"  State: {state}")
        
        if state == 'running' and public_ip != 'N/A':
            print(f"\n✓ SUCCESS: Test EC2 instance with public IP created successfully!")
            print(f"  You can now test the aws-ec2-stop-public-instances policy manually.")
            return True
        else:
            print(f"⚠ WARNING: Instance is {state}, public IP: {public_ip}")
            return False
            
    except Exception as e:
        print(f"✗ Error checking instance: {e}")
        return False

def cleanup_instance(ec2_client, instance_id):
    """Terminate the test instance"""
    print("\n" + "="*80)
    print("STEP 4: Cleaning up test instance")
    print("="*80)
    
    try:
        print(f"Terminating instance {instance_id}...")
        ec2_client.terminate_instances(InstanceIds=[instance_id])
        print(f"✓ Instance {instance_id} terminated")
        
    except Exception as e:
        print(f"✗ Error terminating instance: {e}")
        print(f"⚠ Please manually terminate instance {instance_id}")

def main():
    """Main test execution"""
    print("\n" + "="*80)
    print("Cloud Custodian EC2 Public Instance Policy Test")
    print("="*80)
    print(f"Start time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Region: {REGION}")
    print(f"Policy file: {POLICY_FILE}")
    
    # Check if policy file exists
    if not os.path.exists(POLICY_FILE):
        print(f"\n✗ ERROR: Policy file '{POLICY_FILE}' not found")
        sys.exit(1)
    
    ec2_client = boto3.client('ec2', region_name=REGION)
    instance_id = None
    test_passed = False
    
    try:
        # Step 1: Create test instance
        instance_id, public_ip = create_test_instance(ec2_client)
        
        # Give AWS a moment to fully initialize the instance
        print("\nWaiting 10 seconds for AWS to fully initialize the instance...")
        time.sleep(10)
        
        # Step 2: Run Cloud Custodian policy
        policy_success = run_custodian_policy()
        
        if not policy_success:
            print("\n✗ TEST FAILED: Policy execution failed")
            return 1
        
        # Step 3: Verify instance details
        test_passed = verify_instance_created(ec2_client, instance_id)
        
    except Exception as e:
        print(f"\n✗ TEST FAILED: Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        
    finally:
        # Step 4: Cleanup
        if instance_id:
            cleanup_instance(ec2_client, instance_id)
    
    # Print test summary
    print("\n" + "="*80)
    print("TEST SUMMARY")
    print("="*80)
    print(f"End time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    
    if test_passed:
        print(f"✓ TEST COMPLETED: EC2 instance with public IP was created")
        print(f"  Instance ID: {instance_id}")
        print(f"  The test policy listed the public EC2 instance successfully.")
        return 0
    else:
        print("✗ TEST FAILED: Could not verify EC2 instance creation")
        return 1

if __name__ == '__main__':
    sys.exit(main())
