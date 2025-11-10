# Testing Script for Event-Driven Cloud Custodian

# Configuration
$BUCKET_NAME = "ysr95-custodian-policies"  # Change this to your desired bucket name
$REGION = "us-east-1"
$PROJECT_NAME = "cloud-custodian"
$ENVIRONMENT = "dev"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Cloud Custodian Testing Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Create S3 bucket for policies
Write-Host "Step 1: Creating S3 bucket for policies..." -ForegroundColor Yellow
try {
    aws s3 mb s3://$BUCKET_NAME --region $REGION 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ Bucket created: $BUCKET_NAME" -ForegroundColor Green
    } else {
        Write-Host "  ! Bucket already exists or error occurred" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  ! Could not create bucket" -ForegroundColor Yellow
}

# Enable versioning
Write-Host "  Enabling versioning..." -ForegroundColor White
aws s3api put-bucket-versioning --bucket $BUCKET_NAME --versioning-configuration Status=Enabled
Write-Host "  ✓ Versioning enabled" -ForegroundColor Green
Write-Host ""

# Step 2: Update policy mapping configuration
Write-Host "Step 2: Updating policy mapping configuration..." -ForegroundColor Yellow
$mappingFile = "config\policy-mapping.json"
if (Test-Path $mappingFile) {
    $content = Get-Content $mappingFile -Raw | ConvertFrom-Json
    $content.s3_policy_bucket = $BUCKET_NAME
    $content | ConvertTo-Json -Depth 10 | Set-Content $mappingFile
    Write-Host "  ✓ Updated policy-mapping.json with bucket: $BUCKET_NAME" -ForegroundColor Green
} else {
    Write-Host "  ✗ policy-mapping.json not found!" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Step 3: Upload files to S3
Write-Host "Step 3: Uploading files to S3..." -ForegroundColor Yellow

Write-Host "  Uploading policy-mapping.json..." -ForegroundColor White
aws s3 cp config\policy-mapping.json s3://$BUCKET_NAME/config/policy-mapping.json
if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✓ Uploaded policy-mapping.json" -ForegroundColor Green
}

Write-Host "  Uploading s3-bucket-security.yml..." -ForegroundColor White
aws s3 cp policies\s3-bucket-security.yml s3://$BUCKET_NAME/custodian-policies/s3-bucket-security.yml
if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✓ Uploaded s3-bucket-security.yml" -ForegroundColor Green
}

Write-Host ""
Write-Host "  Verifying uploads..." -ForegroundColor White
aws s3 ls s3://$BUCKET_NAME/config/
aws s3 ls s3://$BUCKET_NAME/custodian-policies/
Write-Host ""

# Step 4: Update terraform.tfvars
Write-Host "Step 4: Creating/updating terraform.tfvars..." -ForegroundColor Yellow
$tfvarsContent = @"
aws_region             = "$REGION"
environment            = "$ENVIRONMENT"
project_name           = "$PROJECT_NAME"
lambda_execution_mode  = "native"

# S3 bucket for policy storage
policy_bucket          = "$BUCKET_NAME"
policy_mapping_key     = "config/policy-mapping.json"

# Lambda configuration
lambda_timeout         = 300
lambda_memory_size     = 512
log_retention_days     = 7

enable_eventbridge_rule = true

tags = {
  Project     = "CloudCustodian"
  Environment = "$ENVIRONMENT"
  ManagedBy   = "Terraform"
}
"@

$tfvarsContent | Set-Content "terraform\terraform.tfvars"
Write-Host "  ✓ Created terraform\terraform.tfvars" -ForegroundColor Green
Write-Host ""

# Step 5: Check CloudTrail
Write-Host "Step 5: Checking CloudTrail status..." -ForegroundColor Yellow
$trails = aws cloudtrail list-trails --query 'Trails[].Name' --output text

if ($trails) {
    Write-Host "  Found CloudTrail trail(s): $trails" -ForegroundColor Green
    $firstTrail = ($trails -split '\s+')[0]
    $trailStatus = aws cloudtrail get-trail-status --name $firstTrail | ConvertFrom-Json
    
    if ($trailStatus.IsLogging) {
        Write-Host "  ✓ CloudTrail is logging" -ForegroundColor Green
    } else {
        Write-Host "  ⚠ CloudTrail is NOT logging - starting logging..." -ForegroundColor Yellow
        aws cloudtrail start-logging --name $firstTrail
    }
} else {
    Write-Host "  ⚠ No CloudTrail trail found!" -ForegroundColor Red
    Write-Host "  You need to create a CloudTrail trail for events to work" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Quick setup:" -ForegroundColor White
    Write-Host "    1. Create CloudTrail bucket: aws s3 mb s3://your-cloudtrail-bucket" -ForegroundColor Gray
    Write-Host "    2. Create trail: aws cloudtrail create-trail --name cloud-custodian-trail --s3-bucket-name your-cloudtrail-bucket" -ForegroundColor Gray
    Write-Host "    3. Start logging: aws cloudtrail start-logging --name cloud-custodian-trail" -ForegroundColor Gray
}
Write-Host ""

# Step 6: Deploy infrastructure with GitHub Actions or Terraform
Write-Host "Step 6: Ready to deploy infrastructure" -ForegroundColor Yellow
Write-Host "  Choose one of the following options:" -ForegroundColor White
Write-Host ""
Write-Host "  Option A: Deploy via GitHub Actions (Recommended)" -ForegroundColor Cyan
Write-Host "    1. Commit and push changes: " -ForegroundColor White
Write-Host "       git add ." -ForegroundColor Gray
Write-Host "       git commit -m 'Configure for testing'" -ForegroundColor Gray
Write-Host "       git push" -ForegroundColor Gray
Write-Host "    2. Go to GitHub Actions: https://github.com/ysrinu95/cloud-custodian-single-lambda/actions" -ForegroundColor White
Write-Host "    3. Manually trigger 'Deploy Infrastructure' workflow" -ForegroundColor White
Write-Host ""
Write-Host "  Option B: Deploy locally with Terraform" -ForegroundColor Cyan
Write-Host "    1. cd terraform" -ForegroundColor Gray
Write-Host "    2. terraform init" -ForegroundColor Gray
Write-Host "    3. terraform plan" -ForegroundColor Gray
Write-Host "    4. terraform apply" -ForegroundColor Gray
Write-Host ""

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Setup Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. Deploy infrastructure (see options above)" -ForegroundColor White
Write-Host "2. Run: .\test-deployment.ps1 (after deployment completes)" -ForegroundColor White
Write-Host ""
