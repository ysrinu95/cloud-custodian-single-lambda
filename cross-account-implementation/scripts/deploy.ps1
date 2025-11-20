#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Deploy Terraform infrastructure for cross-account Cloud Custodian

.DESCRIPTION
    Automated deployment script that:
    - Builds Lambda deployment package
    - Deploys central account infrastructure
    - Optionally deploys member account infrastructure

.PARAMETER Mode
    Deployment mode: 'central', 'member', or 'all' (default: central)

.PARAMETER MemberAccountId
    Member account ID (required for 'member' mode)

.PARAMETER AutoApprove
    Skip Terraform approval prompts

.EXAMPLE
    .\deploy.ps1 -Mode central
    .\deploy.ps1 -Mode member -MemberAccountId "111111111111"
    .\deploy.ps1 -Mode all -AutoApprove
#>

param(
    [ValidateSet('central', 'member', 'all')]
    [string]$Mode = 'central',
    
    [string]$MemberAccountId,
    
    [switch]$AutoApprove
)

$ErrorActionPreference = "Stop"

Write-Host "================================" -ForegroundColor Cyan
Write-Host "Cloud Custodian Deployment" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# Get script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

# Validate mode
if ($Mode -eq 'member' -and -not $MemberAccountId) {
    Write-Host "✗ MemberAccountId is required for 'member' mode" -ForegroundColor Red
    exit 1
}

# Build Lambda package
if ($Mode -in @('central', 'all')) {
    Write-Host "[STEP 1] Building Lambda deployment package..." -ForegroundColor Yellow
    Write-Host ""
    
    $buildScript = Join-Path $ScriptDir "build-lambda-package.ps1"
    & $buildScript
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "✗ Lambda package build failed" -ForegroundColor Red
        exit 1
    }
    
    Write-Host ""
}

# Deploy central account
if ($Mode -in @('central', 'all')) {
    Write-Host "[STEP 2] Deploying central account infrastructure..." -ForegroundColor Yellow
    Write-Host ""
    
    $centralDir = Join-Path $ProjectRoot "terraform" "central-account"
    
    if (-not (Test-Path $centralDir)) {
        Write-Host "✗ Central account directory not found: $centralDir" -ForegroundColor Red
        exit 1
    }
    
    Push-Location $centralDir
    try {
        # Check for tfvars file
        $tfvarsFile = "terraform.tfvars"
        if (-not (Test-Path $tfvarsFile)) {
            Write-Host "⚠ Warning: $tfvarsFile not found" -ForegroundColor Yellow
            Write-Host "  Please copy terraform.tfvars.example to terraform.tfvars and configure it" -ForegroundColor Yellow
            
            $createTfvars = Read-Host "Create terraform.tfvars from example? (y/n)"
            if ($createTfvars -eq 'y') {
                Copy-Item "terraform.tfvars.example" $tfvarsFile
                Write-Host "✓ Created $tfvarsFile" -ForegroundColor Green
                Write-Host "  Please edit the file with your configuration and run this script again" -ForegroundColor Yellow
                exit 0
            } else {
                Write-Host "✗ Deployment cancelled" -ForegroundColor Red
                exit 1
            }
        }
        
        # Terraform init
        Write-Host "Running: terraform init" -ForegroundColor Gray
        & terraform init
        if ($LASTEXITCODE -ne 0) {
            Write-Host "✗ terraform init failed" -ForegroundColor Red
            exit 1
        }
        
        # Terraform plan
        Write-Host ""
        Write-Host "Running: terraform plan" -ForegroundColor Gray
        & terraform plan
        if ($LASTEXITCODE -ne 0) {
            Write-Host "✗ terraform plan failed" -ForegroundColor Red
            exit 1
        }
        
        # Terraform apply
        Write-Host ""
        if ($AutoApprove) {
            Write-Host "Running: terraform apply -auto-approve" -ForegroundColor Gray
            & terraform apply -auto-approve
        } else {
            Write-Host "Running: terraform apply" -ForegroundColor Gray
            & terraform apply
        }
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "✗ terraform apply failed" -ForegroundColor Red
            exit 1
        }
        
        Write-Host ""
        Write-Host "✓ Central account deployment completed" -ForegroundColor Green
        Write-Host ""
        
        # Get outputs
        Write-Host "Central Account Outputs:" -ForegroundColor Yellow
        & terraform output
        Write-Host ""
        
    } finally {
        Pop-Location
    }
}

