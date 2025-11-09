# Build script for Cloud Custodian Lambda Layer (Windows PowerShell)
# This script creates a Lambda layer with Cloud Custodian and its dependencies

$ErrorActionPreference = "Stop"

# Configuration
$PYTHON_VERSION = "3.11"
$LAYER_NAME = "cloud-custodian-layer"
$LAYER_DIR = "layers"
$BUILD_DIR = "$LAYER_DIR\python\lib\python$PYTHON_VERSION\site-packages"

Write-Host "======================================"
Write-Host "Building Cloud Custodian Lambda Layer"
Write-Host "======================================"

# Clean up previous builds
Write-Host "Cleaning up previous builds..."
if (Test-Path $LAYER_DIR) {
    Remove-Item -Recurse -Force $LAYER_DIR
}
if (Test-Path "$LAYER_NAME.zip") {
    Remove-Item -Force "$LAYER_NAME.zip"
}

# Create layer directory structure
Write-Host "Creating layer directory structure..."
New-Item -ItemType Directory -Force -Path $BUILD_DIR | Out-Null

# Install dependencies
Write-Host "Installing Cloud Custodian and dependencies..."
python -m pip install --upgrade pip
python -m pip install -r requirements.txt -t $BUILD_DIR

# Remove unnecessary files to reduce size
Write-Host "Removing unnecessary files..."
Push-Location $BUILD_DIR

# Remove test files
Get-ChildItem -Recurse -Directory -Filter "tests" -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
Get-ChildItem -Recurse -Directory -Filter "test" -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
Get-ChildItem -Recurse -Directory -Filter "__pycache__" -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force

# Remove Python cache files
Get-ChildItem -Recurse -Filter "*.pyc" -ErrorAction SilentlyContinue | Remove-Item -Force
Get-ChildItem -Recurse -Filter "*.pyo" -ErrorAction SilentlyContinue | Remove-Item -Force

# Remove distribution info
Get-ChildItem -Recurse -Filter "*.dist-info" -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
Get-ChildItem -Recurse -Filter "*.egg-info" -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force

# Remove boto3 and botocore (already in Lambda runtime)
Get-ChildItem -Filter "boto3*" -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
Get-ChildItem -Filter "botocore*" -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force

# Remove documentation and examples
Get-ChildItem -Recurse -Filter "*.md" -ErrorAction SilentlyContinue | Remove-Item -Force
Get-ChildItem -Recurse -Directory -Filter "docs" -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
Get-ChildItem -Recurse -Directory -Filter "examples" -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force

Pop-Location

# Create zip file
Write-Host "Creating layer zip file..."
Push-Location $LAYER_DIR
Compress-Archive -Path "python" -DestinationPath "..\$LAYER_NAME.zip" -Force
Pop-Location

Move-Item -Force "$LAYER_NAME.zip" "$LAYER_DIR\$LAYER_NAME.zip"

# Check size
$SIZE_BYTES = (Get-Item "$LAYER_DIR\$LAYER_NAME.zip").Length
$SIZE_MB = [math]::Round($SIZE_BYTES / 1MB, 2)

Write-Host ""
Write-Host "======================================"
Write-Host "Build completed successfully!"
Write-Host "======================================"
Write-Host "Layer file: $LAYER_DIR\$LAYER_NAME.zip"
Write-Host "Size: $SIZE_MB MB"
Write-Host ""

if ($SIZE_MB -gt 250) {
    Write-Host "⚠️  WARNING: Layer size exceeds 250MB!" -ForegroundColor Yellow
    Write-Host "    Lambda has a 250MB limit for unzipped layers."
    Write-Host "    Consider further optimization or use a container image."
} else {
    Write-Host "✓ Layer size is within Lambda limits" -ForegroundColor Green
}

Write-Host ""
Write-Host "Next steps:"
Write-Host "1. Test the layer locally (see scripts\test_layer.ps1)"
Write-Host "2. Deploy with Terraform: cd terraform; terraform apply"
Write-Host "3. Or upload manually to AWS Lambda"
