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
    key     = "cross-account-implementation/member-account/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region
}

# Data source to get current AWS account ID
data "aws_caller_identity" "current" {}

# EventBridge Rule - Forward EC2 events to central account
resource "aws_cloudwatch_event_rule" "forward_to_central" {
  name        = "forward-security-events-to-central-${var.environment}"
  description = "Forward security events from this member account to central security account"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = ["RunInstances"]
    }
  })

  tags = {
    Name        = "Forward Security Events to Central Account"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# EventBridge Rule - Forward SecurityHub findings to central account
resource "aws_cloudwatch_event_rule" "forward_securityhub_to_central" {
  name        = "forward-securityhub-to-central-${var.environment}"
  description = "Forward SecurityHub findings from this member account to central security account"

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
  })

  tags = {
    Name        = "Forward SecurityHub Findings to Central Account"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# EventBridge Rule - Forward GuardDuty findings directly to central account (real-time)
resource "aws_cloudwatch_event_rule" "forward_guardduty_to_central" {
  name        = "forward-guardduty-to-central-${var.environment}"
  description = "Forward GuardDuty findings directly to central account for real-time detection"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
  })

  tags = {
    Name        = "Forward GuardDuty Findings to Central Account"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# EventBridge Rule - Forward ALB CloudTrail events to central account
resource "aws_cloudwatch_event_rule" "forward_alb_cloudtrail_to_central" {
  name        = "forward-alb-cloudtrail-to-central-${var.environment}"
  description = "Forward ALB CloudTrail events from this member account to central security account"

  event_pattern = jsonencode({
    source      = ["aws.elasticloadbalancing"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = [
        "CreateLoadBalancer",
        "CreateListener",
        "ModifyListener",
        "ModifyLoadBalancerAttributes",
        "DeleteLoadBalancer",
        "DeleteListener"
      ]
    }
  })

  tags = {
    Name        = "Forward ALB CloudTrail Events to Central Account"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# EventBridge Rule - Forward S3 CloudTrail events to central account
resource "aws_cloudwatch_event_rule" "forward_s3_cloudtrail_to_central" {
  name        = "forward-s3-cloudtrail-to-central-${var.environment}"
  description = "Forward S3 CloudTrail events from this member account to central security account"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = [
        "CreateBucket",
        "PutBucketPolicy",
        "PutBucketAcl",
        "PutBucketPublicAccessBlock",
        "DeleteBucketPublicAccessBlock",
        "PutBucketEncryption",
        "DeleteBucketEncryption"
      ]
    }
  })

  tags = {
    Name        = "Forward S3 CloudTrail Events to Central Account"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# EventBridge Target - Central account event bus for EC2 events
resource "aws_cloudwatch_event_target" "central_bus" {
  rule     = aws_cloudwatch_event_rule.forward_to_central.name
  arn      = var.central_event_bus_arn
  role_arn = aws_iam_role.eventbridge_cross_account.arn
}

# EventBridge Target - Central account event bus for SecurityHub events
resource "aws_cloudwatch_event_target" "central_bus_securityhub" {
  rule     = aws_cloudwatch_event_rule.forward_securityhub_to_central.name
  arn      = var.central_event_bus_arn
  role_arn = aws_iam_role.eventbridge_cross_account.arn
}

# EventBridge Target - Central account event bus for GuardDuty findings (real-time)
resource "aws_cloudwatch_event_target" "central_bus_guardduty" {
  rule     = aws_cloudwatch_event_rule.forward_guardduty_to_central.name
  arn      = var.central_event_bus_arn
  role_arn = aws_iam_role.eventbridge_cross_account.arn
}

# EventBridge Target - Central account event bus for ALB CloudTrail events
resource "aws_cloudwatch_event_target" "central_bus_alb" {
  rule     = aws_cloudwatch_event_rule.forward_alb_cloudtrail_to_central.name
  arn      = var.central_event_bus_arn
  role_arn = aws_iam_role.eventbridge_cross_account.arn
}

# EventBridge Target - Central account event bus for S3 CloudTrail events
resource "aws_cloudwatch_event_target" "central_bus_s3" {
  rule     = aws_cloudwatch_event_rule.forward_s3_cloudtrail_to_central.name
  arn      = var.central_event_bus_arn
  role_arn = aws_iam_role.eventbridge_cross_account.arn
}

# IAM Role for EventBridge cross-account event forwarding
resource "aws_iam_role" "eventbridge_cross_account" {
  name = "eventbridge-cross-account-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "events.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "EventBridge Cross-Account Role"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# IAM Policy for EventBridge - Allow putting events to central bus
resource "aws_iam_role_policy" "eventbridge_put_events" {
  name = "eventbridge-put-events-policy"
  role = aws_iam_role.eventbridge_cross_account.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "events:PutEvents"
      Resource = var.central_event_bus_arn
    }]
  })
}

