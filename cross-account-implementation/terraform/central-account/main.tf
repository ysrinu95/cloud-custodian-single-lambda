terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket  = "ysr95-cloud-custodian-tf-bkt"
    key     = "cross-account-implementation/central-account/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
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

# EventBridge Rule on default bus - Trigger Lambda for local central account events
resource "aws_cloudwatch_event_rule" "custodian_local_trigger" {
  name        = "cloud-custodian-local-trigger-${var.environment}"
  description = "Trigger Cloud Custodian Lambda for security events in central account (172327596604)"

  event_pattern = jsonencode({
    account     = [data.aws_caller_identity.current.account_id]
    source      = ["aws.ec2", "aws.s3", "aws.elasticloadbalancing", "aws.rds", "aws.iam", "aws.elasticfilesystem"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = [
        # EC2 events
        "RunInstances",
        # S3 events
        "CreateBucket",
        "PutBucketPolicy",
        "PutBucketAcl",
        "PutBucketPublicAccessBlock",
        "DeleteBucketPublicAccessBlock",
        "PutBucketEncryption",
        "DeleteBucketEncryption",
        # ALB events
        "CreateLoadBalancer",
        "CreateListener",
        "ModifyListener",
        "ModifyLoadBalancerAttributes",
        # RDS events
        "CreateDBInstance",
        "ModifyDBInstance",
        "CreateDBCluster",
        "ModifyDBCluster",
        # IAM events
        "CreateUser",
        "CreateAccessKey",
        "AttachUserPolicy",
        "PutUserPolicy",
        # EFS events
        "CreateFileSystem",
        "PutFileSystemPolicy"
      ]
    }
  })

  tags = {
    Name        = "Cloud Custodian Local Trigger"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# EventBridge Rule on default bus - Trigger Lambda for SecurityHub findings in central account
resource "aws_cloudwatch_event_rule" "custodian_local_securityhub_trigger" {
  name        = "cloud-custodian-local-securityhub-${var.environment}"
  description = "Trigger Cloud Custodian Lambda for SecurityHub findings in central account"

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
  })

  tags = {
    Name        = "Cloud Custodian Local SecurityHub Trigger"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# EventBridge Target - Lambda function for local SecurityHub events
resource "aws_cloudwatch_event_target" "lambda_local_securityhub" {
  rule = aws_cloudwatch_event_rule.custodian_local_securityhub_trigger.name
  arn  = aws_lambda_function.custodian_cross_account_executor.arn
}

# Lambda Permission - Allow EventBridge to invoke for SecurityHub events
resource "aws_lambda_permission" "allow_eventbridge_local_securityhub" {
  statement_id  = "AllowExecutionFromEventBridgeLocalSecurityHub"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.custodian_cross_account_executor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.custodian_local_securityhub_trigger.arn
}

# EventBridge Target - Lambda function for local events
resource "aws_cloudwatch_event_target" "lambda_local" {
  rule = aws_cloudwatch_event_rule.custodian_local_trigger.name
  arn  = aws_lambda_function.custodian_cross_account_executor.arn
}

# Lambda Permission - Allow EventBridge default bus to invoke
resource "aws_lambda_permission" "allow_eventbridge_local" {
  statement_id  = "AllowExecutionFromEventBridgeLocal"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.custodian_cross_account_executor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.custodian_local_trigger.arn
}

# EventBridge Rule on custom bus - Trigger Lambda for cross-account EC2 events
resource "aws_cloudwatch_event_rule" "custodian_cross_account_trigger" {
  name           = "cloud-custodian-cross-account-trigger-${var.environment}"
  description    = "Trigger Cloud Custodian Lambda for cross-account security events"
  event_bus_name = aws_cloudwatch_event_bus.centralized.name

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    account     = var.member_account_ids
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = ["RunInstances"]
    }
  })

  tags = {
    Name        = "Cloud Custodian Cross-Account Trigger"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# EventBridge Rule on custom bus - Trigger Lambda for all security events from member accounts (consolidated)
resource "aws_cloudwatch_event_rule" "custodian_security_events_from_members" {
  name           = "custodian-security-events-from-members-${var.environment}"
  description    = "Trigger Cloud Custodian Lambda for all security events (CloudTrail, SecurityHub, GuardDuty) from member accounts"
  event_bus_name = aws_cloudwatch_event_bus.centralized.name

  event_pattern = jsonencode({
    account = var.member_account_ids
    "$or" = [
      {
        detail-type = ["AWS API Call via CloudTrail"]
        detail = {
          "$or" = [
            {
              eventSource = ["ec2.amazonaws.com"]
              eventName   = ["RunInstances", "ModifyImageAttribute", "CreateImage", "CopyImage"]
            },
            {
              eventSource = ["elasticloadbalancing.amazonaws.com"]
              eventName   = ["CreateLoadBalancer", "CreateListener", "ModifyListener", "ModifyLoadBalancerAttributes", "DeleteLoadBalancer", "DeleteListener"]
            },
            {
              eventSource = ["s3.amazonaws.com"]
              eventName   = ["CreateBucket", "PutBucketPolicy", "PutBucketAcl", "PutBucketPublicAccessBlock", "DeleteBucketPublicAccessBlock", "PutBucketEncryption", "DeleteBucketEncryption"]
            }
          ]
        }
      },
      {
        source      = ["aws.securityhub"]
        detail-type = ["Security Hub Findings - Imported"]
      },
      {
        source      = ["aws.guardduty"]
        detail-type = ["GuardDuty Finding"]
      }
    ]
  })

  tags = {
    Name        = "Cloud Custodian Security Events from Members"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
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
      POLICY_BUCKET           = var.policy_bucket
      ACCOUNT_MAPPING_KEY     = "config/account-policy-mapping.json"
      CROSS_ACCOUNT_ROLE_NAME = "CloudCustodianExecutionRole"
      EXTERNAL_ID_PREFIX      = "cloud-custodian"
      LOG_LEVEL               = var.log_level
      MAILER_QUEUE_URL        = aws_sqs_queue.custodian_mailer.url
      MAILER_ENABLED          = "true"
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
        Resource = [
          "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/*",
          "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/c7n/*"
        ]
      },
      {
        Sid    = "CloudWatchLogsDescribe"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      },
      {
        Sid    = "SQSMailerQueue"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueUrl",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.custodian_mailer.arn
      },
      {
        Sid    = "EC2LocalAccountRemediation"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceAttribute",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeTags",
          "ec2:TerminateInstances",
          "ec2:StopInstances",
          "ec2:ModifyInstanceAttribute",
          "ec2:CreateTags"
        ]
        Resource = "*"
      },
      {
        Sid    = "ALBLocalAccountRead"
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
          "iam:ListAccountAliases",
          "iam:GetRole",
          "iam:GetRolePolicy"
        ]
        Resource = "*"
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

# SQS Queue for Cloud Custodian Notifications
resource "aws_sqs_queue" "custodian_mailer" {
  name                       = "cloud-custodian-mailer-queue-${var.environment}"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 1209600 # 14 days

  tags = {
    Name        = "Cloud Custodian Mailer Queue"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# SQS Dead Letter Queue
resource "aws_sqs_queue" "custodian_mailer_dlq" {
  name                      = "cloud-custodian-mailer-dlq-${var.environment}"
  message_retention_seconds = 1209600 # 14 days

  tags = {
    Name        = "Cloud Custodian Mailer DLQ"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# SQS Queue Policy - Allow member account roles to send messages
resource "aws_sqs_queue_policy" "custodian_mailer_policy" {
  queue_url = aws_sqs_queue.custodian_mailer.url

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
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.custodian_mailer.arn
      },
      {
        Sid    = "AllowCentralAccountLambda"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/cloud-custodian-cross-account-executor-role-${var.environment}"
        }
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.custodian_mailer.arn
      }
    ]
  })
}

