# ========================================
# Cloud Custodian Single Lambda - Combined Terraform Configuration
# ========================================
# This file combines all Terraform resources for Cloud Custodian event-driven architecture
# Created: November 11, 2025

# ========================================
# Terraform Configuration & Provider
# ========================================

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
    key     = "cloud-custodian-lambda/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "CloudCustodian"
      ManagedBy   = "Terraform"
      Environment = var.environment
    }
  }
}

# ========================================
# Data Sources
# ========================================

data "aws_caller_identity" "current" {}

# ========================================
# Variables
# ========================================

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "cloud-custodian"
}

variable "lambda_execution_mode" {
  description = "Lambda execution mode: 'native' (library) or 'cli' (subprocess)"
  type        = string
  default     = "native"
  
  validation {
    condition     = contains(["native", "cli"], var.lambda_execution_mode)
    error_message = "Lambda execution mode must be either 'native' or 'cli'"
  }
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 300
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 512
}

variable "policy_bucket" {
  description = "S3 bucket containing Cloud Custodian policy files and policy mapping configuration"
  type        = string
  default     = ""
}

variable "policy_mapping_key" {
  description = "S3 key for policy mapping JSON file"
  type        = string
  default     = "config/policy-mapping.json"
}

variable "policy_path" {
  description = "Path to policy file in Lambda package"
  type        = string
  default     = "/var/task/policies/sample-policies.yml"
}

variable "custodian_layer_arn" {
  description = "ARN of the Cloud Custodian Lambda layer (will be created if not provided)"
  type        = string
  default     = ""
}

variable "enable_eventbridge_rule" {
  description = "Enable EventBridge rule for S3 CloudTrail events"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention period in days"
  type        = number
  default     = 7
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}

# ========================================
# IAM Role and Policies
# ========================================

# IAM Role for Lambda Function

resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-lambda-role-${var.environment}"
    }
  )
}

# Basic Lambda Execution Policy

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Cloud Custodian Permissions Policy

resource "aws_iam_policy" "custodian_policy" {
  name        = "${var.project_name}-custodian-policy-${var.environment}"
  description = "IAM policy for Cloud Custodian Lambda function"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Read-only access for resource discovery
      {
        Sid    = "CloudCustodianReadAccess"
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "rds:Describe*",
          "s3:ListAllMyBuckets",
          "s3:GetBucketLocation",
          "s3:GetBucketTagging",
          "s3:GetBucketEncryption",
          "s3:GetBucketVersioning",
          "s3:GetBucketPublicAccessBlock",
          "lambda:ListFunctions",
          "lambda:GetFunction",
          "lambda:ListVersionsByFunction",
          "iam:ListRoles",
          "iam:ListUsers",
          "iam:GetRole",
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "tag:GetResources",
          "tag:GetTagKeys",
          "tag:GetTagValues"
        ]
        Resource = "*"
      },
      # Write permissions for actions (modify as needed)
      {
        Sid    = "CloudCustodianActions"
        Effect = "Allow"
        Action = [
          "ec2:CreateTags",
          "ec2:DeleteTags",
          "ec2:StopInstances",
          "ec2:TerminateInstances",
          "ec2:CreateSnapshot",
          "ec2:DeleteVolume",
          "s3:PutBucketEncryption",
          "s3:PutBucketTagging",
          "s3:PutBucketPublicAccessBlock",
          "s3:PutBucketAcl",
          "s3:PutBucketPolicy",
          "s3:DeleteBucketPolicy",
          "s3:PutBucketCORS",
          "s3:PutBucketWebsite",
          "s3:DeleteBucketWebsite",
          "lambda:DeleteFunction",
          "lambda:PublishVersion",
          "sns:Publish",
          "ses:SendEmail"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.aws_region
          }
        }
      },
      # S3 access for policy files (if using S3)
      {
        Sid    = "S3PolicyAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = var.policy_bucket != "" ? [
          "arn:aws:s3:::${var.policy_bucket}",
          "arn:aws:s3:::${var.policy_bucket}/*"
        ] : ["arn:aws:s3:::placeholder"]
      },
      # CloudWatch Logs for Custodian output
      {
        Sid    = "CloudWatchLogsAccess"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          aws_cloudwatch_log_group.lambda_logs.arn,
          "${aws_cloudwatch_log_group.lambda_logs.arn}:*"
        ]
      },
      # CloudWatch Logs for Cloud Custodian policy execution
      {
        Sid    = "CloudCustodianLogsAccess"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      },
      # IAM permissions for Cloud Custodian notifications
      {
        Sid    = "CloudCustodianIAMAccess"
        Effect = "Allow"
        Action = [
          "iam:ListAccountAliases"
        ]
        Resource = "*"
      },
      # SQS permissions for Cloud Custodian notifications
      {
        Sid    = "CloudCustodianSQSAccess"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueUrl"
        ]
        Resource = "arn:aws:sqs:*:${data.aws_caller_identity.current.account_id}:custodian-mailer-queue*"
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-custodian-policy-${var.environment}"
    }
  )
}

resource "aws_iam_role_policy_attachment" "lambda_custodian_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.custodian_policy.arn
}

