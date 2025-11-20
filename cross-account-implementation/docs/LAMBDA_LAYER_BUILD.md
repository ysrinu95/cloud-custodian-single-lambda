# Lambda Layer Build and Deployment

This document explains the Lambda layer build process for the cross-account Cloud Custodian implementation.

---

## Overview

The cross-account implementation uses a **Lambda Layer** architecture to separate Cloud Custodian dependencies from the Lambda function code. This approach provides several benefits:

✅ **Smaller Function Package**: Function code is < 100KB  
✅ **Faster Deployments**: Only update function code, not dependencies  
✅ **Reusable Layer**: Share layer across multiple Lambda functions  
✅ **Version Control**: Track dependency versions separately  
✅ **Size Optimization**: Layer stays under 250MB limit  

---

## Architecture

```
Lambda Function (cloud-custodian-cross-account-executor)
├── Function Code (~50KB)
│   ├── lambda_function.py (main handler)
│   ├── cross_account_executor.py (policy execution logic)
│   └── validator.py (event validation)
└── Lambda Layer (~200MB)
    └── python/lib/python3.11/site-packages/
        ├── c7n/ (Cloud Custodian 0.9.30)
        ├── c7n_org/ (Multi-account support)
        ├── c7n_mailer/ (Email notifications)
        └── dependencies (argcomplete, jsonschema, etc.)
```

---

## Requirements Files Comparison

### Main Project: `requirements.txt`

```txt
# Cloud Custodian and AWS dependencies
c7n==0.9.30
c7n-org==0.6.29
c7n-awscc>=0.1.0
# boto3, botocore, python-dateutil, and pyyaml versions managed by c7n dependencies
```

**Purpose**: Production-grade dependencies for Lambda layer  
**Size**: ~200MB after optimization  
**Location**: Root of repository  

### Cross-Account: `cross-account-implementation/requirements.txt`

```txt
# Cloud Custodian and AWS dependencies
c7n==0.9.30
c7n-org==0.6.29
c7n-mailer>=0.6.23
# boto3, botocore, python-dateutil, and pyyaml versions managed by c7n dependencies
```

**Purpose**: Cross-account specific dependencies including mailer  
**Size**: ~200MB after optimization  
**Location**: cross-account-implementation/  
**Difference**: Includes `c7n-mailer` for email notifications, removes `c7n-awscc` (not needed for cross-account)  

---

## Build Process

### GitHub Actions Workflow

The build process is automated in `.github/workflows/deploy-cross-account.yml`:

#### Job 1: Build Lambda Layer

```yaml
build-layer:
  name: Build Cloud Custodian Layer
  steps:
    - name: Create layer directory
      run: |
        mkdir -p layers/python/lib/python3.11/site-packages

    - name: Install dependencies to layer
      run: |
        pip install -r requirements.txt \
          -t layers/python/lib/python3.11/site-packages/

    - name: Optimize layer size
      run: |
        # Remove test files and documentation
        find . -type d -name "tests" -exec rm -rf {} +
        find . -name "*.pyc" -delete
        
        # Remove boto3/botocore (already in Lambda runtime)
        rm -rf boto3* botocore*

    - name: Create layer zip
      run: |
        cd layers
        zip -r ../cloud-custodian-layer.zip python/ -q

    - name: Check layer size
      run: |
        SIZE=$(du -m cloud-custodian-layer.zip | cut -f1)
        if [ $SIZE -gt 250 ]; then
          echo "::error::Layer size exceeds 250MB limit!"
          exit 1
        fi

    - name: Upload layer artifact
      uses: actions/upload-artifact@v4
      with:
        name: cloud-custodian-layer
        path: layers/cloud-custodian-layer.zip
```

**Output**: `cloud-custodian-layer.zip` (~200MB)

#### Job 2: Build Lambda Function

```yaml
build-lambda:
  name: Build Lambda Function Package
  steps:
    - name: Create Lambda function zip
      run: |
        mkdir -p lambda-package
        
        # Copy Lambda handler (rename to lambda_function.py)
        cp src/lambda_handler.py lambda-package/lambda_function.py
        cp src/cross_account_executor.py lambda-package/
        cp src/validator.py lambda-package/
        
        # Create zip file
        cd lambda-package
        zip -r ../lambda-function.zip .

    - name: Upload Lambda artifact
      uses: actions/upload-artifact@v4
      with:
        name: lambda-function-package
        path: lambda-function.zip
```

**Output**: `lambda-function.zip` (~50KB)

---

## Layer Optimization

### Before Optimization (~400MB)

