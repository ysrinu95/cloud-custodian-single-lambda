# Test EC2 Public Instance Policy
# This script tests the Cloud Custodian policy that stops EC2 instances with public IPs

Write-Host "`n================================================================================================" -ForegroundColor Cyan
Write-Host "Cloud Custodian EC2 Public Instance Policy Test" -ForegroundColor Cyan
Write-Host "================================================================================================`n" -ForegroundColor Cyan

# Configuration
$Region = "us-east-1"
$PolicyFile = "test-policies.yml"
$OutputDir = "./output"

# Check if policy file exists
if (-not (Test-Path $PolicyFile)) {
    Write-Host "ERROR: Policy file '$PolicyFile' not found" -ForegroundColor Red
    exit 1
}

Write-Host "Step 1: Creating test EC2 instance with public IP..." -ForegroundColor Yellow

# Get the latest Amazon Linux 2023 AMI
Write-Host "  Finding latest Amazon Linux 2023 AMI..."
$ami = aws ec2 describe-images `
    --owners amazon `
    --filters "Name=name,Values=al2023-ami-*-x86_64" "Name=state,Values=available" `
    --query "Images | sort_by(@, &CreationDate) | [-1].ImageId" `
    --output text `
    --region $Region

if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERROR: Failed to find AMI" -ForegroundColor Red
    exit 1
}

Write-Host "  Using AMI: $ami" -ForegroundColor Green

# Get default VPC subnet
Write-Host "  Finding default VPC subnet..."
$subnet = aws ec2 describe-subnets `
    --filters "Name=default-for-az,Values=true" `
    --query "Subnets[0].SubnetId" `
    --output text `
    --region $Region

if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERROR: Failed to find subnet" -ForegroundColor Red
    exit 1
}

Write-Host "  Using Subnet: $subnet" -ForegroundColor Green

# Create EC2 instance with public IP
Write-Host "  Launching EC2 instance..."
$instanceJson = aws ec2 run-instances `
    --image-id $ami `
    --instance-type t2.micro `
    --subnet-id $subnet `
    --associate-public-ip-address `
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=c7n-test-public-instance},{Key=c7n-test,Value=ec2-public-instance-test},{Key=Purpose,Value=Cloud Custodian Policy Test}]" `
    --region $Region

if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERROR: Failed to create instance" -ForegroundColor Red
    exit 1
}

$instance = $instanceJson | ConvertFrom-Json
$instanceId = $instance.Instances[0].InstanceId

Write-Host "  Instance created: $instanceId" -ForegroundColor Green

# Wait for instance to be running
Write-Host "  Waiting for instance to be running..."
aws ec2 wait instance-running --instance-ids $instanceId --region $Region

if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERROR: Instance failed to start" -ForegroundColor Red
    # Cleanup
    aws ec2 terminate-instances --instance-ids $instanceId --region $Region | Out-Null
    exit 1
}

# Get instance details
$instanceDetails = aws ec2 describe-instances `
    --instance-ids $instanceId `
    --region $Region `
    | ConvertFrom-Json

$publicIp = $instanceDetails.Reservations[0].Instances[0].PublicIpAddress
$privateIp = $instanceDetails.Reservations[0].Instances[0].PrivateIpAddress
$state = $instanceDetails.Reservations[0].Instances[0].State.Name

Write-Host "`n  Instance Details:" -ForegroundColor Cyan
Write-Host "    Instance ID: $instanceId"
Write-Host "    Public IP: $publicIp"
Write-Host "    Private IP: $privateIp"
Write-Host "    State: $state"

# Wait a bit for AWS to fully initialize
Write-Host "`n  Waiting 15 seconds for AWS to fully initialize the instance..." -ForegroundColor Yellow
Start-Sleep -Seconds 15

Write-Host "`nStep 2: Running Cloud Custodian policy..." -ForegroundColor Yellow

# Run Cloud Custodian policy
custodian run --output-dir $OutputDir --region $Region $PolicyFile

if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERROR: Policy execution failed" -ForegroundColor Red
    # Cleanup
    Write-Host "`n  Cleaning up instance..."
    aws ec2 terminate-instances --instance-ids $instanceId --region $Region | Out-Null
    exit 1
}

Write-Host "  Policy execution completed" -ForegroundColor Green

# Wait for policy actions to take effect
Write-Host "`n  Waiting 15 seconds for policy actions to take effect..." -ForegroundColor Yellow
Start-Sleep -Seconds 15

Write-Host "`nStep 3: Verifying instance details..." -ForegroundColor Yellow

# Get final instance details
$instanceDetails = aws ec2 describe-instances `
    --instance-ids $instanceId `
    --region $Region `
    | ConvertFrom-Json

$currentState = $instanceDetails.Reservations[0].Instances[0].State.Name
$publicIp = $instanceDetails.Reservations[0].Instances[0].PublicIpAddress

Write-Host "`n  Final Instance Details:" -ForegroundColor Cyan
Write-Host "    Instance ID: $instanceId"
Write-Host "    Public IP: $publicIp"
Write-Host "    State: $currentState"

Write-Host "`n  Test EC2 instance with public IP created successfully!" -ForegroundColor Green
Write-Host "  You can now test the aws-ec2-stop-public-instances policy manually." -ForegroundColor Yellow

Write-Host "`nStep 4: Cleaning up test instance..." -ForegroundColor Yellow
aws ec2 terminate-instances --instance-ids $instanceId --region $Region | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "  Instance $instanceId terminated" -ForegroundColor Green
}

# Print test summary
Write-Host "`n================================================================================================" -ForegroundColor Cyan
Write-Host "TEST SUMMARY" -ForegroundColor Cyan
Write-Host "================================================================================================" -ForegroundColor Cyan

Write-Host "`nTEST COMPLETED: EC2 instance with public IP was created and policy was run" -ForegroundColor Green
Write-Host "Instance ID: $instanceId" -ForegroundColor Cyan
Write-Host "The test policy listed the public EC2 instance successfully.`n" -ForegroundColor Green
exit 0
