#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Build Lambda deployment package for cross-account Cloud Custodian executor

.DESCRIPTION
    Creates a deployment package (lambda-function.zip) containing:
    - Python Lambda handler code
    - Cloud Custodian library
    - All required dependencies

.PARAMETER OutputPath
    Path where lambda-function.zip will be created (default: terraform/central-account)

.PARAMETER PythonVersion
    Python version to use (default: python3.11)

.EXAMPLE
    .\build-lambda-package.ps1
    .\build-lambda-package.ps1 -OutputPath "dist" -PythonVersion "python3.11"
#>

param(
    [string]$OutputPath = "terraform/central-account",
    [string]$PythonVersion = "python3.11"
)

$ErrorActionPreference = "Stop"

Write-Host "================================" -ForegroundColor Cyan
Write-Host "Lambda Package Builder" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# Get script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

# Paths
$SourceDir = Join-Path $ProjectRoot "src"
$BuildDir = Join-Path $ProjectRoot "build"
$OutputFile = Join-Path $ProjectRoot $OutputPath "lambda-function.zip"

Write-Host "[1/6] Validating environment..." -ForegroundColor Yellow

# Check Python installation
try {
    $pythonCmd = Get-Command python -ErrorAction Stop
    $pythonVersionOutput = & python --version 2>&1
    Write-Host "  ✓ Python found: $pythonVersionOutput" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Python not found. Please install Python 3.11 or higher." -ForegroundColor Red
    exit 1
}

# Check pip
try {
    & python -m pip --version | Out-Null
    Write-Host "  ✓ pip found" -ForegroundColor Green
} catch {
    Write-Host "  ✗ pip not found. Please install pip." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[2/6] Cleaning build directory..." -ForegroundColor Yellow

# Clean and create build directory
if (Test-Path $BuildDir) {
    Remove-Item -Path $BuildDir -Recurse -Force
    Write-Host "  ✓ Removed existing build directory" -ForegroundColor Green
}

New-Item -Path $BuildDir -ItemType Directory | Out-Null
Write-Host "  ✓ Created build directory: $BuildDir" -ForegroundColor Green

Write-Host ""
Write-Host "[3/6] Installing Cloud Custodian and dependencies..." -ForegroundColor Yellow

# Install dependencies to build directory
$pipInstallArgs = @(
    "-m", "pip", "install",
    "--target", $BuildDir,
    "--upgrade",
    "c7n",           # Cloud Custodian core
    "boto3",         # AWS SDK
    "pyyaml",        # YAML parsing
    "jsonschema"     # Schema validation
)

Write-Host "  Installing packages to: $BuildDir" -ForegroundColor Gray
& python $pipInstallArgs

if ($LASTEXITCODE -ne 0) {
    Write-Host "  ✗ pip install failed" -ForegroundColor Red
    exit 1
}

Write-Host "  ✓ Dependencies installed" -ForegroundColor Green

Write-Host ""
Write-Host "[4/6] Copying Lambda source code..." -ForegroundColor Yellow

# Copy Lambda handler and supporting files
$sourceFiles = @(
    "lambda_handler.py",
    "cross_account_executor.py",
    "validator.py"
)

foreach ($file in $sourceFiles) {
    $sourcePath = Join-Path $SourceDir $file
    $destPath = Join-Path $BuildDir $file
    
    if (Test-Path $sourcePath) {
        Copy-Item -Path $sourcePath -Destination $destPath
        Write-Host "  ✓ Copied $file" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Source file not found: $file" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "[5/6] Creating deployment package..." -ForegroundColor Yellow

# Create output directory if it doesn't exist
$OutputDir = Split-Path -Parent $OutputFile
if (-not (Test-Path $OutputDir)) {
    New-Item -Path $OutputDir -ItemType Directory | Out-Null
}

# Remove existing zip if present
if (Test-Path $OutputFile) {
    Remove-Item -Path $OutputFile -Force
    Write-Host "  ✓ Removed existing lambda-function.zip" -ForegroundColor Green
}

# Create zip file
Push-Location $BuildDir
try {
    if (Get-Command Compress-Archive -ErrorAction SilentlyContinue) {
        # Use PowerShell's built-in Compress-Archive
        Get-ChildItem -Path . -Recurse | Compress-Archive -DestinationPath $OutputFile -CompressionLevel Optimal
        Write-Host "  ✓ Created ZIP using Compress-Archive" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Compress-Archive not available" -ForegroundColor Red
        exit 1
    }
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "[6/6] Verifying deployment package..." -ForegroundColor Yellow

if (Test-Path $OutputFile) {
    $zipSize = (Get-Item $OutputFile).Length
    $zipSizeMB = [math]::Round($zipSize / 1MB, 2)
    
    Write-Host "  ✓ Package created: $OutputFile" -ForegroundColor Green
    Write-Host "  ✓ Package size: $zipSizeMB MB" -ForegroundColor Green
    
    if ($zipSizeMB -gt 50) {
        Write-Host "  ⚠ Warning: Package size exceeds 50MB. Consider optimizing dependencies." -ForegroundColor Yellow
    }
    
    if ($zipSizeMB -gt 250) {
        Write-Host "  ✗ Error: Package size exceeds Lambda limit of 250MB" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "  ✗ Failed to create deployment package" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "================================" -ForegroundColor Cyan
Write-Host "Build completed successfully!" -ForegroundColor Green
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Deployment package: $OutputFile" -ForegroundColor White
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. cd terraform/central-account" -ForegroundColor Gray
Write-Host "  2. terraform init" -ForegroundColor Gray
Write-Host "  3. terraform plan" -ForegroundColor Gray
Write-Host "  4. terraform apply" -ForegroundColor Gray
Write-Host ""