```
layers/python/lib/python3.11/site-packages/
├── c7n/
├── c7n_org/
├── c7n_mailer/
├── boto3/            ← Remove (in Lambda runtime)
├── botocore/         ← Remove (in Lambda runtime)
├── tests/            ← Remove
├── **pycache**/     ← Remove
├── *.pyc             ← Remove
└── *.dist-info/      ← Remove
```

### After Optimization (~200MB)

```
layers/python/lib/python3.11/site-packages/
├── c7n/
├── c7n_org/
├── c7n_mailer/
└── dependencies (minimal)
```

### Optimization Commands

```bash
cd layers/python/lib/python3.11/site-packages/

# Remove test files
find . -type d -name "tests" -exec rm -rf {} + 2>/dev/null || true
find . -type d -name "test" -exec rm -rf {} + 2>/dev/null || true

# Remove Python cache
find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find . -name "*.pyc" -delete
find . -name "*.pyo" -delete

# Remove metadata
find . -name "*.dist-info" -exec rm -rf {} + 2>/dev/null || true
find . -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true

# Remove boto3/botocore (already in Lambda runtime)
rm -rf boto3* botocore* 2>/dev/null || true
```

---

## Terraform Configuration

### Lambda Layer Resource

```hcl
resource "aws_lambda_layer_version" "custodian_layer" {
  count               = var.lambda_layer_path != "" ? 1 : 0
  filename            = var.lambda_layer_path
  layer_name          = "cloud-custodian-layer-${var.environment}"
  compatible_runtimes = ["python3.11"]
  source_code_hash    = filebase64sha256(var.lambda_layer_path)
  description         = "Cloud Custodian ${var.custodian_version} and dependencies"

  lifecycle {
    create_before_destroy = true
  }
}
```

### Lambda Function with Layer

```hcl
resource "aws_lambda_function" "custodian_cross_account_executor" {
  filename         = var.lambda_package_path
  function_name    = "cloud-custodian-cross-account-executor-${var.environment}"
  role             = aws_iam_role.lambda_execution.arn
  handler          = "lambda_function.handler"
  runtime          = "python3.11"
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size
  source_code_hash = filebase64sha256(var.lambda_package_path)

  # Attach Cloud Custodian layer
  layers = var.lambda_layer_path != "" ? [aws_lambda_layer_version.custodian_layer[0].arn] : []

  environment {
    variables = {
      POLICY_BUCKET            = var.policy_bucket
      CROSS_ACCOUNT_ROLE_NAME  = "CloudCustodianExecutionRole"
      EXTERNAL_ID_PREFIX       = "cloud-custodian"
      LOG_LEVEL                = var.log_level
    }
  }
}
```

### Variables

```hcl
variable "lambda_package_path" {
  description = "Path to the Lambda deployment package (zip file)"
  type        = string
  default     = "lambda-function.zip"
}

variable "lambda_layer_path" {
  description = "Path to the Lambda layer package (zip file with Cloud Custodian)"
  type        = string
  default     = ""
}

variable "custodian_version" {
  description = "Cloud Custodian version for layer description"
  type        = string
  default     = "0.9.30"
}
```

---

## Deployment Flow

### GitHub Actions Deployment

```bash
# Trigger deployment workflow
gh workflow run deploy-cross-account.yml \
  -f environment=central \
  -f action=apply

# Workflow steps:
1. ✅ Validate code and policies
2. ✅ Build Lambda layer (200MB)
3. ✅ Build Lambda function (50KB)
4. ✅ Download artifacts to Terraform directory
5. ✅ Terraform init
6. ✅ Terraform plan with layer path
7. ✅ Terraform apply (creates layer + function)
8. ✅ Output layer ARN and function ARN
```

### Manual Deployment

```bash
# Step 1: Build layer
cd cross-account-implementation
mkdir -p layers/python/lib/python3.11/site-packages
pip install -r requirements.txt -t layers/python/lib/python3.11/site-packages/

# Optimize
cd layers/python/lib/python3.11/site-packages/
find . -type d -name "tests" -exec rm -rf {} +
find . -name "*.pyc" -delete
rm -rf boto3* botocore*

# Create zip
cd ../../../../
zip -r layers/cloud-custodian-layer.zip layers/python/ -q

# Step 2: Build function
mkdir -p lambda-package
cp src/lambda_handler.py lambda-package/lambda_function.py
cp src/cross_account_executor.py lambda-package/
cp src/validator.py lambda-package/
cd lambda-package
zip -r ../lambda-function.zip .
cd ..

# Step 3: Deploy with Terraform
cd terraform/central-account
terraform init
terraform apply \
  -var="lambda_package_path=../../lambda-function.zip" \
  -var="lambda_layer_path=../../layers/cloud-custodian-layer.zip" \
  -var="member_account_ids=[\"123456789012\"]" \
  -var="policy_bucket=custodian-policies-172327596604"
```