# IAM Role - Cloud Custodian execution role (to be assumed by central account)
resource "aws_iam_role" "custodian_execution" {
  name        = "CloudCustodianExecutionRole"
  description = "Role assumed by central account to execute Cloud Custodian policies"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${var.central_account_id}:role/cloud-custodian-cross-account-executor-role-${var.central_environment}"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "sts:ExternalId" = "cloud-custodian-${data.aws_caller_identity.current.account_id}"
        }
      }
    }]
  })

  max_session_duration = 3600 # 1 hour

  tags = {
    Name        = "Cloud Custodian Execution Role"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# IAM Policy - Cloud Custodian remediation permissions
resource "aws_iam_policy" "custodian_remediation" {
  name        = "CloudCustodianRemediationPolicy"
  description = "Permissions for Cloud Custodian to remediate resources in this account"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2Remediation"
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
        Sid    = "EC2SecurityGroups"
        Effect = "Allow"
        Action = [
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSecurityGroupRules",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupEgress",
          "ec2:ModifySecurityGroupRules"
        ]
        Resource = "*"
      },
      {
        Sid    = "ALBRemediation"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DescribeTags",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:SetSecurityGroups",
          "elasticloadbalancing:AddTags"
        ]
        Resource = "*"
      },
      {
        Sid    = "S3Remediation"
        Effect = "Allow"
        Action = [
          "s3:ListAllMyBuckets",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:GetBucketPublicAccessBlock",
          "s3:GetBucketPolicy",
          "s3:GetBucketAcl",
          "s3:GetBucketEncryption",
          "s3:PutBucketPublicAccessBlock",
          "s3:PutBucketPolicy",
          "s3:PutBucketAcl",
          "s3:PutBucketTagging",
          "s3:PutEncryptionConfiguration",
          "s3:GetBucketTagging"
        ]
        Resource = "*"
      },
      {
        Sid    = "IAMReadOnly"
        Effect = "Allow"
        Action = [
          "iam:ListUsers",
          "iam:ListRoles",
          "iam:ListPolicies",
          "iam:ListAccessKeys",
          "iam:ListAccountAliases",
          "iam:GetUser",
          "iam:GetRole",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListAttachedUserPolicies",
          "iam:ListAttachedRolePolicies",
          "iam:ListUserPolicies",
          "iam:ListRolePolicies"
        ]
        Resource = "*"
      },
      {
        Sid    = "IAMRemediation"
        Effect = "Allow"
        Action = [
          "iam:DeleteAccessKey",
          "iam:UpdateAccessKey",
          "iam:TagUser",
          "iam:TagRole"
        ]
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "iam:ResourceTag/Protected" = "true"
          }
        }
      },
      {
        Sid    = "SecurityHubRead"
        Effect = "Allow"
        Action = [
          "securityhub:GetFindings",
          "securityhub:DescribeHub",
          "securityhub:ListFindingAggregators"
        ]
        Resource = "*"
      },
      {
        Sid    = "SecurityHubUpdate"
        Effect = "Allow"
        Action = [
          "securityhub:BatchUpdateFindings"
        ]
        Resource = "*"
      },
      {
        Sid    = "GuardDutyRead"
        Effect = "Allow"
        Action = [
          "guardduty:GetFindings",
          "guardduty:ListFindings",
          "guardduty:ListDetectors",
          "guardduty:GetDetector"
        ]
        Resource = "*"
      },
      {
        Sid    = "ConfigRead"
        Effect = "Allow"
        Action = [
          "config:DescribeConfigRules",
          "config:DescribeComplianceByConfigRule",
          "config:GetComplianceDetailsByConfigRule"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/cloud-custodian/*"
      },
      {
        Sid    = "SQSMailerQueue"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueUrl",
          "sqs:GetQueueAttributes"
        ]
        Resource = "arn:aws:sqs:${var.aws_region}:${var.central_account_id}:custodian-mailer-queue"
      }
    ]
  })

  tags = {
    Name        = "Cloud Custodian Remediation Policy"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Attach remediation policy to execution role
resource "aws_iam_role_policy_attachment" "custodian_permissions" {
  role       = aws_iam_role.custodian_execution.name
  policy_arn = aws_iam_policy.custodian_remediation.arn
}

# Optional: CloudWatch Log Group for local logging
resource "aws_cloudwatch_log_group" "custodian_local" {
  count             = var.create_local_log_group ? 1 : 0
  name              = "/aws/cloud-custodian/${var.environment}"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "Cloud Custodian Local Logs"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
