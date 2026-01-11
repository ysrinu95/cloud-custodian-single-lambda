# ============================================================================
# Cloud Custodian Cross-Account Central Account Infrastructure
# ============================================================================
# This file consolidates all Terraform configuration for the central account
# AWS provider, EventBridge, Lambda, IAM, S3, and SQS resources
# ============================================================================

# ============================================================================
# Terraform Configuration
# ============================================================================

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  backend "s3" {
    bucket  = "ysr95-cloud-custodian-tf-bkt"
    key     = "central/cloud-custodian/terraform.tfstate"
    encrypt = "true"
    region  = "us-east-1"
  }
}

provider "aws" {
  region = var.aws_region
}

# ============================================================================
# Data Sources
# ============================================================================

data "aws_caller_identity" "current" {}

# ============================================================================
# AWS Signer Code Signing Configuration
# ============================================================================

# Create code signing profile for Lambda functions
resource "aws_signer_signing_profile" "lambda_code_signing" {
  platform_id = "AWSLambda-SHA384-ECDSA"
}

# Create code signing configuration for Lambda
resource "aws_lambda_code_signing_config" "lambda_config" {
  allowed_publishers {
    signing_profile_version_arns = [aws_signer_signing_profile.lambda_code_signing.version_arn]
  }

  policies {
    untrusted_artifact_on_deployment = "Warn"
  }
}

# ============================================================================
# Variables
# ============================================================================

variable "aws_region" {
  description = "AWS region for central account resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "central"
}

variable "member_account_ids" {
  description = "List of AWS member account IDs that will send events"
  type        = list(string)
  default       = ["813185901390"]
  validation {
    condition     = length(var.member_account_ids) > 0
    error_message = "At least one member account ID must be provided."
  }
}

variable "policy_bucket" {
  description = "S3 bucket name for storing Cloud Custodian policies"
  type        = string
  default     = "ysr95-cloud-custodian-policies"
}

variable "create_policy_bucket" {
  description = "Whether to create the S3 policy bucket (set to false if bucket already exists)"
  type        = bool
  default     = true
}

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

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 900
  validation {
    condition     = var.lambda_timeout >= 60 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 60 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 256
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "log_level" {
  description = "Logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL)"
  type        = string
  default     = "INFO"
  validation {
    condition     = contains(["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"], var.log_level)
    error_message = "Log level must be one of: DEBUG, INFO, WARNING, ERROR, CRITICAL."
  }
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention value."
  }
}

variable "create_notification_queue" {
  description = "Whether to create SQS queue for notifications"
  type        = bool
  default     = true
}

variable "notification_queue_arn" {
  description = "ARN of existing SQS queue for notifications (if not creating new one)"
  type        = string
  default     = ""
}

variable "mailer_queue_url" {
  description = "SQS queue URL for cloud-custodian-mailer notifications"
  type        = string
  default     = "https://sqs.us-east-1.amazonaws.com/172327596604/custodian-mailer-queue"
}

variable "mailer_queue_arn" {
  description = "SQS queue ARN for cloud-custodian-mailer notifications"
  type        = string
  default     = "arn:aws:sqs:us-east-1:172327596604:custodian-mailer-queue"
}

variable "mailer_enabled" {
  description = "Enable notifications via cloud-custodian-mailer"
  type        = string
  default     = "true"
}

variable "create_mailer_lambda" {
  description = "Whether to create the cloud-custodian-mailer Lambda function via Terraform"
  type        = bool
  default     = false
}

variable "mailer_layer_path" {
  description = "Path to pre-built mailer layer ZIP file (if not provided, builds automatically)"
  type        = string
  default     = ""
}

variable "mailer_contact_email" {
  description = "Email address for mailer notifications (recipient)"
  type        = string
  default     = "srinivasula.yallala@optum.com"
}

variable "mailer_from_address" {
  description = "Email address for mailer from/sender address"
  type        = string
  default     = "ysrinu95@gmail.com"
}

variable "realtime_notification_method" {
  description = "Notification method for realtime policies: 'sns' (SNS topic), 'ses' (direct email), or 'both'"
  type        = string
  default     = "sns"
  
  validation {
    condition     = contains(["sns", "ses", "both"], var.realtime_notification_method)
    error_message = "realtime_notification_method must be 'sns', 'ses', or 'both'."
  }
}

variable "mailer_lambda_timeout" {
  description = "Timeout for mailer Lambda in seconds"
  type        = number
  default     = 300
}

variable "code_signing_config_arn" {
  description = "ARN of the code signing configuration for Lambda functions (required for security compliance)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "cloud-custodian"
}

# ============================================================================
# SQS Resources - Notification Queues
# ============================================================================

# SQS Queue for Real-Time Notifications (processed by cross-account-executor)
resource "aws_sqs_queue" "realtime_notifications" {
  name                       = "aikyam-cloud-custodian-realtime-notifications"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 86400  # 24 hours
  receive_wait_time_seconds  = 0      # No long polling for real-time
  
  tags = merge(
    var.tags,
    {
      Name      = "aikyam-cloud-custodian-realtime-notifications"
      purpose   = "Real-time event-driven policy notifications"
      terraform = "True"
      oid-owned = "True"
    }
  )
}

# SQS Queue for Periodic Policy Notifications (processed by mailer Lambda)
resource "aws_sqs_queue" "periodic_notifications" {
  name                       = "aikyam-cloud-custodian-periodic-notifications"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 345600  # 4 days
  receive_wait_time_seconds  = 20      # Long polling for efficiency
  
  tags = merge(
    var.tags,
    {
      Name      = "aikyam-cloud-custodian-periodic-notifications"
      purpose   = "Periodic scheduled policy notifications with email templates"
      terraform = "True"
      oid-owned = "True"
    }
  )
}

# SQS Queue Policy for Real-Time Queue - Allow member accounts to send messages
resource "aws_sqs_queue_policy" "realtime_notifications" {
  queue_url = aws_sqs_queue.realtime_notifications.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowMemberAccountsSendMessage"
        Effect = "Allow"
        Principal = {
          AWS = [
            for account_id in var.member_account_ids :
            "arn:aws:iam::${account_id}:root"
          ]
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.realtime_notifications.arn
      }
    ]
  })
}

# SQS Queue Policy for Periodic Queue - Allow member accounts to send messages
resource "aws_sqs_queue_policy" "periodic_notifications" {
  queue_url = aws_sqs_queue.periodic_notifications.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowMemberAccountsSendMessage"
        Effect = "Allow"
        Principal = {
          AWS = [
            for account_id in var.member_account_ids :
            "arn:aws:iam::${account_id}:root"
          ]
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.periodic_notifications.arn
      }
    ]
  })
}

# ============================================================================
# EventBridge Resources - Custom Event Bus
# ============================================================================

# EventBridge Custom Bus for receiving cross-account events
resource "aws_cloudwatch_event_bus" "centralized" {
  name = "aikyam-cloud-custodian-centralized-security-events"

  tags = merge(
    var.tags,
    {
      Name      = "aikyam-cloud-custodian-centralized-security-events"
      terraform = "True"
      oid-owned = "True"
    }
  )
}

# EventBridge Bus Policy - Allow member accounts to put events
resource "aws_cloudwatch_event_bus_policy" "allow_member_accounts" {
  event_bus_name = aws_cloudwatch_event_bus.centralized.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowMemberAccountPutEvents"
      Effect = "Allow"
      Principal = {
        AWS = [for account_id in var.member_account_ids : "arn:aws:iam::${account_id}:root"]
      }
      Action   = "events:PutEvents"
      Resource = aws_cloudwatch_event_bus.centralized.arn
    }]
  })
}

# ============================================================================
# EventBridge Rules - Local Account Events (Default Bus)
# ============================================================================

