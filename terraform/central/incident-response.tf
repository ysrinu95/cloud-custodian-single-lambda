# ============================================================================
# S3 Ransomware Incident Response Infrastructure
# ============================================================================
# Step Functions state machine and Lambda functions for automated incident response
# ============================================================================

# ============================================================================
# Variables for Incident Response
# ============================================================================

variable "enable_incident_response" {
  description = "Enable incident response Step Functions and Lambda functions"
  type        = bool
  default     = true
}

variable "incident_response_sns_topic" {
  description = "SNS topic ARN for incident response notifications"
  type        = string
  default     = ""
}

# ============================================================================
# SNS Topic for Security Alerts
# ============================================================================

resource "aws_sns_topic" "security_alerts" {
  count = var.enable_incident_response ? 1 : 0
  
  name              = "security-alerts"
  display_name      = "Security Alerts and Incident Notifications"
  kms_master_key_id = "alias/aws/sns"
  
  tags = merge(
    var.common_tags,
    {
      Name        = "security-alerts"
      Purpose     = "IncidentResponse"
      ManagedBy   = "Terraform"
    }
  )
}

resource "aws_sns_topic_subscription" "security_alerts_email" {
  count = var.enable_incident_response ? 1 : 0
  
  topic_arn = aws_sns_topic.security_alerts[0].arn
  protocol  = "email"
  endpoint  = var.mailer_from_address  # Use the same email as mailer
}

# ============================================================================
# CloudWatch Log Group for Incident Response
# ============================================================================

resource "aws_cloudwatch_log_group" "incident_response" {
  count = var.enable_incident_response ? 1 : 0
  
  name              = "/aws/lambda/incident-response"
  retention_in_days = 90
  kms_key_id        = null
  
  tags = merge(
    var.common_tags,
    {
      Name      = "incident-response-logs"
      Purpose   = "IncidentResponse"
      ManagedBy = "Terraform"
    }
  )
}

# ============================================================================
# IAM Role for Incident Response Lambdas
# ============================================================================

resource "aws_iam_role" "incident_response_lambda" {
  count = var.enable_incident_response ? 1 : 0
  
  name        = "IncidentResponseLambdaRole"
  description = "IAM role for incident response Lambda functions"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  
  tags = merge(
    var.common_tags,
    {
      Name      = "IncidentResponseLambdaRole"
      Purpose   = "IncidentResponse"
      ManagedBy = "Terraform"
    }
  )
}