# SNS Topic for Email Notifications
resource "aws_sns_topic" "custodian_notifications" {
  name = "cloud-custodian-notifications-${var.environment}"

  tags = {
    Name        = "Cloud Custodian Notifications"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# SNS Topic Subscription - Email
resource "aws_sns_topic_subscription" "email_subscription" {
  topic_arn = aws_sns_topic.custodian_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# SNS Topic Policy - Allow mailer Lambda to publish
resource "aws_sns_topic_policy" "custodian_notifications_policy" {
  arn = aws_sns_topic.custodian_notifications.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowMailerLambdaPublish"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.custodian_notifications.arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# Lambda Function - Mailer (SQS to SNS)
resource "aws_lambda_function" "custodian_mailer" {
  count            = var.create_mailer_lambda ? 1 : 0
  filename         = var.mailer_lambda_package_path
  function_name    = "cloud-custodian-mailer-${var.environment}"
  role             = aws_iam_role.mailer_execution.arn
  handler          = "mailer.handler"
  runtime          = "python3.11"
  timeout          = 300
  memory_size      = 256
  source_code_hash = filebase64sha256(var.mailer_lambda_package_path)

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.custodian_notifications.arn
      LOG_LEVEL     = var.log_level
    }
  }

  tags = {
    Name        = "Cloud Custodian Mailer"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# CloudWatch Log Group for Mailer Lambda
resource "aws_cloudwatch_log_group" "mailer_logs" {
  count             = var.create_mailer_lambda ? 1 : 0
  name              = "/aws/lambda/${aws_lambda_function.custodian_mailer[0].function_name}"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "Cloud Custodian Mailer Logs"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# IAM Role for Mailer Lambda
resource "aws_iam_role" "mailer_execution" {
  name = "cloud-custodian-mailer-role-${var.environment}"

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
    Name        = "Cloud Custodian Mailer Role"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# IAM Policy for Mailer Lambda
resource "aws_iam_role_policy" "mailer_execution_policy" {
  name = "mailer-execution-policy"
  role = aws_iam_role.mailer_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
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
        Sid    = "SQSReceiveDelete"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.custodian_mailer.arn
      },
      {
        Sid      = "SNSPublish"
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = aws_sns_topic.custodian_notifications.arn
      }
    ]
  })
}

# Lambda Event Source Mapping - SQS to Lambda
resource "aws_lambda_event_source_mapping" "sqs_to_mailer" {
  count            = var.create_mailer_lambda ? 1 : 0
  event_source_arn = aws_sqs_queue.custodian_mailer.arn
  function_name    = aws_lambda_function.custodian_mailer[0].function_name
  batch_size       = 10
  enabled          = true
}

