terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# EventBridge Custom Bus for receiving cross-account events
resource "aws_cloudwatch_event_bus" "centralized" {
  name = "centralized-security-events"

  tags = {
    Name        = "Centralized Security Events"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
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

# EventBridge Rule on custom bus - Trigger Lambda for all cross-account events
resource "aws_cloudwatch_event_rule" "custodian_cross_account_trigger" {
  name           = "cloud-custodian-cross-account-trigger-${var.environment}"
  description    = "Trigger Cloud Custodian Lambda for cross-account security events"
  event_bus_name = aws_cloudwatch_event_bus.centralized.name

  event_pattern = jsonencode({
    source = [
      "aws.cloudtrail",
      "aws.securityhub",
      "aws.guardduty",
      "aws.config"
    ]
    account = var.member_account_ids
  })

  tags = {
    Name        = "Cloud Custodian Cross-Account Trigger"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# EventBridge Target - Lambda function
resource "aws_cloudwatch_event_target" "lambda" {
  rule           = aws_cloudwatch_event_rule.custodian_cross_account_trigger.name
  event_bus_name = aws_cloudwatch_event_bus.centralized.name
  arn            = aws_lambda_function.custodian_cross_account_executor.arn
}

# Lambda Permission - Allow EventBridge to invoke
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.custodian_cross_account_executor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.custodian_cross_account_trigger.arn
}

# Lambda Layer - Cloud Custodian dependencies
resource "aws_lambda_layer_version" "custodian_layer" {
  count               = var.lambda_layer_path != "" ? 1 : 0
  filename            = var.lambda_layer_path
  layer_name          = "cloud-custodian-layer-${var.environment}"
  compatible_runtimes = ["python3.11"]
  source_code_hash    = filebase64sha256(var.lambda_layer_path)

  description = "Cloud Custodian ${var.custodian_version} and dependencies"

  lifecycle {
    create_before_destroy = true
  }
}

# Lambda Function - Cross-account Cloud Custodian executor
resource "aws_lambda_function" "custodian_cross_account_executor" {
  filename         = var.lambda_package_path
  function_name    = "cloud-custodian-cross-account-executor-${var.environment}"
  role             = aws_iam_role.lambda_execution.arn
  handler          = "lambda_function.handler"
  runtime          = "python3.11"
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size
  source_code_hash = filebase64sha256(var.lambda_package_path)

  # Attach Cloud Custodian layer if provided
  layers = var.lambda_layer_path != "" ? [aws_lambda_layer_version.custodian_layer[0].arn] : []

  environment {
    variables = {
      POLICY_BUCKET            = var.policy_bucket
      ACCOUNT_MAPPING_KEY      = "config/account-policy-mapping.json"
      CROSS_ACCOUNT_ROLE_NAME  = "CloudCustodianExecutionRole"
      EXTERNAL_ID_PREFIX       = "cloud-custodian"
      LOG_LEVEL                = var.log_level
    }
  }

  tags = {
    Name        = "Cloud Custodian Cross-Account Executor"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.custodian_cross_account_executor.function_name}"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "Cloud Custodian Cross-Account Executor Logs"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# IAM Role for Lambda Execution
resource "aws_iam_role" "lambda_execution" {
  name = "cloud-custodian-cross-account-executor-role-${var.environment}"

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

  tags = {
    Name        = "Cloud Custodian Cross-Account Executor Role"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
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
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/*"
      },
      {
        Sid    = "SQSNotifications"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueUrl"
        ]
        Resource = var.notification_queue_arn != "" ? var.notification_queue_arn : "*"
      }
    ]
  })
}

# Data source to get current AWS account ID
data "aws_caller_identity" "current" {}

# S3 Bucket for Policies (optional - create only if specified)
resource "aws_s3_bucket" "policies" {
  count  = var.create_policy_bucket ? 1 : 0
  bucket = var.policy_bucket

  tags = {
    Name        = "Cloud Custodian Policies"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
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

# SQS Queue for Notifications (optional)
resource "aws_sqs_queue" "notifications" {
  count                     = var.create_notification_queue ? 1 : 0
  name                      = "cloud-custodian-notifications-${var.environment}"
  visibility_timeout_seconds = 300
  message_retention_seconds = 1209600  # 14 days

  tags = {
    Name        = "Cloud Custodian Notifications"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# SQS Dead Letter Queue
resource "aws_sqs_queue" "notifications_dlq" {
  count                     = var.create_notification_queue ? 1 : 0
  name                      = "cloud-custodian-notifications-dlq-${var.environment}"
  message_retention_seconds = 1209600  # 14 days

  tags = {
    Name        = "Cloud Custodian Notifications DLQ"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