# ========================================
# CloudWatch Log Group
# ========================================

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.project_name}-executor-${var.environment}"
  retention_in_days = var.log_retention_days

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-logs-${var.environment}"
    }
  )
}

# ========================================
# Lambda Layer and Function
# ========================================

# Lambda Layer for Cloud Custodian

resource "aws_lambda_layer_version" "custodian_layer" {
  count = var.custodian_layer_arn == "" ? 1 : 0

  filename            = "${path.module}/../layers/cloud-custodian-layer.zip"
  layer_name          = "${var.project_name}-layer-${var.environment}"
  compatible_runtimes = ["python3.11", "python3.12"]
  description         = "Cloud Custodian and dependencies"

  # This will be created by the build script or GitHub Actions
  source_code_hash = fileexists("${path.module}/../layers/cloud-custodian-layer.zip") ? filebase64sha256("${path.module}/../layers/cloud-custodian-layer.zip") : null

  lifecycle {
    create_before_destroy = true
  }
}

# Lambda Function

resource "aws_lambda_function" "custodian" {
  filename         = "${path.module}/lambda-function.zip"
  function_name    = "${var.project_name}-executor-${var.environment}"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = filebase64sha256("${path.module}/lambda-function.zip")
  runtime          = "python3.11"
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size

  layers = [
    var.custodian_layer_arn != "" ? var.custodian_layer_arn : aws_lambda_layer_version.custodian_layer[0].arn
  ]

  environment {
    variables = {
      POLICY_MAPPING_BUCKET = var.policy_bucket
      POLICY_MAPPING_KEY    = var.policy_mapping_key
      LOG_GROUP             = aws_cloudwatch_log_group.lambda_logs.name
      ENVIRONMENT           = var.environment
      DRYRUN                = "false"
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda_logs,
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_custodian_policy
  ]

  tags = merge(
    var.tags,
    {
      Name          = "${var.project_name}-executor-${var.environment}"
      ExecutionMode = var.lambda_execution_mode
    }
  )
}

# ========================================
# EventBridge Rules
# ========================================

# EventBridge Rule for Multi-Resource CloudTrail events
# Captures S3, EC2, and IAM API calls for Cloud Custodian policy execution

resource "aws_cloudwatch_event_rule" "custodian_multi_resource_events" {
  count = var.enable_eventbridge_rule ? 1 : 0

  name        = "${var.project_name}-multi-resource-events-${var.environment}"
  description = "Trigger Cloud Custodian Lambda on S3, EC2, and IAM CloudTrail events"

  event_pattern = jsonencode({
    source      = ["aws.s3", "aws.ec2", "aws.iam"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["s3.amazonaws.com", "ec2.amazonaws.com", "iam.amazonaws.com"]
      eventName = [
        # S3 Events
        "CreateBucket",
        "PutBucketAcl",
        "PutBucketPolicy",
        "PutBucketPublicAccessBlock",
        "DeleteBucketPublicAccessBlock",
        "PutBucketCors",
        "PutBucketWebsite",
        "DeleteBucketEncryption",
        "PutBucketLogging",
        
        # EC2 Events
        "RunInstances",
        "StartInstances",
        "StopInstances",
        "TerminateInstances",
        "CreateSecurityGroup",
        "AuthorizeSecurityGroupIngress",
        "AuthorizeSecurityGroupEgress",
        "RevokeSecurityGroupIngress",
        "CreateVolume",
        "AttachVolume",
        "ModifyInstanceAttribute",
        
        # IAM Events
        "CreateUser",
        "CreateRole",
        "CreateAccessKey",
        "CreatePolicy",
        "AttachUserPolicy",
        "AttachRolePolicy",
        "PutUserPolicy",
        "PutRolePolicy",
        "DeleteUserPolicy",
        "DeleteRolePolicy",
        "UpdateAccessKey",
        "CreateLoginProfile"
      ]
    }
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-multi-resource-events-${var.environment}"
    }
  )
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  count = var.enable_eventbridge_rule ? 1 : 0

  rule      = aws_cloudwatch_event_rule.custodian_multi_resource_events[0].name
  target_id = "CloudCustodianLambda"
  arn       = aws_lambda_function.custodian.arn

  # Lambda will receive the full EventBridge event
  # The validator module will extract event details and determine which policy to execute
}

# Lambda permission for EventBridge to invoke function

resource "aws_lambda_permission" "allow_eventbridge" {
  count = var.enable_eventbridge_rule ? 1 : 0

  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.custodian.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.custodian_multi_resource_events[0].arn
}

# ========================================
# Outputs
# ========================================

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.custodian.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.custodian.arn
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

output "lambda_layer_arn" {
  description = "ARN of the Cloud Custodian Lambda layer"
  value       = var.custodian_layer_arn != "" ? var.custodian_layer_arn : aws_lambda_layer_version.custodian_layer[0].arn
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule"
  value       = var.enable_eventbridge_rule ? aws_cloudwatch_event_rule.custodian_multi_resource_events[0].name : null
}

output "log_group_name" {
  description = "Name of the CloudWatch Log Group"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "execution_mode" {
  description = "Lambda execution mode (native or cli)"
  value       = var.lambda_execution_mode
}