# Deploy member account
if ($Mode -in @('member', 'all')) {
    Write-Host "[STEP 3] Deploying member account infrastructure..." -ForegroundColor Yellow
    Write-Host ""
    
    if ($Mode -eq 'all') {
        Write-Host "⚠ Manual member account deployment required" -ForegroundColor Yellow
        Write-Host "  Run this script with -Mode member -MemberAccountId <ACCOUNT_ID> for each member account" -ForegroundColor Yellow
        Write-Host ""
    } else {
        $memberDir = Join-Path $ProjectRoot "terraform" "member-account"
        
        if (-not (Test-Path $memberDir)) {
            Write-Host "✗ Member account directory not found: $memberDir" -ForegroundColor Red
            exit 1
        }
        
        Push-Location $memberDir
        try {
            # Check for tfvars file
            $tfvarsFile = "terraform.tfvars"
            if (-not (Test-Path $tfvarsFile)) {
                Write-Host "⚠ Warning: $tfvarsFile not found" -ForegroundColor Yellow
                Write-Host "  Please copy terraform.tfvars.example to terraform.tfvars and configure it" -ForegroundColor Yellow
                
                $createTfvars = Read-Host "Create terraform.tfvars from example? (y/n)"
                if ($createTfvars -eq 'y') {
                    Copy-Item "terraform.tfvars.example" $tfvarsFile
                    Write-Host "✓ Created $tfvarsFile" -ForegroundColor Green
                    Write-Host "  Please edit the file with your configuration and run this script again" -ForegroundColor Yellow
                    exit 0
                } else {
                    Write-Host "✗ Deployment cancelled" -ForegroundColor Red
                    exit 1
                }
            }
            
            # Terraform init
            Write-Host "Running: terraform init" -ForegroundColor Gray
            & terraform init
            if ($LASTEXITCODE -ne 0) {
                Write-Host "✗ terraform init failed" -ForegroundColor Red
                exit 1
            }
            
            # Terraform plan
            Write-Host ""
            Write-Host "Running: terraform plan" -ForegroundColor Gray
            & terraform plan
            if ($LASTEXITCODE -ne 0) {
                Write-Host "✗ terraform plan failed" -ForegroundColor Red
                exit 1
            }
            
            # Terraform apply
            Write-Host ""
            if ($AutoApprove) {
                Write-Host "Running: terraform apply -auto-approve" -ForegroundColor Gray
                & terraform apply -auto-approve
            } else {
                Write-Host "Running: terraform apply" -ForegroundColor Gray
                & terraform apply
            }
            
            if ($LASTEXITCODE -ne 0) {
                Write-Host "✗ terraform apply failed" -ForegroundColor Red
                exit 1
            }
            
            Write-Host ""
            Write-Host "✓ Member account deployment completed" -ForegroundColor Green
            Write-Host ""
            
            # Get outputs
            Write-Host "Member Account Outputs:" -ForegroundColor Yellow
            & terraform output
            Write-Host ""
            
        } finally {
            Pop-Location
        }
    }
}

Write-Host "================================" -ForegroundColor Cyan
Write-Host "Deployment Complete!" -ForegroundColor Green
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Next Steps:" -ForegroundColor Yellow
if ($Mode -eq 'central') {
    Write-Host "  1. Upload Cloud Custodian policies to S3" -ForegroundColor Gray
    Write-Host "  2. Deploy member account infrastructure in each member account" -ForegroundColor Gray
    Write-Host "  3. Test cross-account access using test-cross-account-access.ps1" -ForegroundColor Gray
} elseif ($Mode -eq 'member') {
    Write-Host "  1. Test cross-account access using test-cross-account-access.ps1" -ForegroundColor Gray
    Write-Host "  2. Send test events to verify end-to-end functionality" -ForegroundColor Gray
} else {
    Write-Host "  1. Upload Cloud Custodian policies to S3" -ForegroundColor Gray
    Write-Host "  2. Deploy member account infrastructure in each member account" -ForegroundColor Gray
    Write-Host "  3. Test cross-account access" -ForegroundColor Gray
}
Write-Host ""
