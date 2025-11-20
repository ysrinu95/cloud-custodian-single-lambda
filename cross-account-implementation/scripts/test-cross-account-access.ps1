#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Test cross-account role assumption and permissions

.DESCRIPTION
    Tests the cross-account setup by:
    - Verifying IAM role trust policies
    - Attempting to assume role in member accounts
    - Testing basic AWS API permissions

.PARAMETER CentralAccountId
    Central security account ID

.PARAMETER MemberAccountIds
    Comma-separated list of member account IDs

.PARAMETER RoleName
    IAM role name in member accounts (default: CloudCustodianExecutionRole)

.PARAMETER Region
    AWS region (default: us-east-1)

.EXAMPLE
    .\test-cross-account-access.ps1 -CentralAccountId "999999999999" -MemberAccountIds "111111111111,222222222222"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$CentralAccountId,
    
    [Parameter(Mandatory=$true)]
    [string]$MemberAccountIds,
    
    [string]$RoleName = "CloudCustodianExecutionRole",
    [string]$Region = "us-east-1"
)

$ErrorActionPreference = "Stop"

Write-Host "================================" -ForegroundColor Cyan
Write-Host "Cross-Account Access Tester" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# Check AWS CLI
try {
    $awsVersion = & aws --version 2>&1
    Write-Host "AWS CLI: $awsVersion" -ForegroundColor Green
} catch {
    Write-Host "✗ AWS CLI not found. Please install AWS CLI." -ForegroundColor Red
    exit 1
}

Write-Host ""

# Get current identity
Write-Host "Current AWS Identity:" -ForegroundColor Yellow
try {
    $identity = & aws sts get-caller-identity --output json | ConvertFrom-Json
    Write-Host "  Account: $($identity.Account)" -ForegroundColor Gray
    Write-Host "  User/Role: $($identity.Arn)" -ForegroundColor Gray
    Write-Host ""
} catch {
    Write-Host "✗ Failed to get AWS identity. Check your credentials." -ForegroundColor Red
    exit 1
}

# Parse member account IDs
$memberAccounts = $MemberAccountIds -split ',' | ForEach-Object { $_.Trim() }

Write-Host "Testing access to $($memberAccounts.Count) member account(s)" -ForegroundColor Yellow
Write-Host ""

$results = @()