---

## Layer Updates

### When to Update the Layer

- ✅ Cloud Custodian version upgrade
- ✅ New dependencies added to requirements.txt
- ✅ Security patches for packages

### When NOT to Update the Layer

- ❌ Lambda function code changes (update function only)
- ❌ Environment variable changes
- ❌ IAM permission changes

### Updating the Layer

```bash
# Update requirements.txt
echo "c7n==0.9.31" > cross-account-implementation/requirements.txt

# Rebuild layer via GitHub Actions
gh workflow run deploy-cross-account.yml \
  -f environment=central \
  -f action=apply

# Or manually
pip install -r requirements.txt -t layers/python/lib/python3.11/site-packages/ --upgrade
# ... optimization steps ...
zip -r layers/cloud-custodian-layer.zip layers/python/ -q
terraform apply -var="lambda_layer_path=../../layers/cloud-custodian-layer.zip"
```

---

## Testing

### Test Layer Import

```python
# test_layer.py
import json
import sys

def handler(event, context):
    try:
        # Test Cloud Custodian import
        import c7n
        import c7n.policy
        import c7n.resources
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Layer loaded successfully',
                'c7n_version': c7n.version.version,
                'python_version': sys.version
            })
        }
    except ImportError as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
```

### Test via AWS CLI

```bash
# Invoke Lambda to test layer
aws lambda invoke \
  --function-name cloud-custodian-cross-account-executor-prod \
  --payload '{"test": true}' \
  --region us-east-1 \
  response.json

cat response.json
```

---

## Troubleshooting

### Error: "Unable to import module 'lambda_function'"

**Cause**: Layer not properly attached or wrong handler name

**Solution**:
```bash
# Check Lambda configuration
aws lambda get-function-configuration \
  --function-name cloud-custodian-cross-account-executor-prod

# Verify handler is "lambda_function.handler"
# Verify layer is attached
```

### Error: "Layer size exceeds 250MB"

**Cause**: Layer not optimized

**Solution**:
```bash
# Re-run optimization
cd layers/python/lib/python3.11/site-packages/
find . -type d -name "tests" -exec rm -rf {} +
find . -name "*.pyc" -delete
rm -rf boto3* botocore*

# Check size
du -sh .
```

### Error: "Module 'c7n' has no attribute 'version'"

**Cause**: Corrupted installation

**Solution**:
```bash
# Clean and reinstall
rm -rf layers/
mkdir -p layers/python/lib/python3.11/site-packages
pip install -r requirements.txt -t layers/python/lib/python3.11/site-packages/ --no-cache-dir
```

---

## Best Practices

### 1. Version Pinning

✅ **Do**: Pin exact versions in requirements.txt
```txt
c7n==0.9.30
c7n-org==0.6.29
c7n-mailer==0.6.23
```

❌ **Don't**: Use flexible versions
```txt
c7n>=0.9.0
c7n-org
```

### 2. Layer Caching

Enable GitHub Actions caching:
```yaml
- name: Cache pip packages
  uses: actions/cache@v3
  with:
    path: ~/.cache/pip
    key: ${{ runner.os }}-pip-${{ hashFiles('requirements.txt') }}
```

### 3. Separate Layers for Different Environments

```bash
# Development layer (includes test dependencies)
cloud-custodian-layer-dev

# Production layer (optimized)
cloud-custodian-layer-prod
```

### 4. Layer Version Tracking

Use descriptive layer versions:
```hcl
resource "aws_lambda_layer_version" "custodian_layer" {
  layer_name  = "cloud-custodian-layer-${var.environment}"
  description = "Cloud Custodian ${var.custodian_version} - Built on ${timestamp()}"
}
```

---

## Cost Implications

### Layer Storage

- **Size**: ~200MB
- **Cost**: $0.0000000309 per GB-second
- **Monthly**: < $0.01 per layer version

### Function Package

- **Size**: ~50KB
- **Cost**: Negligible
- **Monthly**: < $0.01

### Total Lambda Layer Cost

**Estimate**: < $0.05/month for layer storage  
**Savings vs. No Layer**: Faster deployments, reduced function size

---

## Summary

The Lambda layer architecture provides:

✅ **Separation of Concerns**: Dependencies vs. code  
✅ **Smaller Deployments**: 50KB function vs. 200MB  
✅ **Faster Updates**: Update code without rebuilding dependencies  
✅ **Reusability**: Share layer across multiple functions  
✅ **Version Control**: Track dependency versions separately  
✅ **Cost Optimization**: Minimal storage costs  

**Recommendation**: Always use Lambda layers for production deployments! 🚀