# EventBridge Rule on default bus - Trigger Lambda for local security events
resource "aws_cloudwatch_event_rule" "custodian_local_trigger" {
  name        = "aikyam-cloud-custodian-local-trigger"
  description = "Trigger Cloud Custodian Lambda for security events (CloudTrail, GuardDuty, Security Hub) in central account (172327596604)"

  event_pattern = jsonencode({
    "$or" = [
      {
        # CloudTrail events for EFS, ECR, EKS, ElastiCache, Kinesis, and SNS in central account
        account = [data.aws_caller_identity.current.account_id]
        source  = ["aws.elasticfilesystem", "aws.ecr", "aws.eks", "aws.elasticache", "aws.kinesis", "aws.sns"]
        detail-type = ["AWS API Call via CloudTrail"]
        detail = {
          eventName = [
            # EFS events
            "CreateFileSystem",
            "PutFileSystemPolicy",
            "DeleteFileSystemPolicy",
            # ECR events
            "CreateRepository",
            "SetRepositoryPolicy",
            "PutRepositoryPolicy",
            "DeleteRepositoryPolicy",
            "PutImageScanningConfiguration",
            # EKS events
            "CreateCluster",
            "UpdateClusterConfig",
            "UpdateClusterVersion",
            # ElastiCache events
            "CreateCacheCluster",
            "CreateReplicationGroup",
            "ModifyCacheCluster",
            "ModifyReplicationGroup",
            # Kinesis events
            "CreateStream",
            "StartStreamEncryption",
            "StopStreamEncryption",
            # SNS events
            "CreateTopic",
            "SetTopicAttributes"
          ]
        }
      },
      {
        # GuardDuty findings with severity >= 7 (HIGH and CRITICAL) in central account
        account     = [data.aws_caller_identity.current.account_id]
        source      = ["aws.guardduty"]
        detail-type = ["GuardDuty Finding"]
        detail = {
          severity = [
            { "numeric" : [">=", 7] }
          ]
        }
      },
      {
       # Security Hub findings that are CRITICAL or HIGH severity with FAILED compliance in central account
       account     = [data.aws_caller_identity.current.account_id]
       source      = ["aws.securityhub"]
       detail-type = ["Security Hub Findings - Imported"]
       detail = {
         findings = {
           Severity = {
             Label = ["CRITICAL", "HIGH","MEDIUM"]
           }
           Compliance = {
             Status = ["FAILED"]
           }
           # Only forward findings originating from AWS Config (ProductName == "Config")
           ProductFields = {
             "aws/securityhub/ProductName" = ["Config"]
           }                
         }
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name      = "cloud-custodian-local-trigger"
      terraform = "True"
      oid-owned = "True"
    }
  )
}

# EventBridge Target - Lambda function for local events
resource "aws_cloudwatch_event_target" "lambda_local" {
  rule      = aws_cloudwatch_event_rule.custodian_local_trigger.name
  arn       = aws_lambda_function.custodian_cross_account_executor.arn
}

# Lambda Permission - Allow EventBridge default bus to invoke
resource "aws_lambda_permission" "allow_eventbridge_local" {
  statement_id  = "AllowExecutionFromEventBridgeLocal"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.custodian_cross_account_executor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.custodian_local_trigger.arn
}

# ============================================================================
# EventBridge Rules - Cross-Account Events (Custom Bus)
# ============================================================================

# EventBridge Rule on custom bus - Trigger Lambda for all security events from member accounts
resource "aws_cloudwatch_event_rule" "custodian_security_events_from_members" {
  name           = "aikyam-cloud-custodian-security-events-from-members"
  description    = "Trigger Cloud Custodian Lambda for security events (CloudTrail, GuardDuty, Security Hub) from member accounts"
  event_bus_name = aws_cloudwatch_event_bus.centralized.name

  event_pattern = jsonencode({
    "$or" = [
      {
        # CloudTrail events for EC2, ELB, S3, CloudFront, ECR, EKS, EFS, ElastiCache, Kinesis, and SNS
        detail-type = ["AWS API Call via CloudTrail"]
        detail = {
          eventSource = [
            "ec2.amazonaws.com",
            "elasticloadbalancing.amazonaws.com",
            "s3.amazonaws.com",
            "cloudfront.amazonaws.com",
            "ecr.amazonaws.com",
            "eks.amazonaws.com",
            "elasticfilesystem.amazonaws.com",
            "elasticache.amazonaws.com",
            "kinesis.amazonaws.com",
            "sns.amazonaws.com"
          ]
          eventName = [
            # EC2 events
            "RunInstances",
            "ModifyImageAttribute",
            "CreateImage",
            "CopyImage",
            # ALB events
            "CreateLoadBalancer",
            "CreateListener",
            "ModifyListener",
            "ModifyLoadBalancerAttributes",
            "DeleteLoadBalancer",
            "DeleteListener",
            # S3 events
            "CreateBucket",
            "PutBucketPolicy",
            "PutBucketAcl",
            "PutBucketPublicAccessBlock",
            "DeleteBucketPublicAccessBlock",
            "PutBucketEncryption",
            "DeleteBucketEncryption",
            # CloudFront events
            "CreateDistribution",
            "UpdateDistribution",
            "CreateDistributionWithTags",
            # ECR events
            "CreateRepository",
            "SetRepositoryPolicy",
            "PutRepositoryPolicy",
            "DeleteRepositoryPolicy",
            "PutImageScanningConfiguration",
            # EKS events
            "CreateCluster",
            "UpdateClusterConfig",
            "UpdateClusterVersion",
            # EFS events
            "CreateFileSystem",
            "PutFileSystemPolicy",
            "DeleteFileSystemPolicy",
            # ElastiCache events
            "CreateCacheCluster",
            "CreateReplicationGroup",
            "ModifyCacheCluster",
            "ModifyReplicationGroup",
            # Kinesis events
            "CreateStream",
            "StartStreamEncryption",
            "StopStreamEncryption",
            # SNS events
            "CreateTopic",
            "SetTopicAttributes"
          ]
        }
      },
      {
        # GuardDuty findings with severity >= 7 (HIGH and CRITICAL)
        source      = ["aws.guardduty"]
        detail-type = ["GuardDuty Finding"]
        detail = {
          severity = [
            { "numeric" : [">=", 7] }
          ]
        }
      },
      {
        # Security Hub findings that are CRITICAL or HIGH severity with FAILED compliance status
        source      = ["aws.securityhub"]
        detail-type = ["Security Hub Findings - Imported"]
        detail = {
          findings = {
            Severity = {
              Label = ["CRITICAL", "HIGH","MEDIUM"]
            }
            Compliance = {
              Status = ["FAILED"]
            }
           # Only forward findings originating from AWS Config (ProductName == "Config")
           ProductFields = {
             "aws/securityhub/ProductName" = ["Config"]
           }                         
          }
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name      = "aikyam-cloud-custodian-security-events-from-members"
      terraform = "True"
      oid-owned = "True"
    }
  )
}

# EventBridge Target - Lambda function for all security events from member accounts
resource "aws_cloudwatch_event_target" "lambda_security_events_from_members" {
  rule           = aws_cloudwatch_event_rule.custodian_security_events_from_members.name
  event_bus_name = aws_cloudwatch_event_bus.centralized.name
  arn            = aws_lambda_function.custodian_cross_account_executor.arn
}

# Lambda Permission - Allow EventBridge to invoke for all security events
resource "aws_lambda_permission" "allow_eventbridge_security_events" {
  statement_id  = "AllowExecutionFromEventBridgeSecurityEvents"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.custodian_cross_account_executor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.custodian_security_events_from_members.arn
}

# ============================================================================
# Lambda Resources
# ============================================================================

# Local variables for layer and function paths
locals {
  layer_requirements_path = "${path.module}/../../lambda_functions/cloud-custodian-layer/requirements.txt"
  layer_build_dir         = "${path.module}/../../lambda_functions/cloud-custodian-layer"
  layer_zip_name          = "cloud-custodian-layer.zip"
  
  # Lambda function source paths
  lambda_source_dir       = "${path.module}/../../lambda_functions/cloud-custodian"
  lambda_build_dir        = "${path.module}/lambda-build"
  lambda_zip_name         = "lambda-function.zip"
}

# Build Cloud Custodian Lambda Layer
resource "null_resource" "custodian_layer_build" {
  count = var.lambda_layer_path == "" ? 1 : 0

  triggers = {
    requirements = fileexists(local.layer_requirements_path) ? filesha1(local.layer_requirements_path) : "placeholder"
    python_version = "3.11"
    build_version = "v6"  # Updated for CloudFront distribution ID filtering support
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "📦 Building Cloud Custodian Lambda layer..."
      
      # Navigate to layer directory
      cd ${local.layer_build_dir}
      
      # Clean up previous builds
      rm -rf python ${local.layer_zip_name} 2>/dev/null || true
      
      # Create layer directory structure
      mkdir -p python/lib/python3.11/site-packages
      
      # Install dependencies (use python3 -m pip for better compatibility)
      echo "📥 Installing Cloud Custodian and dependencies..."
      python3 -m pip install --upgrade pip --quiet
      python3 -m pip install -r requirements.txt -t python/lib/python3.11/site-packages/ --no-cache-dir --quiet
      
      # Optimize layer size
      echo "🗜️ Optimizing layer size..."
      cd python/lib/python3.11/site-packages/
      
      # Remove test files and documentation
      find . -type d -name "tests" -exec rm -rf {} + 2>/dev/null || true
      find . -type d -name "test" -exec rm -rf {} + 2>/dev/null || true
      find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
      find . -name "*.pyc" -delete 2>/dev/null || true
      find . -name "*.pyo" -delete 2>/dev/null || true
      find . -name "*.dist-info" -exec rm -rf {} + 2>/dev/null || true
      find . -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true
      
      # Remove boto3/botocore (already in Lambda runtime)
      rm -rf boto3* botocore* 2>/dev/null || true
      
      # Return to layer directory and create zip
      cd ../../../..
      echo "🗜️ Creating layer zip file..."
      zip -r ${local.layer_zip_name} python/ -q
      
      # Check layer size (cross-platform compatible)
      if command -v stat &> /dev/null; then
        SIZE_BYTES=$(stat -f%z ${local.layer_zip_name} 2>/dev/null || stat -c%s ${local.layer_zip_name})
        SIZE_MB=$((SIZE_BYTES / 1024 / 1024))
        echo "📏 Layer size: $${SIZE_MB}MB"
        
        if [ $SIZE_MB -gt 250 ]; then
          echo "❌ ERROR: Layer size exceeds 250MB limit!"
          exit 1
        elif [ $SIZE_MB -gt 200 ]; then
          echo "⚠️  WARNING: Layer size approaching 250MB limit ($${SIZE_MB}MB)"
        else
          echo "✅ Layer size is optimal: $${SIZE_MB}MB"
        fi
      else
        echo "⚠️  Cannot check layer size (stat command not available)"
      fi
      
      # Clean up build artifacts
      rm -rf python
      
      echo "✅ Layer build complete: ${local.layer_zip_name}"
    EOT
  }
}

# Lambda Layer for Cloud Custodian
resource "aws_lambda_layer_version" "custodian_layer" {
  count = var.lambda_layer_path == "" ? 1 : 0

  filename            = "${local.layer_build_dir}/${local.layer_zip_name}"
  layer_name          = "cloud-custodian-layer"
  compatible_runtimes = ["python3.11", "python3.12"]
  description         = "Cloud Custodian and dependencies (built by Terraform)"


  source_code_hash = fileexists("${local.layer_build_dir}/${local.layer_zip_name}") ? filebase64sha256("${local.layer_build_dir}/${local.layer_zip_name}") : null

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [null_resource.custodian_layer_build]
}

# ========================================
# Lambda Function Build
# ========================================

# Build Lambda Function Package
resource "null_resource" "lambda_function_build" {
  triggers = {
    lambda_handler   = fileexists("${local.lambda_source_dir}/lambda_handler.py") ? filesha1("${local.lambda_source_dir}/lambda_handler.py") : "placeholder"
    validator       = fileexists("${local.lambda_source_dir}/validator.py") ? filesha1("${local.lambda_source_dir}/validator.py") : "placeholder"
    cross_account_executor = fileexists("${local.lambda_source_dir}/cross_account_executor.py") ? filesha1("${local.lambda_source_dir}/cross_account_executor.py") : "placeholder"
    realtime_notifier = fileexists("${local.lambda_source_dir}/realtime_notifier.py") ? filesha1("${local.lambda_source_dir}/realtime_notifier.py") : "placeholder"
    event_filter_builder = fileexists("${local.lambda_source_dir}/event_filter_builder.py") ? filesha1("${local.lambda_source_dir}/event_filter_builder.py") : "placeholder"
    build_version = "v83"  # Fixed filter execution: use filter_resources() for pre-fetched resources instead of bypassing filters
  }

  provisioner "local-exec" {
    working_dir = path.module
    command = <<-EOT
      set -e
      echo "📦 Building Lambda function package..."
      
      # Resolve absolute paths
      SOURCE_DIR="$(cd ../../lambda-functions/cloud-custodian 2>/dev/null && pwd)" || SOURCE_DIR="${local.lambda_source_dir}"
      BUILD_DIR="${local.lambda_build_dir}"
      ZIP_NAME="${local.lambda_zip_name}"
      
      echo "📍 Source directory: $${SOURCE_DIR}"
      echo "📍 Build directory: $${BUILD_DIR}"
      
      # Create build directory
      rm -rf "$${BUILD_DIR}" 2>/dev/null || true
      mkdir -p "$${BUILD_DIR}"
      
      # Check if source files exist
      if [ ! -f "$${SOURCE_DIR}/lambda_handler.py" ]; then
        echo "❌ ERROR: lambda_handler.py not found at $${SOURCE_DIR}/lambda_handler.py"
        echo "Available files in source directory:"
        ls -la "$${SOURCE_DIR}/" 2>/dev/null || echo "Source directory does not exist"
        exit 1
      fi
      
      # Copy Lambda source files
      echo "📄 Copying Lambda source files..."
      cp "$${SOURCE_DIR}/lambda_handler.py" "$${BUILD_DIR}/lambda_function.py"
      
      if [ -f "$${SOURCE_DIR}/event_validator.py" ]; then
        cp "$${SOURCE_DIR}/event_validator.py" "$${BUILD_DIR}/"
        echo "  ✓ event_validator.py copied"
      fi
      
      if [ -f "$${SOURCE_DIR}/cross_account_executor.py" ]; then
        cp "$${SOURCE_DIR}/cross_account_executor.py" "$${BUILD_DIR}/"
        echo "  ✓ cross_account_executor.py copied"
      fi
      
      if [ -f "$${SOURCE_DIR}/realtime_notifier.py" ]; then
        cp "$${SOURCE_DIR}/realtime_notifier.py" "$${BUILD_DIR}/"
        echo "  ✓ realtime_notifier.py copied"
      fi
      
      if [ -f "$${SOURCE_DIR}/compliance_pre_validator.py" ]; then
        cp "$${SOURCE_DIR}/compliance_pre_validator.py" "$${BUILD_DIR}/"
        echo "  ✓ compliance_pre_validator.py copied"
      fi
      
      if [ -f "$${SOURCE_DIR}/event_filter_builder.py" ]; then
        cp "$${SOURCE_DIR}/event_filter_builder.py" "$${BUILD_DIR}/"
        echo "  ✓ event_filter_builder.py copied"
      fi
      
      echo "  ℹ️  Note: Real-time policies → realtime SQS → immediate SNS | Periodic policies → periodic SQS → mailer Lambda"
      
      # Create the zip file
      echo "🗜️ Creating Lambda function zip..."
      cd "$${BUILD_DIR}"
      zip -r "../$${ZIP_NAME}" . -q
      cd - > /dev/null
      
      # Check zip size
      if [ -f "$${ZIP_NAME}" ]; then
        SIZE_BYTES=$(stat -f%z "$${ZIP_NAME}" 2>/dev/null || stat -c%s "$${ZIP_NAME}")
        SIZE_KB=$((SIZE_BYTES / 1024))
        echo "📏 Lambda package size: $${SIZE_KB}KB"
      fi
      
      # Clean up build directory but keep zip
      rm -rf "$${BUILD_DIR}"
      
      echo "✅ Lambda function build complete: $${ZIP_NAME}"
      echo "✅ Lambda handler is ready: lambda_function.handler"
    EOT
  }
}

# Data source to get stable hash of lambda package
data "archive_file" "lambda_function_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda-function-data.zip"
  
  source {
    content  = "placeholder"
    filename = "placeholder.txt"
  }

  depends_on = [null_resource.lambda_function_build]
}

# Lambda Layer from file or built
resource "aws_lambda_layer_version" "custodian_layer_external" {
  count               = var.lambda_layer_path != "" ? 1 : 0
  filename            = var.lambda_layer_path
  layer_name          = "cloud-custodian-layer"
  compatible_runtimes = ["python3.11"]
  source_code_hash    = filebase64sha256(var.lambda_layer_path)
}

# Lambda Function - Cross-account Cloud Custodian executor
resource "aws_lambda_function" "custodian_cross_account_executor" {
  filename         = "${path.module}/${local.lambda_zip_name}"
  function_name    = "cloud-custodian-cross-account-executor"
  role             = aws_iam_role.lambda_execution.arn
  handler          = "lambda_function.handler"
  runtime          = "python3.11"
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size
  source_code_hash = null_resource.lambda_function_build.id

  # Code signing configuration for security compliance (required)
  code_signing_config_arn = var.code_signing_config_arn != "" ? var.code_signing_config_arn : aws_lambda_code_signing_config.lambda_config.arn

  # Attach Cloud Custodian layer - use built or external layer
  layers = [
    var.lambda_layer_path != "" ? aws_lambda_layer_version.custodian_layer_external[0].arn : aws_lambda_layer_version.custodian_layer[0].arn
  ]

  environment {
    variables = {
      POLICY_BUCKET           = var.policy_bucket
      ACCOUNT_MAPPING_KEY     = "config/account-policy-mapping.json"
      CROSS_ACCOUNT_ROLE_NAME = "CloudCustodianExecutionRole"
      EXTERNAL_ID_PREFIX      = "cloud-custodian"
      LOG_LEVEL               = var.log_level
      REALTIME_QUEUE_URL      = aws_sqs_queue.realtime_notifications.url
      MAILER_ENABLED          = var.mailer_enabled
      SNS_TOPIC_ARN           = aws_sns_topic.custodian_mailer_notifications.arn
      NOTIFICATION_METHOD     = var.realtime_notification_method
      FROM_ADDRESS            = var.mailer_from_address
      TO_ADDRESSES            = var.mailer_contact_email
      TEMPLATES_BUCKET        = var.policy_bucket
      REGION                  = var.aws_region
    }
  }

  depends_on = [
    null_resource.lambda_function_build,
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_execution_policy
  ]

  tags = merge(
    var.tags,
    {
      # Identification tags
      Name             = "cloud-custodian-cross-account-executor"
      application      = "cloud-custodian"
      component        = "executor"
      repo             = "aikyam-everything-as-code"
      
      # Required organizational/governance tags for SCP compliance
      terraform        = "True"
      oid-owned        = "True"
      aide-id          = "UHGWM110-019726"
      service-tier     = "p1"
      
      # Contact and management tags
      contact          = "srinivasula.yallala@optum.com"
      environment      = var.environment
      managed-by       = "terraform"
      
      # Optional Optum governance tags
      OptumGovernance  = "Optum"
      costcenter       = "platform"
      owner            = "platform-team"
    }
  )
}

# Basic Lambda Execution Policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/cloud-custodian-cross-account-executor"
  retention_in_days = var.log_retention_days

  tags = merge(
    var.tags,
    {
      Name      = "cloud-custodian-cross-account-executor-logs"
      terraform = "True"
      oid-owned = "True"
    }
  )
}

# ============================================================================
# IAM Resources
# ============================================================================

# IAM Role for Lambda Execution
resource "aws_iam_role" "lambda_execution" {
  name = "cloud-custodian-cross-account-executor-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = merge(
    var.tags,
    {
      Name      = "cloud-custodian-cross-account-executor-role"
      terraform = "True"
      oid-owned = "True"
    }
  )
}

# IAM Policy - Lambda execution permissions
resource "aws_iam_role_policy" "lambda_execution_policy" {
  name = "lambda-execution-policy"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AssumeRoleInMemberAccounts"
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Resource = [
          for account_id in var.member_account_ids :
          "arn:aws:iam::${account_id}:role/CloudCustodianExecutionRole"
        ]
        Condition = {
          StringEquals = {
            "sts:ExternalId" = [
              for account_id in var.member_account_ids :
              "cloud-custodian-${account_id}"
            ]
          }
        }
      },
      {
        Sid    = "S3PolicyAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.policy_bucket}",
          "arn:aws:s3:::${var.policy_bucket}/*"
        ]
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/*",
          "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/cloud-custodian/*"
        ]
      },
      {
        Sid    = "CloudWatchLogsDescribe"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:*"
        ]
      },
      {
        Sid    = "SQSRealtimeQueue"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:ChangeMessageVisibility",
          "sqs:GetQueueUrl",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.realtime_notifications.arn
      },
      {
        Sid    = "SNSPublishNotifications"
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = "arn:aws:sns:${var.aws_region}:${data.aws_caller_identity.current.account_id}:custodian-mailer-notifications"
      },
      {
        Sid    = "SESEmailSending"
        Effect = "Allow"
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ]
        Resource = [
          aws_ses_email_identity.mailer.arn,
          "arn:aws:ses:${var.aws_region}:${data.aws_caller_identity.current.account_id}:identity/*"
        ]
      },
      {
        Sid    = "S3TemplatesRead"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.policy_bucket}/templates/*",
          "arn:aws:s3:::${var.policy_bucket}"
        ]
      },
      {
        Sid    = "EC2DescribeActions"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceAttribute",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeTags"
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2WriteActions"
        Effect = "Allow"
        Action = [
          "ec2:TerminateInstances",
          "ec2:StopInstances",
          "ec2:ModifyInstanceAttribute",
          "ec2:CreateTags"
        ]
        Resource = "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/*"
        Condition = {
          StringEquals = {
            "aws:ResourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "ALBDescribeActions"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DescribeTags"
        ]
        Resource = "*"
      },
      {
        Sid    = "IAMReadOnly"
        Effect = "Allow"
        Action = [
          "iam:ListAccountAliases"
        ]
        Resource = "*"
      },
      {
        Sid    = "IAMGetActions"
        Effect = "Allow"
        Action = [
          "iam:GetRole",
          "iam:GetRolePolicy"
        ]
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*"
        ]
      }
    ]
  })
}

# ============================================================================
# IAM Resources - Cloud Custodian Execution Role (for Jenkins CI/CD)
# ============================================================================

# IAM Role - Cloud Custodian execution role (to be assumed by service user in central account)
resource "aws_iam_role" "custodian_execution" {
  name        = "CloudCustodianExecutionRole"
  description = "Role for executing Cloud Custodian policies via Jenkins CI/CD pipeline in central account"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowLambdaAssume"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  max_session_duration = 3600 # 1 hour

  tags = merge(
    var.tags,
    {
      Name      = "CloudCustodianExecutionRole"
      terraform = "True"
      oid-owned = "True"
    }
  )
}

# IAM Policy - Cloud Custodian remediation permissions for central account
resource "aws_iam_policy" "custodian_execution_policy" {
  name        = "CloudCustodianExecutionPolicy"
  description = "Permissions for Cloud Custodian to scan and remediate resources in central account"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2DescribeActions"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceAttribute",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeTags",
          "ec2:DescribeVolumes",
          "ec2:DescribeSnapshots",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeImages",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = [var.aws_region]
          }
        }
      },
      {
        Sid    = "EC2RemediationActions"
        Effect = "Allow"
        Action = [
          "ec2:StopInstances",
          "ec2:StartInstances",
          "ec2:TerminateInstances",
          "ec2:CreateTags",
          "ec2:DeleteTags",
          "ec2:ModifyInstanceAttribute",
        ]
        Resource = "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/*"
        Condition = {
          StringEquals = {
            "aws:ResourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "S3ReadOnlyActions"
        Effect = "Allow"
        Action = [
          "s3:GetBucketPolicy",
          "s3:GetBucketPublicAccessBlock",
          "s3:GetBucketEncryption",
          "s3:GetBucketVersioning",
          "s3:GetBucketTagging",
          "s3:ListBucket",
        ]
        Resource = "arn:aws:s3:::*"
        Condition = {
          StringEquals = {
            "aws:ResourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "S3ListBuckets"
        Effect = "Allow"
        Action = [
          "s3:ListAllMyBuckets",
        ]
        Resource = "*"
      },
      {
        Sid    = "S3WriteActions"
        Effect = "Allow"
        Action = [
          "s3:PutBucketPublicAccessBlock",
          "s3:PutBucketEncryption",
          "s3:PutBucketVersioning",
          "s3:PutBucketTagging",
        ]
        Resource = "arn:aws:s3:::*"
        Condition = {
          StringEquals = {
            "aws:ResourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "RDSDescribeActions"
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances",
          "rds:DescribeDBClusters",
          "rds:DescribeDBSnapshots",
          "rds:ListTagsForResource",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = [var.aws_region]
          }
        }
      },
      {
        Sid    = "RDSRemediationActions"
        Effect = "Allow"
        Action = [
          "rds:AddTagsToResource",
          "rds:ModifyDBInstance",
          "rds:StopDBInstance",
        ]
        Resource = [
          "arn:aws:rds:${var.aws_region}:${data.aws_caller_identity.current.account_id}:db:*",
          "arn:aws:rds:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster:*",
        ]
      },
      {
        Sid    = "IAMReadOnlyActions"
        Effect = "Allow"
        Action = [
          "iam:GetUser",
          "iam:ListUsers",
          "iam:ListAccessKeys",
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/*"
      },
      {
        Sid    = "IAMAccessKeyActions"
        Effect = "Allow"
        Action = [
          "iam:UpdateAccessKey",
          "iam:DeleteAccessKey",
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/*"
        Condition = {
          StringEquals = {
            "iam:ResourceTag/custodian-managed" = "true"
          }
        }
      },
      {
        Sid    = "IAMTaggingActions"
        Effect = "Allow"
        Action = [
          "iam:TagUser",
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/*"
      },
      {
        Sid    = "LambdaReadActions"
        Effect = "Allow"
        Action = [
          "lambda:GetFunction",
          "lambda:ListFunctions",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = [var.aws_region]
          }
        }
      },
      {
        Sid    = "LambdaTaggingActions"
        Effect = "Allow"
        Action = [
          "lambda:TagResource",
        ]
        Resource = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:*"
      },
      {
        Sid    = "SecurityServicesReadOnly"
        Effect = "Allow"
        Action = [
          "guardduty:GetFindings",
          "guardduty:ListFindings",
          "securityhub:GetFindings",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = [var.aws_region]
          }
        }
      },
      {
        Sid    = "SecurityHubUpdateFindings"
        Effect = "Allow"
        Action = [
          "securityhub:BatchUpdateFindings",
        ]
        Resource = "arn:aws:securityhub:${var.aws_region}:${data.aws_caller_identity.current.account_id}:hub/default"
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/cloud-custodian/*"
      },
      {
        Sid    = "SQSAccess"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueUrl",
          "sqs:GetQueueAttributes",
        ]
        Resource = [
          "arn:aws:sqs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:custodian-mailer-queue",
          "arn:aws:sqs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:custodian-mailer-queue-*",
        ]
      },
      {
        Sid    = "ElastiCacheDescribeActions"
        Effect = "Allow"
        Action = [
          "elasticache:DescribeCacheClusters",
          "elasticache:DescribeReplicationGroups",
          "elasticache:DescribeCacheSubnetGroups",
          "elasticache:DescribeCacheParameterGroups",
          "elasticache:ListTagsForResource"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = [var.aws_region]
          }
        }
      },
      {
        Sid    = "ElastiCacheRemediationActions"
        Effect = "Allow"
        Action = [
          "elasticache:ModifyReplicationGroup",
          "elasticache:ModifyCacheCluster",
          "elasticache:AddTagsToResource",
          "elasticache:RemoveTagsFromResource"
        ]
        Resource = [
          "arn:aws:elasticache:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster:*",
          "arn:aws:elasticache:${var.aws_region}:${data.aws_caller_identity.current.account_id}:replicationgroup:*"
        ]
      },
      {
        Sid    = "EFSDescribeActions"
        Effect = "Allow"
        Action = [
          "elasticfilesystem:DescribeFileSystems",
          "elasticfilesystem:DescribeMountTargets",
          "elasticfilesystem:DescribeFileSystemPolicy",
          "elasticfilesystem:DescribeTags"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = [var.aws_region]
          }
        }
      },
      {
        Sid    = "EFSRemediationActions"
        Effect = "Allow"
        Action = [
          "elasticfilesystem:PutFileSystemPolicy",
          "elasticfilesystem:DeleteFileSystemPolicy",
          "elasticfilesystem:TagResource",
          "elasticfilesystem:UntagResource"
        ]
        Resource = [
          "arn:aws:elasticfilesystem:${var.aws_region}:${data.aws_caller_identity.current.account_id}:file-system/*"
        ]
      },
      {
        Sid    = "KinesisDescribeActions"
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:DescribeStreamSummary",
          "kinesis:ListStreams",
          "kinesis:ListTagsForStream"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = [var.aws_region]
          }
        }
      },
      {
        Sid    = "KinesisRemediationActions"
        Effect = "Allow"
        Action = [
          "kinesis:StartStreamEncryption",
          "kinesis:StopStreamEncryption",
          "kinesis:AddTagsToStream",
          "kinesis:RemoveTagsFromStream"
        ]
        Resource = [
          "arn:aws:kinesis:${var.aws_region}:${data.aws_caller_identity.current.account_id}:stream/*"
        ]
      },
      {
        Sid    = "SNSDescribeActions"
        Effect = "Allow"
        Action = [
          "sns:ListTopics",
          "sns:GetTopicAttributes",
          "sns:ListTagsForResource"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = [var.aws_region]
          }
        }
      },
      {
        Sid    = "SNSRemediationActions"
        Effect = "Allow"
        Action = [
          "sns:SetTopicAttributes",
          "sns:TagResource",
          "sns:UntagResource"
        ]
        Resource = [
          "arn:aws:sns:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
        ]
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name      = "CloudCustodianExecutionPolicy"
      terraform = "True"
      oid-owned = "True"
    }
  )
}

# Attach execution policy to execution role
resource "aws_iam_role_policy_attachment" "custodian_execution_permissions" {
  role       = aws_iam_role.custodian_execution.name
  policy_arn = aws_iam_policy.custodian_execution_policy.arn
}

# ============================================================================
# S3 Resources
# ============================================================================

# S3 Bucket for Policies (optional - create only if specified)
resource "aws_s3_bucket" "policies" {
  count  = var.create_policy_bucket ? 1 : 0
  bucket = var.policy_bucket

  tags = merge(
    var.tags,
    {
      Name      = "aikyam-cloud-custodian-policies"
      terraform = "True"
      oid-owned = "True"
    }
  )
}

resource "aws_s3_bucket_versioning" "policies" {
  count  = var.create_policy_bucket ? 1 : 0
  bucket = aws_s3_bucket.policies[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "policies" {
  count  = var.create_policy_bucket ? 1 : 0
  bucket = aws_s3_bucket.policies[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "policies" {
  count  = var.create_policy_bucket ? 1 : 0
  bucket = aws_s3_bucket.policies[0].id

  rule {
    id     = "archive-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_transition {
      noncurrent_days = 90
      storage_class   = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ============================================================================
# Upload Mailer Templates to S3
# ============================================================================

# Upload email templates to policies bucket (templates/ prefix)
resource "null_resource" "upload_templates" {
  count = var.create_mailer_lambda && var.create_policy_bucket ? 1 : 0

  triggers = {
    # Trigger upload when templates change
    templates_hash = sha256(join("", [for f in fileset("${path.module}/../../../../c7n/config/mailer-templates", "*.j2") : filesha256("${path.module}/../../../../c7n/config/mailer-templates/${f}")]))
  }

  provisioner "local-exec" {
    working_dir = path.module
    command = <<-EOT
      set -e
      echo "📧 Uploading email templates to S3..."
      
      REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD/../../../..")"
      TEMPLATES_SOURCE="$REPO_ROOT/c7n/config/mailer-templates"
      BUCKET_NAME="${var.policy_bucket}"
      
      if [ -d "$TEMPLATES_SOURCE" ]; then
        aws s3 sync "$TEMPLATES_SOURCE/" "s3://$BUCKET_NAME/templates/" \
          --exclude "*" --include "*.j2" --include "*.html" \
          --delete
        
        TEMPLATE_COUNT=$(aws s3 ls "s3://$BUCKET_NAME/templates/" | wc -l)
        echo "✅ Uploaded $TEMPLATE_COUNT templates to s3://$BUCKET_NAME/templates/"
      else
        echo "⚠️  WARNING: Templates directory not found at $TEMPLATES_SOURCE"
      fi
    EOT
  }

  depends_on = [aws_s3_bucket.policies]
}

# ============================================================================
# SQS Resources
# ============================================================================

# SQS Queue for Mailer Notifications
resource "aws_sqs_queue" "custodian_mailer" {
  count                      = var.create_notification_queue ? 1 : 0
  name                       = "custodian-mailer-queue"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 1209600 # 14 days

  tags = merge(
    var.tags,
    {
      Name      = "custodian-mailer-queue"
      terraform = "True"
      oid-owned = "True"
    }
  )
}

# SQS DLQ for Mailer
resource "aws_sqs_queue" "custodian_mailer_dlq" {
  count                     = var.create_notification_queue ? 1 : 0
  name                      = "custodian-mailer-dlq"
  message_retention_seconds = 1209600 # 14 days

  tags = merge(
    var.tags,
    {
      Name      = "custodian-mailer-dlq"
      terraform = "True"
      oid-owned = "True"
    }
  )
}

# SQS Queue Policy - Allow member account roles to send messages
resource "aws_sqs_queue_policy" "mailer_queue_policy" {
  count     = var.create_notification_queue ? 1 : 0
  queue_url = aws_sqs_queue.custodian_mailer[0].url

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowMemberAccountSendMessage"
        Effect = "Allow"
        Principal = {
          AWS = [
            for account_id in var.member_account_ids :
            "arn:aws:iam::${account_id}:role/CloudCustodianExecutionRole"
          ]
        }
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueUrl",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.custodian_mailer[0].arn
      }
    ]
  })
  depends_on = [aws_sqs_queue.custodian_mailer]
}

# ============================================================================
# SES Email Identity Configuration
# ============================================================================

# SES Email Identity for ysrinu95@gmail.com
resource "aws_ses_email_identity" "mailer" {
  email = var.mailer_from_address
}

# Note: After Terraform applies this, you MUST verify the email address by:
# 1. Check the inbox of ysrinu95@gmail.com
# 2. Click the verification link sent by AWS SES
# 3. Email verification is required before sending emails

# Output the verification status
output "ses_email_verification_status" {
  value       = "Email verification required for ${aws_ses_email_identity.mailer.email}"
  description = "Check the inbox and click the verification link from AWS SES"
}

# SES email identity policy for cross-account access (optional for email identities)
resource "aws_ses_identity_policy" "mailer" {
  identity = aws_ses_email_identity.mailer.arn
  name     = "cross-account-central"
  policy   = data.aws_iam_policy_document.support_cross_account.json
}

# IAM policy document for cross-account SES access
data "aws_iam_policy_document" "support_cross_account" {
  statement {
    actions   = ["SES:SendEmail", "SES:SendRawEmail"]
    resources = [aws_ses_email_identity.mailer.arn]

    principals {
      identifiers = ["arn:aws:iam::172327596604:root", "arn:aws:iam::813185901390:root"]
      type        = "AWS"
    }
  }
}

# Output SES configuration details
output "ses_email_identity_arn" {
  value       = aws_ses_email_identity.mailer.arn
  description = "ARN of the SES email identity"
}


# ============================================================================
# SNS Topic for Formatted Notifications
# ============================================================================

# SNS Topic for mailer notifications (formatted messages)
resource "aws_sns_topic" "custodian_mailer_notifications" {
  name = "custodian-mailer-notifications"

  tags = merge(
    var.tags,
    {
      Name      = "custodian-mailer-notifications"
      terraform = "True"
      oid-owned = "True"
    }
  )
}

# SNS Topic Policy - Allow mailer Lambda to publish messages
resource "aws_sns_topic_policy" "mailer_notifications_policy" {
  arn = aws_sns_topic.custodian_mailer_notifications.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowMailerLambdaPublish"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.custodian_mailer_notifications.arn
        Condition = {
          StringEquals = {
            "aws:SourceArn" = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:cloud-custodian-mailer"
          }
        }
      },
      {
        Sid    = "AllowMemberAccountsSubscribe"
        Effect = "Allow"
        Principal = {
          AWS = [
            for account_id in var.member_account_ids :
            "arn:aws:iam::${account_id}:root"
          ]
        }
        Action = [
          "sns:Subscribe",
          "sns:Receive"
        ]
        Resource = aws_sns_topic.custodian_mailer_notifications.arn
      }
    ]
  })
}

# Email subscription to SNS topic (optional)
resource "aws_sns_topic_subscription" "mailer_email" {
  topic_arn = aws_sns_topic.custodian_mailer_notifications.arn
  protocol  = "email"
  endpoint  = var.mailer_contact_email

  depends_on = [aws_sns_topic.custodian_mailer_notifications]
}

# ============================================================================
# SES Email Verification for Direct HTML Email Delivery
# ============================================================================

# Verify sender email address in SES (required for sending emails)
resource "aws_ses_email_identity" "mailer_sender" {
  count = var.create_mailer_lambda ? 1 : 0
  email = var.mailer_contact_email
}

# Verify recipient email address in SES (required in sandbox mode)
resource "aws_ses_email_identity" "mailer_recipient" {
  count = var.create_mailer_lambda ? 1 : 0
  email = var.mailer_contact_email
}

# ============================================================================
# cloud-custodian-mailer Lambda Resources (Optional)
# ============================================================================

# Build cloud-custodian-mailer Lambda Layer
resource "null_resource" "mailer_layer_build" {
  count = var.create_mailer_lambda && var.mailer_layer_path == "" ? 1 : 0

  triggers = {
    mailer_version = "0.6.20"
    # Hash of requirements to detect actual dependency changes
    requirements_hash = sha256(<<-EOT
      c7n>=0.9.21
      cryptography<43.0.0
      PyJWT>=2.8.0
      jinja2>=3.0.0
      pyyaml>=5.4.0
      boto3>=1.26.0
      botocore>=1.29.0
      requests>=2.28.0
      click>=8.0.0
      tabulate>=0.9.0
      decorator>=4.4.0
      jsonschema==4.17.3
      python-dateutil>=2.8.0
      sendgrid>=6.0.0
      redis>=3.0.0
      ldap3>=2.9.0
    EOT
    )
  }

  provisioner "local-exec" {
    working_dir = path.module
    command = <<-EOT
      set -e
      LAYER_DIR="./mailer-layer"
      WORKING_DIR="$(pwd)"
      echo "📦 Building cloud-custodian-mailer Lambda layer..."
      echo "📁 Layer directory: $LAYER_DIR"
      echo "📂 Working directory: $WORKING_DIR"
      rm -rf "$LAYER_DIR" 2>/dev/null || true
      mkdir -p "$LAYER_DIR/python/lib/python3.11/site-packages"
      echo "✅ Layer directory created"
      
      # Create requirements file for dependencies (NOT including c7n/c7n-mailer)
      cat > "$LAYER_DIR/requirements-mailer.txt" << 'REQS'
c7n>=0.9.21
cryptography<43.0.0
PyJWT>=2.8.0
jinja2>=3.0.0
pyyaml>=5.4.0
boto3>=1.26.0
botocore>=1.29.0
requests>=2.28.0
click>=8.0.0
tabulate>=0.9.0
decorator>=4.4.0
jsonschema==4.17.3
python-dateutil>=2.8.0
sendgrid>=6.0.0
redis>=3.0.0
ldap3>=2.9.0
REQS
      echo "✅ Requirements file created"
      
      # Install dependencies with proper sequencing (matching deploy-mailer.sh approach)
      echo "📥 Installing cloud-custodian-mailer and dependencies..."
      python3 -m pip install --upgrade pip setuptools wheel
      
      # Install pinned dependencies FIRST with upgrade strategy to prevent upgrades
      echo "📥 Installing supporting dependencies with pinned versions..."
      python3 -m pip install -r "$LAYER_DIR/requirements-mailer.txt" -t "$LAYER_DIR/python/lib/python3.11/site-packages/" --no-cache-dir --upgrade-strategy only-if-needed --only-binary=:all:
      if [ $? -ne 0 ]; then
        echo "❌ ERROR: Failed to install dependencies"
        exit 1
      fi
      echo "✅ Supporting dependencies installed with pinned versions"
      
      # Install c7n-mailer LAST without dependencies to avoid overriding pinned versions
      echo "📥 Installing c7n-mailer (without dependencies)..."
      python3 -m pip install 'c7n-mailer>=0.6.20' --no-deps -t "$LAYER_DIR/python/lib/python3.11/site-packages/" --no-cache-dir
      if [ $? -ne 0 ]; then
        echo "❌ ERROR: Failed to install c7n-mailer"
        exit 1
      fi
      echo "✅ c7n-mailer installed (no deps)"
      
      # Verify c7n-mailer was actually installed
      echo "🔍 Checking c7n-mailer installation..."
      if ! ls -la "$LAYER_DIR/python/lib/python3.11/site-packages/" | grep -i mailer; then
        echo "❌ ERROR: c7n-mailer not found in site-packages!"
        echo "All installed packages:"
        ls -la "$LAYER_DIR/python/lib/python3.11/site-packages/" | grep "^d" || echo "No directories found"
        exit 1
      fi
      echo "✅ c7n-mailer directory confirmed"
      
      # Verify c7n packages were installed
      echo "🔍 Verifying c7n packages..."
      if ! ls "$LAYER_DIR/python/lib/python3.11/site-packages/" | grep -q "^c7n"; then
        echo "❌ ERROR: c7n packages not found in site-packages!"
        echo "Installed packages:"
        ls -la "$LAYER_DIR/python/lib/python3.11/site-packages/" | head -30
        exit 1
      fi
      
      # Verify c7n_mailer specifically
      if [ ! -d "$LAYER_DIR/python/lib/python3.11/site-packages/c7n_mailer" ]; then
        echo "❌ ERROR: c7n_mailer module not found!"
        echo "Available c7n packages:"
        ls "$LAYER_DIR/python/lib/python3.11/site-packages/" | grep "^c7n"
        exit 1
      fi
      echo "✅ c7n packages verified"
      
      # Verify critical dependencies via Python import
      echo "🔍 Verifying critical dependencies can be imported..."
      PYTHONPATH="$LAYER_DIR/python/lib/python3.11/site-packages:$PYTHONPATH" python3 -c "import jwt; print('✅ PyJWT imported successfully')" || {
        echo "❌ ERROR: PyJWT import failed"
        exit 1
      }
      PYTHONPATH="$LAYER_DIR/python/lib/python3.11/site-packages:$PYTHONPATH" python3 -c "import cryptography; print('✅ cryptography imported successfully')" || {
        echo "❌ ERROR: cryptography import failed"
        exit 1
      }
      PYTHONPATH="$LAYER_DIR/python/lib/python3.11/site-packages:$PYTHONPATH" python3 -c "import c7n_mailer; print('✅ c7n_mailer imported successfully')" || {
        echo "❌ ERROR: c7n_mailer import failed"
        echo "Detailed debug info:"
        echo "PYTHONPATH: $LAYER_DIR/python/lib/python3.11/site-packages"
        echo "Contents of site-packages:"
        ls -la "$LAYER_DIR/python/lib/python3.11/site-packages/" | head -40
        echo "Attempting direct import with traceback:"
        PYTHONPATH="$LAYER_DIR/python/lib/python3.11/site-packages:$PYTHONPATH" python3 -c "import traceback; 
try:
    import c7n_mailer
except ImportError as e:
    traceback.print_exc()
    print(f'Error: {e}')
"
        exit 1
      }
      echo "✅ All critical dependencies verified"
      
      # Verify directory exists before optimization
      if [ ! -d "$LAYER_DIR/python/lib/python3.11/site-packages/" ]; then
        echo "❌ ERROR: Site-packages directory does not exist!"
        ls -la "$LAYER_DIR/python/lib/python3.11/" || echo "python3.11 directory missing"
        exit 1
      fi
      
      # Optimize layer size
      echo "🗜️ Optimizing layer size..."
      cd "$LAYER_DIR/python/lib/python3.11/site-packages/"
      find . -type d -name "tests" -exec rm -rf {} + 2>/dev/null || true
      find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
      find . -name "*.pyc" -delete 2>/dev/null || true
      find . -name "*.dist-info" -exec rm -rf {} + 2>/dev/null || true
      find . -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true
      rm -rf boto3* botocore* 2>/dev/null || true
      
      # Remove cryptography Rust bindings that require newer GLIBC (Lambda has older glibc)
      # Lambda's runtime already has cryptography, so we just need the pure Python fallbacks
      echo "🗑️ Removing cryptography Rust bindings incompatible with Lambda runtime..."
      find cryptography -name "_rust*.so" -delete 2>/dev/null || true
      find cryptography -name "_rust*.pyd" -delete 2>/dev/null || true
      rm -rf cryptography/hazmat/bindings/_rust* 2>/dev/null || true
      echo "✅ Cryptography Rust bindings removed"
      
      echo "✅ Layer optimized"
      
      # Verify c7n packages still exist after cleanup
      echo "🔍 Verifying c7n packages after optimization..."
      if [ ! -d "c7n_mailer" ]; then
        echo "❌ ERROR: c7n_mailer removed during optimization!"
        exit 1
      fi
      echo "✅ c7n packages preserved after optimization"
      
      # Return to working directory and create zip file with correct structure
      cd "$WORKING_DIR"
      echo "📂 Current working directory: $(pwd)"
      echo "📂 LAYER_DIR path: $LAYER_DIR"
      
      # Verify layer directory exists before zipping
      if [ ! -d "$LAYER_DIR/python" ]; then
        echo "❌ ERROR: Layer python directory not found at $LAYER_DIR/python"
        ls -la "$LAYER_DIR/" || true
        exit 1
      fi
      
      echo "🗜️ Creating ZIP file with correct Lambda layer structure..."
      # IMPORTANT: Lambda layers must have python/ at the root of the ZIP, not mailer-layer/python/
      cd "$LAYER_DIR" && zip -r "$WORKING_DIR/mailer-layer.zip" python/ -q
      cd "$WORKING_DIR"
      
      # Verify ZIP was created
      if [ ! -f "mailer-layer.zip" ]; then
        echo "❌ ERROR: ZIP file was not created!"
        ls -la . | grep -i zip || echo "No ZIP files found"
        exit 1
      fi
      echo "✅ ZIP file created"
      
      # Check layer size
      if command -v stat &> /dev/null; then
        SIZE_BYTES=$(stat -f%z "mailer-layer.zip" 2>/dev/null || stat -c%s "mailer-layer.zip")
        SIZE_MB=$((SIZE_BYTES / 1024 / 1024))
        echo "📏 Layer size: $${SIZE_MB}MB"
        
        if [ $SIZE_MB -gt 250 ]; then
          echo "❌ ERROR: Layer size exceeds 250MB limit!"
          exit 1
        elif [ $SIZE_MB -gt 200 ]; then
          echo "⚠️  WARNING: Layer size approaching 250MB limit ($${SIZE_MB}MB)"
        else
          echo "✅ Layer size is optimal: $${SIZE_MB}MB"
        fi
      fi
      
      # Clean up build artifacts
      rm -rf "$LAYER_DIR"
      echo "✅ Cleanup complete"
      
      echo "✅ Mailer layer build complete: mailer-layer.zip"
    EOT
  }
}

# cloud-custodian-mailer Lambda Layer (built by Terraform)
resource "aws_lambda_layer_version" "mailer_layer" {
  count = var.create_mailer_lambda && var.mailer_layer_path == "" ? 1 : 0

  filename                = "${path.module}/mailer-layer.zip"
  layer_name              = "cloud-custodian-mailer-layer"
  compatible_runtimes     = ["python3.11"]
  skip_destroy            = false
  
  description = "Cloud Custodian Mailer dependencies (cloud-custodian-mailer) - built by Terraform"

  # Simple hash that triggers on build changes
  source_code_hash = fileexists("${path.module}/mailer-layer.zip") ? filebase64sha256("${path.module}/mailer-layer.zip") : null

  depends_on = [null_resource.mailer_layer_build]

  lifecycle {
    create_before_destroy = true
    ignore_changes = [source_code_hash]
  }
}

# cloud-custodian-mailer Lambda Layer (external/pre-built)
resource "aws_lambda_layer_version" "mailer_layer_external" {
  count               = var.create_mailer_lambda && var.mailer_layer_path != "" ? 1 : 0
  filename            = var.mailer_layer_path
  layer_name          = "cloud-custodian-mailer-layer"
  compatible_runtimes = ["python3.11"]
  description         = "Cloud Custodian Mailer dependencies (cloud-custodian-mailer) - external"
  source_code_hash    = fileexists(var.mailer_layer_path) ? filebase64sha256(var.mailer_layer_path) : base64sha256(var.mailer_layer_path)
}

# Build cloud-custodian-mailer Lambda Function
resource "null_resource" "mailer_function_build" {
  count = var.create_mailer_lambda ? 1 : 0

  # No triggers needed - handler is generated inline, config is from environment variables
  # Function will rebuild only when provisioner command changes or resource is tainted

  provisioner "local-exec" {
    working_dir = path.module
    command = <<-EOT
      set -e
      echo "📦 Building cloud-custodian-mailer Lambda with native c7n-mailer..."
      
      # Create build directory
      LAMBDA_DIR="./mailer-build"
      rm -rf $LAMBDA_DIR 2>/dev/null || true
      mkdir -p $LAMBDA_DIR
      
      # Create native c7n-mailer handler (matches c7n-mailer --update-lambda output)
      cat > $LAMBDA_DIR/lambda_function.py << 'HANDLER'
import logging
import json
import os
import sys
import boto3

# Ensure Lambda layer packages are in path
layer_path = '/opt/python/lib/python3.11/site-packages'
if layer_path not in sys.path:
    sys.path.insert(0, layer_path)

# Also add /opt/python to path
if '/opt/python' not in sys.path:
    sys.path.insert(0, '/opt/python')

# Try importing c7n_mailer with better error handling
try:
    from c7n_mailer import handle
except ImportError as e:
    print(f"ERROR: Failed to import c7n_mailer: {e}")
    print(f"Python path: {sys.path}")
    print(f"Available packages in layer:")
    if os.path.exists(layer_path):
        print(os.listdir(layer_path))
    raise

logger = logging.getLogger('custodian.mailer')

# Get log level from environment variable (DEBUG, INFO, WARNING, ERROR)
log_level = os.environ.get('LOG_LEVEL', 'INFO').upper()
logger.setLevel(getattr(logging, log_level, logging.INFO))

# Initialize boto3 S3 client for template loading
s3_client = boto3.client('s3', region_name=os.environ.get('REGION', 'us-east-1'))

log_format = '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
logging.basicConfig(level=getattr(logging, log_level, logging.INFO), format=log_format)
logging.getLogger('botocore').setLevel(logging.WARNING)

def handler(event, context):
    """
    Cloud Custodian Mailer Lambda Handler
    Uses native c7n-mailer for periodic policy notifications
    Generates config.json dynamically from environment variables
    """
    logger.info("=" * 80)
    logger.info("Cloud Custodian Mailer (Native) Starting")
    logger.info(f"Log Level: {log_level}")
    logger.info("=" * 80)
    
    try:
        # Log incoming event for debugging
        logger.info(f"Lambda invoked with event: {json.dumps(event, default=str)}")
        
        # Determine if debug mode is enabled
        is_debug = log_level == 'DEBUG'
        
        # Generate config.json dynamically from environment variables
        config = {
            "queue_url": os.environ.get('QUEUE_URL'),
            "role": os.environ.get('ROLE_ARN'),
            "region": os.environ.get('REGION', 'us-east-1'),
            "contact_tags": ["contact", "owner"],
            "from_address": os.environ.get('FROM_ADDRESS'),
            "ses_region": os.environ.get('REGION', 'us-east-1'),
            "templates_folders": [f"s3://{os.environ.get('TEMPLATES_BUCKET')}/templates"],
            "debug": is_debug  # Enable c7n-mailer debug logging
        }
        
        # Write config to /tmp/config.json (Lambda writeable directory)
        config_path = '/tmp/config.json'
        with open(config_path, 'w') as f:
            json.dump(config, f, indent=2)
        
        logger.info(f"Generated config.json at {config_path}")
        logger.info(f"Queue URL: {config['queue_url']}")
        logger.info(f"Region: {config['region']}")
        logger.info(f"Debug Mode: {is_debug}")
        
        if is_debug:
            logger.debug(f"Full config: {json.dumps(config, indent=2)}")
        
        # Download S3 templates to local /tmp directory
        # c7n-mailer uses Jinja2 FileSystemLoader which requires local filesystem
        bucket = os.environ.get('TEMPLATES_BUCKET')
        local_templates_dir = '/tmp/mailer-templates'
        
        try:
            import shutil
            
            # Clean and recreate templates directory
            if os.path.exists(local_templates_dir):
                shutil.rmtree(local_templates_dir)
            os.makedirs(local_templates_dir, exist_ok=True)
            
            logger.info(f"Downloading templates from s3://{bucket}/templates/ to {local_templates_dir}")
            
            # List and download all templates from S3
            response = s3_client.list_objects_v2(Bucket=bucket, Prefix='templates/')
            if 'Contents' in response:
                for obj in response['Contents']:
                    key = obj['Key']
                    if key.endswith('/'):  # Skip directory markers
                        continue
                    
                    # Get filename without 'templates/' prefix
                    filename = key.replace('templates/', '')
                    local_path = os.path.join(local_templates_dir, filename)
                    
                    logger.info(f"Downloading {key} to {local_path}")
                    s3_client.download_file(bucket, key, local_path)
                
                downloaded = len([f for f in os.listdir(local_templates_dir) if os.path.isfile(os.path.join(local_templates_dir, f))])
                logger.info(f"Successfully downloaded {downloaded} templates to {local_templates_dir}")
                logger.info(f"Template files: {os.listdir(local_templates_dir)}")
            else:
                logger.warning(f"No templates found in s3://{bucket}/templates/")
                
        except Exception as e:
            logger.error(f"Failed to download S3 templates: {e}", exc_info=True)
            raise
        
        # Update config to use local templates directory
        config['templates_folders'] = [local_templates_dir]
        logger.info(f"Updated config to use local templates: {config['templates_folders']}")
        
        # Call c7n-mailer's start function with config dict
        result = handle.start_c7n_mailer(logger, config=config, parallel=False)
        
        logger.info("=" * 80)
        logger.info("Cloud Custodian Mailer completed successfully")
        logger.info("=" * 80)
        
        return {
            'statusCode': 200,
            'body': 'Mailer processed successfully'
        }
        
    except Exception as e:
        logger.error("=" * 80)
        logger.error("Cloud Custodian Mailer handler failed: %s", str(e))
        logger.error("=" * 80)
        logger.error("Full traceback:", exc_info=True)
        
        return {
            'statusCode': 500,
            'body': 'Error: {}'.format(str(e))
        }
HANDLER
      
      # Templates will be loaded from S3 - no need to package them in Lambda
      echo "📧 Templates will be loaded from S3: s3://${var.policy_bucket}/templates/"
      
      # No static config.json needed - generated dynamically at runtime from env vars
      
      # Create zip file
      cd "$LAMBDA_DIR"
      zip -r "../mailer-function.zip" . -q
      cd ..
      
      # Cleanup
      rm -rf "$LAMBDA_DIR"
      
      echo "✅ Native c7n-mailer Lambda build complete"
    EOT
    
    environment = {
      QUEUE_URL         = aws_sqs_queue.periodic_notifications.url
      ROLE_ARN          = var.create_mailer_lambda ? aws_iam_role.mailer_execution[0].arn : ""
      REGION            = var.aws_region
      SNS_TOPIC_ARN     = aws_sns_topic.custodian_mailer_notifications.arn
      FROM_ADDRESS      = var.mailer_from_address
      TEMPLATES_BUCKET  = var.policy_bucket
    }
  }
}

# IAM Role for Mailer Lambda
resource "aws_iam_role" "mailer_execution" {
  count = var.create_mailer_lambda ? 1 : 0
  name  = "cloud-custodian-mailer-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = merge(
    var.tags,
    {
      Name      = "cloud-custodian-mailer-execution-role"
      terraform = "True"
      oid-owned = "True"
    }
  )
}

# IAM Policy for Mailer Lambda
resource "aws_iam_role_policy" "mailer_policy" {
  count = var.create_mailer_lambda ? 1 : 0
  name  = "cloud-custodian-mailer-policy"
  role  = aws_iam_role.mailer_execution[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SQSAccess"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility"
        ]
        Resource = [aws_sqs_queue.periodic_notifications.arn]
      },
      {
        Sid    = "SNSPublish"
        Effect = "Allow"
        Action = [
          "sns:Publish",
          "sns:GetTopicAttributes"
        ]
        Resource = aws_sns_topic.custodian_mailer_notifications.arn
      },
      {
        Sid    = "S3TemplatesRead"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.policy_bucket}",
          "arn:aws:s3:::${var.policy_bucket}/templates/*"
        ]
      },
      {
        Sid    = "SESEmailSend"
        Effect = "Allow"
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ]
        Resource = [
          "arn:aws:ses:${var.aws_region}:${data.aws_caller_identity.current.account_id}:identity/*"
        ]
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/*"
      }
    ]
  })
}
# cloud-custodian-mailer Lambda Function
resource "aws_lambda_function" "mailer" {
  count = var.create_mailer_lambda ? 1 : 0

  filename         = "${path.module}/mailer-function.zip"
  function_name    = "cloud-custodian-mailer"
  role             = aws_iam_role.mailer_execution[0].arn
  handler          = "lambda_function.handler"
  runtime          = "python3.11"
  timeout          = var.mailer_lambda_timeout
  memory_size      = 256
  source_code_hash = base64sha256(
    "${null_resource.mailer_function_build[0].id}:${fileexists("${path.module}/mailer-function.zip") ? filebase64sha256("${path.module}/mailer-function.zip") : "building"}"
  )

  # Code signing configuration for security compliance
  code_signing_config_arn = var.code_signing_config_arn != "" ? var.code_signing_config_arn : aws_lambda_code_signing_config.lambda_config.arn

  # Attach mailer layer - use built or external layer
  # Reference layer version ARN so Lambda updates when layer version changes
  layers = [
    var.mailer_layer_path != "" ? aws_lambda_layer_version.mailer_layer_external[0].arn : aws_lambda_layer_version.mailer_layer[0].arn
  ]

  environment {
    variables = {
      QUEUE_URL         = aws_sqs_queue.periodic_notifications.url
      FROM_ADDRESS      = var.mailer_from_address
      SNS_TOPIC_ARN     = aws_sns_topic.custodian_mailer_notifications.arn
      TEMPLATES_BUCKET  = var.policy_bucket
      REGION            = var.aws_region
      ROLE_ARN          = aws_iam_role.mailer_execution[0].arn
      DRYRUN            = "false"
      LOG_LEVEL         = "DEBUG"  # Increased for troubleshooting config generation
    }
  }

  depends_on = [
    null_resource.mailer_function_build,
    aws_iam_role_policy.mailer_policy,
    aws_lambda_layer_version.mailer_layer
  ]

  tags = merge(
    var.tags,
    {
      Name             = "cloud-custodian-mailer"
      application      = "cloud-custodian"
      component        = "mailer"
      repo             = "aikyam-everything-as-code"
      terraform        = "True"
      oid-owned        = "True"
      aide-id          = "UHGWM110-019726"
      service-tier     = "p1"
      contact          = var.mailer_contact_email
      environment      = var.environment
      managed-by       = "terraform"
      OptumGovernance  = "Optum"
      costcenter       = "platform"
      owner            = "platform-team"
    }
  )
}

# EventBridge Scheduled Rule for Mailer Lambda (polls SQS queue every 5 minutes)
# This is the standard c7n-mailer approach - scheduled polling instead of event-driven
resource "aws_cloudwatch_event_rule" "mailer_schedule" {
  count               = var.create_mailer_lambda ? 1 : 0
  name                = "cloud-custodian-mailer-schedule"
  description         = "Trigger c7n-mailer Lambda every 5 minutes to process SQS queue"
  schedule_expression = "rate(5 minutes)"

  tags = merge(
    var.tags,
    {
      Name      = "cloud-custodian-mailer-schedule"
      terraform = "True"
      oid-owned = "True"
    }
  )
}

# EventBridge Target for Mailer Lambda
resource "aws_cloudwatch_event_target" "mailer_schedule" {
  count = var.create_mailer_lambda ? 1 : 0
  rule  = aws_cloudwatch_event_rule.mailer_schedule[0].name
  arn   = aws_lambda_function.mailer[0].arn
}

# Lambda Permission for EventBridge to invoke Mailer
resource "aws_lambda_permission" "allow_eventbridge_mailer" {
  count         = var.create_mailer_lambda ? 1 : 0
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.mailer[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.mailer_schedule[0].arn
}

# CloudWatch Log Group for Mailer
resource "aws_cloudwatch_log_group" "mailer_logs" {
  count             = var.create_mailer_lambda ? 1 : 0
  name              = "/aws/lambda/cloud-custodian-mailer"
  retention_in_days = var.log_retention_days

  tags = merge(
    var.tags,
    {
      Name      = "cloud-custodian-mailer-logs"
      terraform = "True"
      oid-owned = "True"
    }
  )
}

# ============================================================================
# Outputs
# ============================================================================

output "event_bus_arn" {
  description = "ARN of the centralized EventBridge custom bus"
  value       = aws_cloudwatch_event_bus.centralized.arn
}

output "event_bus_name" {
  description = "Name of the centralized EventBridge custom bus"
  value       = aws_cloudwatch_event_bus.centralized.name
}

output "lambda_function_arn" {
  description = "ARN of the Cloud Custodian executor Lambda function"
  value       = aws_lambda_function.custodian_cross_account_executor.arn
}

output "lambda_function_name" {
  description = "Name of the Cloud Custodian executor Lambda function"
  value       = aws_lambda_function.custodian_cross_account_executor.function_name
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution.arn
}

output "lambda_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "lambda_layer_arn" {
  description = "ARN of the Cloud Custodian Lambda layer (if created)"
  value       = var.lambda_layer_path != "" ? (length(aws_lambda_layer_version.custodian_layer_external) > 0 ? aws_lambda_layer_version.custodian_layer_external[0].arn : "N/A") : (length(aws_lambda_layer_version.custodian_layer) > 0 ? aws_lambda_layer_version.custodian_layer[0].arn : "N/A")
}

output "lambda_layer_version" {
  description = "Version of the Cloud Custodian Lambda layer (if created)"
  value       = var.lambda_layer_path != "" ? (length(aws_lambda_layer_version.custodian_layer_external) > 0 ? aws_lambda_layer_version.custodian_layer_external[0].version : "N/A") : (length(aws_lambda_layer_version.custodian_layer) > 0 ? aws_lambda_layer_version.custodian_layer[0].version : "N/A")
}

output "policy_bucket_name" {
  description = "Name of the S3 bucket for policies"
  value       = var.policy_bucket
}

output "policy_bucket_arn" {
  description = "ARN of the S3 bucket for policies (if created)"
  value       = var.create_policy_bucket ? aws_s3_bucket.policies[0].arn : "N/A - Bucket not created by this module"
}

output "realtime_queue_url" {
  description = "URL of the real-time SQS notification queue (for event-driven policies)"
  value       = aws_sqs_queue.realtime_notifications.url
}

output "realtime_queue_arn" {
  description = "ARN of the real-time SQS notification queue (for event-driven policies)"
  value       = aws_sqs_queue.realtime_notifications.arn
}

output "periodic_queue_url" {
  description = "URL of the periodic SQS notification queue (for scheduled policies with email templates)"
  value       = aws_sqs_queue.periodic_notifications.url
}

output "periodic_queue_arn" {
  description = "ARN of the periodic SQS notification queue (for scheduled policies with email templates)"
  value       = aws_sqs_queue.periodic_notifications.arn
}

output "mailer_sns_topic_arn" {
  description = "ARN of the SNS topic for formatted mailer notifications"
  value       = aws_sns_topic.custodian_mailer_notifications.arn
}

output "mailer_sns_topic_name" {
  description = "Name of the SNS topic for formatted mailer notifications"
  value       = aws_sns_topic.custodian_mailer_notifications.name
}

output "member_account_ids" {
  description = "List of member account IDs configured"
  value       = var.member_account_ids
}

output "mailer_lambda_arn" {
  description = "ARN of the cloud-custodian-mailer Lambda function (if created)"
  value       = var.create_mailer_lambda ? aws_lambda_function.mailer[0].arn : "N/A - Mailer Lambda not created"
}

output "mailer_lambda_name" {
  description = "Name of the cloud-custodian-mailer Lambda function (if created)"
  value       = var.create_mailer_lambda ? aws_lambda_function.mailer[0].function_name : "N/A - Mailer Lambda not created"
}

output "mailer_role_arn" {
  description = "ARN of the cloud-custodian-mailer execution role (if created)"
  value       = var.create_mailer_lambda ? aws_iam_role.mailer_execution[0].arn : "N/A - Mailer role not created"
}