foreach ($accountId in $memberAccounts) {
    Write-Host "─────────────────────────────────" -ForegroundColor Gray
    Write-Host "Testing Account: $accountId" -ForegroundColor Cyan
    Write-Host "─────────────────────────────────" -ForegroundColor Gray
    
    $roleArn = "arn:aws:iam::${accountId}:role/$RoleName"
    $externalId = "cloud-custodian-$accountId"
    $sessionName = "test-session-$accountId"
    
    $result = @{
        AccountId = $accountId
        RoleArn = $roleArn
        AssumeRoleSuccess = $false
        Permissions = @{}
    }
    
    # Test AssumeRole
    Write-Host "[1/4] Testing AssumeRole..." -ForegroundColor Yellow
    try {
        $assumeRoleOutput = & aws sts assume-role `
            --role-arn $roleArn `
            --role-session-name $sessionName `
            --external-id $externalId `
            --duration-seconds 900 `
            --region $Region `
            --output json 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            $credentials = ($assumeRoleOutput | ConvertFrom-Json).Credentials
            Write-Host "  ✓ Successfully assumed role" -ForegroundColor Green
            Write-Host "    Session expires: $($credentials.Expiration)" -ForegroundColor Gray
            $result.AssumeRoleSuccess = $true
            
            # Set temporary credentials
            $env:AWS_ACCESS_KEY_ID = $credentials.AccessKeyId
            $env:AWS_SECRET_ACCESS_KEY = $credentials.SecretAccessKey
            $env:AWS_SESSION_TOKEN = $credentials.SessionToken
            
            # Test STS GetCallerIdentity
            Write-Host "[2/4] Testing STS GetCallerIdentity..." -ForegroundColor Yellow
            try {
                $callerIdentity = & aws sts get-caller-identity --region $Region --output json | ConvertFrom-Json
                Write-Host "  ✓ STS access confirmed" -ForegroundColor Green
                Write-Host "    Assumed ARN: $($callerIdentity.Arn)" -ForegroundColor Gray
                $result.Permissions.STS = $true
            } catch {
                Write-Host "  ✗ STS GetCallerIdentity failed" -ForegroundColor Red
                $result.Permissions.STS = $false
            }
            
            # Test EC2 DescribeInstances
            Write-Host "[3/4] Testing EC2 DescribeInstances..." -ForegroundColor Yellow
            try {
                $ec2Output = & aws ec2 describe-instances --region $Region --max-results 5 --output json 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $ec2Data = $ec2Output | ConvertFrom-Json
                    $instanceCount = ($ec2Data.Reservations | ForEach-Object { $_.Instances }).Count
                    Write-Host "  ✓ EC2 access confirmed ($instanceCount instances found)" -ForegroundColor Green
                    $result.Permissions.EC2 = $true
                } else {
                    Write-Host "  ✗ EC2 DescribeInstances failed" -ForegroundColor Red
                    $result.Permissions.EC2 = $false
                }
            } catch {
                Write-Host "  ✗ EC2 access test failed: $_" -ForegroundColor Red
                $result.Permissions.EC2 = $false
            }
            
            # Test S3 ListBuckets
            Write-Host "[4/4] Testing S3 ListBuckets..." -ForegroundColor Yellow
            try {
                $s3Output = & aws s3api list-buckets --output json 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $s3Data = $s3Output | ConvertFrom-Json
                    $bucketCount = $s3Data.Buckets.Count
                    Write-Host "  ✓ S3 access confirmed ($bucketCount buckets found)" -ForegroundColor Green
                    $result.Permissions.S3 = $true
                } else {
                    Write-Host "  ✗ S3 ListBuckets failed" -ForegroundColor Red
                    $result.Permissions.S3 = $false
                }
            } catch {
                Write-Host "  ✗ S3 access test failed: $_" -ForegroundColor Red
                $result.Permissions.S3 = $false
            }
            
        } else {
            Write-Host "  ✗ Failed to assume role" -ForegroundColor Red
            Write-Host "    Error: $assumeRoleOutput" -ForegroundColor Red
            $result.AssumeRoleSuccess = $false
        }
    } catch {
        Write-Host "  ✗ AssumeRole failed: $_" -ForegroundColor Red
        $result.AssumeRoleSuccess = $false
    } finally {
        # Clear temporary credentials
        Remove-Item Env:\AWS_ACCESS_KEY_ID -ErrorAction SilentlyContinue
        Remove-Item Env:\AWS_SECRET_ACCESS_KEY -ErrorAction SilentlyContinue
        Remove-Item Env:\AWS_SESSION_TOKEN -ErrorAction SilentlyContinue
    }
    
    $results += $result
    Write-Host ""
}

# Summary
Write-Host "================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

$successCount = ($results | Where-Object { $_.AssumeRoleSuccess }).Count
$totalCount = $results.Count

Write-Host "Accounts tested: $totalCount" -ForegroundColor White
Write-Host "Successful: $successCount" -ForegroundColor Green
Write-Host "Failed: $($totalCount - $successCount)" -ForegroundColor Red
Write-Host ""

foreach ($result in $results) {
    $status = if ($result.AssumeRoleSuccess) { "✓" } else { "✗" }
    $color = if ($result.AssumeRoleSuccess) { "Green" } else { "Red" }
    
    Write-Host "$status Account $($result.AccountId)" -ForegroundColor $color
    
    if ($result.AssumeRoleSuccess) {
        foreach ($service in $result.Permissions.Keys) {
            $permStatus = if ($result.Permissions[$service]) { "✓" } else { "✗" }
            $permColor = if ($result.Permissions[$service]) { "Green" } else { "Red" }
            Write-Host "    $permStatus $service" -ForegroundColor $permColor
        }
    }
}

Write-Host ""

if ($successCount -eq $totalCount) {
    Write-Host "All tests passed! ✓" -ForegroundColor Green
    exit 0
} else {
    Write-Host "Some tests failed. Check the configuration." -ForegroundColor Yellow
    exit 1
}