# IAM Policy for Incident Response Lambda
resource "aws_iam_role_policy" "incident_response_lambda" {
  count = var.enable_incident_response ? 1 : 0
  
  name = "IncidentResponseLambdaPolicy"
  role = aws_iam_role.incident_response_lambda[0].id
  
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
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/incident-response:*"
      },
      {
        Sid    = "S3BucketOperations"
        Effect = "Allow"
        Action = [
          "s3:GetBucketVersioning",
          "s3:GetBucketEncryption",
          "s3:GetPublicAccessBlock",
          "s3:GetObjectLockConfiguration",
          "s3:GetBucketLogging",
          "s3:GetBucketPolicy",
          "s3:GetBucketAcl",
          "s3:GetBucketTagging",
          "s3:PutBucketVersioning",
          "s3:PutBucketEncryption",
          "s3:PutPublicAccessBlock",
          "s3:PutBucketPolicy",
          "s3:PutBucketAcl",
          "s3:PutBucketTagging",
          "s3:DeleteBucketPolicy",
          "s3:ListBucket",
          "s3:ListBucketVersions",
          "s3:ListAccessPoints"
        ]
        Resource = "arn:aws:s3:::*"
      },
      {
        Sid    = "S3ObjectOperations"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:CopyObject",
          "s3:HeadObject"
        ]
        Resource = "arn:aws:s3:::*/*"
      },
      {
        Sid    = "GuardDutyRead"
        Effect = "Allow"
        Action = [
          "guardduty:ListDetectors",
          "guardduty:ListFindings",
          "guardduty:GetFindings"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchMetrics"
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:PutMetricAlarm",
          "cloudwatch:DescribeAlarms"
        ]
        Resource = "*"
      },
      {
        Sid    = "IAMOperations"
        Effect = "Allow"
        Action = [
          "iam:ListAccessKeys",
          "iam:UpdateAccessKey",
          "iam:DeleteAccessKey",
          "iam:GetRole",
          "iam:GetUser",
          "iam:ListAttachedRolePolicies",
          "iam:ListRolePolicies",
          "iam:DetachRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:DeleteRole"
        ]
        Resource = "*"
      },
      {
        Sid    = "SNSPublish"
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = var.enable_incident_response ? aws_sns_topic.security_alerts[0].arn : "*"
      },
      {
        Sid    = "SecurityHubFindings"
        Effect = "Allow"
        Action = [
          "securityhub:BatchImportFindings",
          "securityhub:BatchUpdateFindings"
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2Describe"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeSecurityGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach AWS managed policy for basic Lambda execution
resource "aws_iam_role_policy_attachment" "incident_response_lambda_basic" {
  count = var.enable_incident_response ? 1 : 0
  
  role       = aws_iam_role.incident_response_lambda[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ============================================================================
# Lambda Functions for Each Incident Response Phase
# ============================================================================

# Phase 1: Detection & Triage
resource "aws_lambda_function" "ir_phase1_detection" {
  count = var.enable_incident_response ? 1 : 0
  
  function_name = "ir-phase1-detection-triage"
  description   = "Incident Response Phase 1: Detection and Triage"
  role          = aws_iam_role.incident_response_lambda[0].arn
  handler       = "phase1_detection_triage.lambda_handler"
  runtime       = "python3.12"
  timeout       = 300
  memory_size   = 512
  
  filename         = data.archive_file.ir_phase1[0].output_path
  source_code_hash = data.archive_file.ir_phase1[0].output_base64sha256
  
  environment {
    variables = {
      REGION           = var.aws_region
      SNS_TOPIC_ARN    = aws_sns_topic.security_alerts[0].arn
      LOG_GROUP_NAME   = aws_cloudwatch_log_group.incident_response[0].name
    }
  }
  
  tracing_config {
    mode = "Active"
  }
  
  tags = merge(
    var.common_tags,
    {
      Name      = "ir-phase1-detection-triage"
      Phase     = "Detection"
      Purpose   = "IncidentResponse"
      ManagedBy = "Terraform"
    }
  )
}

# Phase 2: Containment
resource "aws_lambda_function" "ir_phase2_containment" {
  count = var.enable_incident_response ? 1 : 0
  
  function_name = "ir-phase2-containment"
  description   = "Incident Response Phase 2: Containment"
  role          = aws_iam_role.incident_response_lambda[0].arn
  handler       = "phase2_containment.lambda_handler"
  runtime       = "python3.12"
  timeout       = 300
  memory_size   = 512
  
  filename         = data.archive_file.ir_phase2[0].output_path
  source_code_hash = data.archive_file.ir_phase2[0].output_base64sha256
  
  environment {
    variables = {
      REGION           = var.aws_region
      SNS_TOPIC_ARN    = aws_sns_topic.security_alerts[0].arn
      BACKUP_BUCKET    = var.policy_bucket
    }
  }
  
  tracing_config {
    mode = "Active"
  }
  
  tags = merge(
    var.common_tags,
    {
      Name      = "ir-phase2-containment"
      Phase     = "Containment"
      Purpose   = "IncidentResponse"
      ManagedBy = "Terraform"
    }
  )
}

# Phase 3: Eradication
resource "aws_lambda_function" "ir_phase3_eradication" {
  count = var.enable_incident_response ? 1 : 0
  
  function_name = "ir-phase3-eradication"
  description   = "Incident Response Phase 3: Eradication"
  role          = aws_iam_role.incident_response_lambda[0].arn
  handler       = "phase3_eradication.lambda_handler"
  runtime       = "python3.12"
  timeout       = 600
  memory_size   = 512
  
  filename         = data.archive_file.ir_phase3[0].output_path
  source_code_hash = data.archive_file.ir_phase3[0].output_base64sha256
  
  environment {
    variables = {
      REGION        = var.aws_region
      BACKUP_BUCKET = var.policy_bucket
    }
  }
  
  tracing_config {
    mode = "Active"
  }
  
  tags = merge(
    var.common_tags,
    {
      Name      = "ir-phase3-eradication"
      Phase     = "Eradication"
      Purpose   = "IncidentResponse"
      ManagedBy = "Terraform"
    }
  )
}

# Phase 4: Recovery
resource "aws_lambda_function" "ir_phase4_recovery" {
  count = var.enable_incident_response ? 1 : 0
  
  function_name = "ir-phase4-recovery"
  description   = "Incident Response Phase 4: Recovery"
  role          = aws_iam_role.incident_response_lambda[0].arn
  handler       = "phase4_recovery.lambda_handler"
  runtime       = "python3.12"
  timeout       = 300
  memory_size   = 512
  
  filename         = data.archive_file.ir_phase4[0].output_path
  source_code_hash = data.archive_file.ir_phase4[0].output_base64sha256
  
  environment {
    variables = {
      REGION           = var.aws_region
      SNS_TOPIC_ARN    = aws_sns_topic.security_alerts[0].arn
      BACKUP_BUCKET    = var.policy_bucket
    }
  }
  
  tracing_config {
    mode = "Active"
  }
  
  tags = merge(
    var.common_tags,
    {
      Name      = "ir-phase4-recovery"
      Phase     = "Recovery"
      Purpose   = "IncidentResponse"
      ManagedBy = "Terraform"
    }
  )
}

# Phase 5: Post-Incident Analysis
resource "aws_lambda_function" "ir_phase5_post_incident" {
  count = var.enable_incident_response ? 1 : 0
  
  function_name = "ir-phase5-post-incident"
  description   = "Incident Response Phase 5: Post-Incident Analysis"
  role          = aws_iam_role.incident_response_lambda[0].arn
  handler       = "phase5_post_incident.lambda_handler"
  runtime       = "python3.12"
  timeout       = 300
  memory_size   = 512
  
  filename         = data.archive_file.ir_phase5[0].output_path
  source_code_hash = data.archive_file.ir_phase5[0].output_base64sha256
  
  environment {
    variables = {
      REGION           = var.aws_region
      SNS_TOPIC_ARN    = aws_sns_topic.security_alerts[0].arn
      REPORT_BUCKET    = var.policy_bucket
    }
  }
  
  tracing_config {
    mode = "Active"
  }
  
  tags = merge(
    var.common_tags,
    {
      Name      = "ir-phase5-post-incident"
      Phase     = "PostIncident"
      Purpose   = "IncidentResponse"
      ManagedBy = "Terraform"
    }
  )
}

# ============================================================================
# Archive Data Sources for Lambda Functions
# ============================================================================

data "archive_file" "ir_phase1" {
  count = var.enable_incident_response ? 1 : 0
  
  type        = "zip"
  source_file = "${path.module}/../../lambda-functions/incident-response/phase1_detection_triage.py"
  output_path = "${path.module}/../../output/ir-phase1-detection-triage.zip"
}

data "archive_file" "ir_phase2" {
  count = var.enable_incident_response ? 1 : 0
  
  type        = "zip"
  source_file = "${path.module}/../../lambda-functions/incident-response/phase2_containment.py"
  output_path = "${path.module}/../../output/ir-phase2-containment.zip"
}

data "archive_file" "ir_phase3" {
  count = var.enable_incident_response ? 1 : 0
  
  type        = "zip"
  source_file = "${path.module}/../../lambda-functions/incident-response/phase3_eradication.py"
  output_path = "${path.module}/../../output/ir-phase3-eradication.zip"
}

data "archive_file" "ir_phase4" {
  count = var.enable_incident_response ? 1 : 0
  
  type        = "zip"
  source_file = "${path.module}/../../lambda-functions/incident-response/phase4_recovery.py"
  output_path = "${path.module}/../../output/ir-phase4-recovery.zip"
}

data "archive_file" "ir_phase5" {
  count = var.enable_incident_response ? 1 : 0
  
  type        = "zip"
  source_file = "${path.module}/../../lambda-functions/incident-response/phase5_post_incident.py"
  output_path = "${path.module}/../../output/ir-phase5-post-incident.zip"
}

# ============================================================================
# IAM Role for Step Functions
# ============================================================================

resource "aws_iam_role" "incident_response_sfn" {
  count = var.enable_incident_response ? 1 : 0
  
  name        = "IncidentResponseStepFunctionsRole"
  description = "IAM role for incident response Step Functions state machine"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  
  tags = merge(
    var.common_tags,
    {
      Name      = "IncidentResponseStepFunctionsRole"
      Purpose   = "IncidentResponse"
      ManagedBy = "Terraform"
    }
  )
}

# IAM Policy for Step Functions
resource "aws_iam_role_policy" "incident_response_sfn" {
  count = var.enable_incident_response ? 1 : 0
  
  name = "IncidentResponseStepFunctionsPolicy"
  role = aws_iam_role.incident_response_sfn[0].id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "InvokeLambdaFunctions"
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          aws_lambda_function.ir_phase1_detection[0].arn,
          aws_lambda_function.ir_phase2_containment[0].arn,
          aws_lambda_function.ir_phase3_eradication[0].arn,
          aws_lambda_function.ir_phase4_recovery[0].arn,
          aws_lambda_function.ir_phase5_post_incident[0].arn
        ]
      },
      {
        Sid    = "PublishToSNS"
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.security_alerts[0].arn
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

# ============================================================================
# CloudWatch Log Group for Step Functions
# ============================================================================

resource "aws_cloudwatch_log_group" "incident_response_sfn" {
  count = var.enable_incident_response ? 1 : 0
  
  name              = "/aws/vendedlogs/states/incident-response-state-machine"
  retention_in_days = 90
  
  tags = merge(
    var.common_tags,
    {
      Name      = "incident-response-sfn-logs"
      Purpose   = "IncidentResponse"
      ManagedBy = "Terraform"
    }
  )
}

# ============================================================================
# Step Functions State Machine
# ============================================================================

resource "aws_sfn_state_machine" "incident_response" {
  count = var.enable_incident_response ? 1 : 0
  
  name     = "s3-ransomware-incident-response"
  role_arn = aws_iam_role.incident_response_sfn[0].arn
  
  definition = templatefile("${path.module}/../../lambda-functions/incident-response/state-machine-definition.json", {
    detection_lambda_arn     = aws_lambda_function.ir_phase1_detection[0].arn
    containment_lambda_arn   = aws_lambda_function.ir_phase2_containment[0].arn
    eradication_lambda_arn   = aws_lambda_function.ir_phase3_eradication[0].arn
    recovery_lambda_arn      = aws_lambda_function.ir_phase4_recovery[0].arn
    post_incident_lambda_arn = aws_lambda_function.ir_phase5_post_incident[0].arn
    sns_topic_arn            = aws_sns_topic.security_alerts[0].arn
  })
  
  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.incident_response_sfn[0].arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }
  
  tracing_configuration {
    enabled = true
  }
  
  tags = merge(
    var.common_tags,
    {
      Name      = "s3-ransomware-incident-response"
      Purpose   = "IncidentResponse"
      ManagedBy = "Terraform"
    }
  )
}

# ============================================================================
# Outputs for Incident Response Infrastructure
# ============================================================================

output "incident_response_state_machine_arn" {
  description = "ARN of the incident response Step Functions state machine"
  value       = var.enable_incident_response ? aws_sfn_state_machine.incident_response[0].arn : null
}

output "incident_response_lambda_arns" {
  description = "ARNs of incident response Lambda functions"
  value = var.enable_incident_response ? {
    phase1_detection     = aws_lambda_function.ir_phase1_detection[0].arn
    phase2_containment   = aws_lambda_function.ir_phase2_containment[0].arn
    phase3_eradication   = aws_lambda_function.ir_phase3_eradication[0].arn
    phase4_recovery      = aws_lambda_function.ir_phase4_recovery[0].arn
    phase5_post_incident = aws_lambda_function.ir_phase5_post_incident[0].arn
  } : null
}

output "security_alerts_topic_arn" {
  description = "ARN of the security alerts SNS topic"
  value       = var.enable_incident_response ? aws_sns_topic.security_alerts[0].arn : null
}
