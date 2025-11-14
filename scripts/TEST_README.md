# EC2 Public Instance Policy Test

This directory contains test scripts to verify that the Cloud Custodian policy correctly stops EC2 instances with public IP addresses.

## Test Overview

The test performs the following steps:

1. **Create Test Instance**: Launches an EC2 instance (t2.micro) with a public IP address in the default VPC
2. **Run Policy**: Executes the Cloud Custodian policy (`test-policies.yml`) 
3. **Verify State**: Checks that the instance is stopped or stopping
4. **Cleanup**: Terminates the test instance

## Prerequisites

- AWS CLI configured with appropriate credentials
- Cloud Custodian installed (`pip install c7n`)
- Permissions to:
  - Create and terminate EC2 instances
  - Describe EC2 resources (instances, AMIs, VPCs, subnets)
- A default VPC in the target region (us-east-1)

## Test Files

- **test-policies.yml**: Cloud Custodian policy file for testing
- **test_ec2_policy.ps1**: PowerShell test script (for Windows)
- **test_ec2_policy.py**: Python test script (cross-platform)

## Running the Test

### Option 1: PowerShell (Windows)

```powershell
cd "C:\United Techno\Git Repos\cloud-custodian-single-lambda"
.\scripts\test_ec2_policy.ps1
```

### Option 2: Python (Cross-platform)

```bash
cd /path/to/cloud-custodian-single-lambda
python scripts/test_ec2_policy.py
```

## Expected Output

### Successful Test

```
================================================================================================
Cloud Custodian EC2 Public Instance Policy Test
================================================================================================

Step 1: Creating test EC2 instance with public IP...
  Finding latest Amazon Linux 2023 AMI...
  Using AMI: ami-xxxxxxxxxxxxx
  Using Subnet: subnet-xxxxxxxxxxxxx
  Launching EC2 instance...
  Instance created: i-xxxxxxxxxxxxx
  Waiting for instance to be running...

  Instance Details:
    Instance ID: i-xxxxxxxxxxxxx
    Public IP: xx.xx.xx.xx
    Private IP: xx.xx.xx.xx
    State: running

Step 2: Running Cloud Custodian policy...
  Policy execution completed

Step 3: Verifying instance state...
  Attempt 1/12 : Instance state is 'stopping'
  SUCCESS: Instance is stopping

Step 4: Cleaning up test instance...
  Instance i-xxxxxxxxxxxxx terminated

================================================================================================
TEST SUMMARY
================================================================================================

TEST PASSED: EC2 instance with public IP was successfully stopped
The policy correctly identified and stopped the public EC2 instance.
```

## What the Test Validates

1. ✅ Policy correctly identifies EC2 instances with public IP addresses
2. ✅ Policy stops running instances with public IPs
3. ✅ Policy actions (stop + notify) execute successfully
4. ✅ Instance state changes from 'running' to 'stopped' or 'stopping'

## Policy Being Tested

**Policy Name**: `aws-ec2-stop-public-instances`

**Resource**: `aws.ec2`

**Filters**:
- State is `running`
- `PublicIpAddress` is present

**Actions**:
- Stop the instance (with force)
- Send notification email via SQS

## Troubleshooting

### Test Fails - Instance Not Stopped

If the test fails because the instance wasn't stopped:

1. Check Cloud Custodian policy syntax: `custodian validate test-policies.yml`
2. Verify AWS credentials have EC2 stop permissions
3. Check the policy output in the `./output` directory
4. Review CloudWatch Logs if running via Lambda

### Test Fails - Instance Creation

If instance creation fails:

1. Verify default VPC exists in us-east-1
2. Check EC2 service limits (t2.micro instances)
3. Ensure AWS credentials have EC2 RunInstances permission
4. Verify AMI availability in the region

### Manual Cleanup

If the test crashes and doesn't cleanup:

```bash
# Find test instances
aws ec2 describe-instances \
  --filters "Name=tag:c7n-test,Values=ec2-public-instance-test" \
  --query "Reservations[*].Instances[*].InstanceId" \
  --output text

# Terminate them
aws ec2 terminate-instances --instance-ids <instance-id>
```

## Cost Considerations

- Each test run creates a t2.micro instance (Free Tier eligible)
- Instance runs for approximately 1-2 minutes
- Cost is negligible (< $0.01 per test)
- Instance is automatically terminated after the test

## Integration with CI/CD

The test scripts can be integrated into CI/CD pipelines:

### GitHub Actions Example

```yaml
- name: Test EC2 Policy
  run: |
    pip install c7n boto3
    python scripts/test_ec2_policy.py
  env:
    AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
    AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
    AWS_DEFAULT_REGION: us-east-1
```

## Additional Notes

- Test uses tag `c7n-test=ec2-public-instance-test` for easy identification
- Instance name is `c7n-test-public-instance`
- Policy execution output is saved to `./output` directory
- Test takes approximately 1-2 minutes to complete
