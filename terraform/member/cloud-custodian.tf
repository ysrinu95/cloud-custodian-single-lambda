# ============================================================================
# Cloud Custodian Member Account Infrastructure - Consolidated Configuration
# ============================================================================
# This file consolidates all Terraform configuration for member accounts
# AWS provider, EventBridge, IAM roles, and policies
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
  }

  backend "s3" {
    bucket  = "ysr95-cloud-custodian-tf-bkt"
    key     = "member/cloud-custodian/terraform.tfstate"
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

# Data source to get current AWS account ID
data "aws_caller_identity" "current" {}

# ============================================================================
# Variables
# ============================================================================

variable "aws_region" {
  description = "AWS region for this member account"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name for this member account (e.g., production, development, staging)"
  type        = string
  default     = "dev"
}

variable "central_account_id" {
  description = "AWS account ID of the central security account"
  type        = string
  validation {
    condition     = can(regex("^\\d{12}$", var.central_account_id))
    error_message = "Central account ID must be a 12-digit AWS account ID."
  }
  default = "172327596604"
}

variable "central_environment" {
  description = "Environment name used in the central account (must match central account setup)"
  type        = string
  default     = "central"
}

variable "central_event_bus_arn" {
  description = "ARN of the EventBridge custom bus in the central account"
  type        = string
  validation {
    condition     = can(regex("^arn:aws:events:[a-z0-9-]+:\\d{12}:event-bus/", var.central_event_bus_arn))
    error_message = "Central event bus ARN must be a valid EventBridge ARN."
  }
  default = "arn:aws:events:us-east-1:172327596604:event-bus/aikyam-cloud-custodian-centralized-security-events"
}

variable "create_local_log_group" {
  description = "Whether to create a local CloudWatch log group for Cloud Custodian"
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days (if creating local log group)"
  type        = number
  default     = 7
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention value."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {
    terraform = "True"
    oid-owned = "True"
    environment = "dev"
    component = "cloud-custodian"
    application = "cloud-custodian"
  }
}

# ============================================================================
# EventBridge Resources
# ============================================================================

# EventBridge Rule - Forward all security events to central account (consolidated)
resource "aws_cloudwatch_event_rule" "forward_security_events_to_central" {
  name        = "aikyam-cloud-custodian-forward-security-events-to-central"
  description = "Forward all security events (CloudTrail, SecurityHub, GuardDuty) to central account"

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
            "CopyImage",
            # EBS events
            "CreateVolume",
            "CreateSnapshot",
            "ModifySnapshotAttribute",
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
            "SetRepositoryPolicy",
            "PutRepositoryPolicy",
            "DeleteRepositoryPolicy",
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
      Name      = "aikyam-cloud-custodian-forward-security-events-to-central"
      terraform = "True"
      oid-owned = "True"
    }
  )
}

# EventBridge Target - Central account event bus for all security events
resource "aws_cloudwatch_event_target" "central_bus_security_events" {
  rule      = aws_cloudwatch_event_rule.forward_security_events_to_central.name
  target_id = "SendToCentralBus"
  arn       = var.central_event_bus_arn
  role_arn  = aws_iam_role.eventbridge_cross_account.arn

  depends_on = [aws_cloudwatch_event_rule.forward_security_events_to_central]
}

# ============================================================================
# IAM Resources - EventBridge Cross-Account
# ============================================================================

# IAM Role for EventBridge cross-account event forwarding
resource "aws_iam_role" "eventbridge_cross_account" {
  name = "aikyam-cloud-custodian-eventbridge-cross-account-role"

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

  tags = merge(
    var.tags,
    {
      Name      = "aikyam-cloud-custodian-eventbridge-cross-account-role"
      terraform = "True"
      oid-owned = "True"
    }
  )
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

# ============================================================================
# IAM Resources - Cloud Custodian Execution
# ============================================================================

# IAM Role - Cloud Custodian execution role (to be assumed by service user and central account Lambda)
resource "aws_iam_role" "custodian_execution" {
  name        = "CloudCustodianExecutionRole"
  description = "Role for executing Cloud Custodian policies via Jenkins CI/CD pipeline and central account Lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCentralAccountLambdaAssume"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.central_account_id}:role/cloud-custodian-cross-account-executor-role"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = "cloud-custodian-${data.aws_caller_identity.current.account_id}"
          }
        }
      },
      {
        Sid    = "AllowMemberAccountRootAssume"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = "sts:AssumeRole"
      }
    ]
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

# IAM Policy 1 - Cloud Custodian compute and network permissions (EC2, ELB, S3)
resource "aws_iam_policy" "custodian_compute_network" {
  name        = "CloudCustodianComputeNetworkPolicy"
  description = "Permissions for Cloud Custodian compute and network resources (EC2, ELB, S3)"

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
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSecurityGroupRules",
          "ec2:DescribeSnapshots",
          "ec2:DescribeEbs",
          "ec2:DescribeVolumes",
          "ec2:DescribeImages",
          "ec2:DescribeImageAttribute"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.aws_region
          }
        }
      },
      {
        Sid    = "EC2RemediationActions"
        Effect = "Allow"
        Action = [
          "ec2:TerminateInstances",
          "ec2:StopInstances",
          "ec2:ModifyInstanceAttribute",
          "ec2:CreateTags",
          "ec2:ModifyImageAttribute",
          "ec2:ModifySnapshotAttribute"
        ]
        Resource = [
          "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/*",
          "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:image/*",
          "arn:aws:ec2:${var.aws_region}::snapshot/*"
        ]
      },
      {
        Sid    = "EC2SecurityGroupActions"
        Effect = "Allow"
        Action = [
          "ec2:RevokeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupEgress",
          "ec2:ModifySecurityGroupRules"
        ]
        Resource = [
          "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:security-group/*"
        ]
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
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.aws_region
          }
        }
      },
      {
        Sid    = "ALBRemediationActions"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:SetSecurityGroups",
          "elasticloadbalancing:AddTags"
        ]
        Resource = [
          "arn:aws:elasticloadbalancing:${var.aws_region}:${data.aws_caller_identity.current.account_id}:loadbalancer/*",
          "arn:aws:elasticloadbalancing:${var.aws_region}:${data.aws_caller_identity.current.account_id}:listener/*"
        ]
      },
      {
        Sid    = "S3ListActions"
        Effect = "Allow"
        Action = [
          "s3:ListAllMyBuckets"
        ]
        Resource = "arn:aws:s3:::*"
      },
      {
        Sid    = "S3BucketActions"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:Get*",
          "s3:PutBucketPublicAccessBlock",
          "s3:PutBucketPolicy"
        ]
        Resource = [
          "arn:aws:s3:::*"
        ]
      },
      {
        Sid    = "CloudFrontListActions"
        Effect = "Allow"
        Action = [
          "cloudfront:ListDistributions"
        ]
        Resource = "arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/*"
      },
      {
        Sid    = "CloudFrontDistributionActions"
        Effect = "Allow"
        Action = [
          "cloudfront:GetDistribution",
          "cloudfront:GetDistributionConfig"
        ]
        Resource = "arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/*"
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name      = "CloudCustodianComputeNetworkPolicy"
      terraform = "True"
      oid-owned = "True"
    }
  )
}

# IAM Policy 2 - Cloud Custodian IAM and security permissions
resource "aws_iam_policy" "custodian_iam_security" {
  name        = "CloudCustodianIAMSecurityPolicy"
  description = "Permissions for Cloud Custodian IAM and security services"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "IAMReadOnly"
        Effect = "Allow"
        Action = [
          "iam:ListUsers",
          "iam:ListRoles",
          "iam:ListPolicies",
          "iam:ListGroups",
          "iam:ListAccessKeys",
          "iam:GetUser",
          "iam:GetRole",
          "iam:GetGroup",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListAttachedUserPolicies",
          "iam:ListAttachedRolePolicies",
          "iam:ListAttachedGroupPolicies",
          "iam:ListUserPolicies",
          "iam:ListRolePolicies",
          "iam:ListGroupPolicies",
          "iam:ListGroupsForUser"
        ]
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:group/*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/*",
          "arn:aws:iam::aws:policy/*"
        ]
      },
      {
        Sid    = "IAMSimulation"
        Effect = "Allow"
        Action = [
          "iam:SimulatePrincipalPolicy",
          "iam:SimulateCustomPolicy"
        ]
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*"
        ]
      },
      {
        Sid    = "IAMListAccountAliasesNoResourceSupport"
        Effect = "Allow"
        Action = [
          "iam:ListAccountAliases"
        ]
        Resource = "*"
        # Note: ListAccountAliases does not support resource-level permissions per AWS documentation
      },
      {
        Sid    = "IAMCredentialReport"
        Effect = "Allow"
        Action = [
          "iam:GetCredentialReport",
          "iam:GenerateCredentialReport"
        ]
        Resource = "*"
        # Note: These actions do not support resource-level permissions per AWS documentation
      },
      {
        Sid    = "IAMServiceLastAccessed"
        Effect = "Allow"
        Action = [
          "iam:GenerateServiceLastAccessedDetails",
          "iam:GetServiceLastAccessedDetails"
        ]
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:group/*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/*"
        ]
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
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*"
        ]
        Condition = {
          StringNotEquals = {
            "iam:ResourceTag/Protected" = "true"
          }
        }
      },
      {
        Sid    = "ResourceGroupsTaggingAPIRead"
        Effect = "Allow"
        Action = [
          "tag:GetResources",
          "tag:GetTagKeys",
          "tag:GetTagValues"
        ]
        Resource = "*"  # Resource Groups Tagging API actions don't support resource-level permissions
      },
      {
        Sid    = "ResourceGroupsTaggingAPIWrite"
        Effect = "Allow"
        Action = [
          "tag:TagResources",
          "tag:UntagResources"
        ]
        Resource = "*"  # Resource Groups Tagging API actions don't support resource-level permissions
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.aws_region
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
        Resource = [
          "arn:aws:securityhub:${var.aws_region}:${data.aws_caller_identity.current.account_id}:hub/default",
          "arn:aws:securityhub:${var.aws_region}:${data.aws_caller_identity.current.account_id}:finding-aggregator/*"
        ]
      },
      {
        Sid    = "SecurityHubUpdate"
        Effect = "Allow"
        Action = [
          "securityhub:BatchUpdateFindings"
        ]
        Resource = "arn:aws:securityhub:${var.aws_region}:${data.aws_caller_identity.current.account_id}:hub/default"
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
        Resource = [
          "arn:aws:guardduty:${var.aws_region}:${data.aws_caller_identity.current.account_id}:detector/*"
        ]
      },
      {
        Sid    = "ConfigRead"
        Effect = "Allow"
        Action = [
          "config:DescribeConfigRules",
          "config:DescribeComplianceByConfigRule",
          "config:GetComplianceDetailsByConfigRule"
        ]
        Resource = [
          "arn:aws:config:${var.aws_region}:${data.aws_caller_identity.current.account_id}:config-rule/*"
        ]
      },
      {
        Sid    = "CloudWatchLogsRead"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:*"
      },
      {
        Sid    = "CloudWatchLogsWrite"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/cloud-custodian/*"
      },
      {
        Sid    = "CloudWatchMetrics"
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricData"
        ]
        Resource = "arn:aws:cloudwatch:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Sid    = "HealthAPI"
        Effect = "Allow"
        Action = [
          "health:DescribeEvents",
          "health:DescribeEventDetails",
          "health:DescribeAffectedEntities"
        ]
        Resource = "arn:aws:health:*:*:event/*/*"
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name      = "CloudCustodianIAMSecurityPolicy"
      terraform = "True"
      oid-owned = "True"
    }
  )
}

# IAM Policy 3 - Cloud Custodian container and database permissions (ECS, EKS, Lambda, RDS)
resource "aws_iam_policy" "custodian_container_database" {
  name        = "CloudCustodianContainerDatabasePolicy"
  description = "Permissions for Cloud Custodian container and database resources"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECSActions"
        Effect = "Allow"
        Action = [
          "ecs:List*",
          "ecs:Describe*",
          "ecs:UpdateService",
          "ecs:StopTask",
          "ecs:TagResource",
          "ecs:UntagResource"
        ]
        Resource = "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Sid    = "EKSActions"
        Effect = "Allow"
        Action = [
          "eks:List*",
          "eks:Describe*",
          "eks:UpdateClusterConfig",
          "eks:UpdateClusterVersion",
          "eks:UpdateNodegroupConfig",
          "eks:TagResource",
          "eks:UntagResource"
        ]
        Resource = "arn:aws:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Sid    = "ECRActions"
        Effect = "Allow"
        Action = [
          "ecr:Describe*",
          "ecr:List*",
          "ecr:Get*",
          "ecr:SetRepositoryPolicy",
          "ecr:DeleteRepositoryPolicy",
          "ecr:Put*",
          "ecr:TagResource",
          "ecr:UntagResource"
        ]
        Resource = "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/*"
      },
      {
        Sid    = "ElastiCacheActions"
        Effect = "Allow"
        Action = [
          "elasticache:Describe*",
          "elasticache:ListTagsForResource",
          "elasticache:Modify*",
          "elasticache:AddTagsToResource",
          "elasticache:RemoveTagsFromResource",
          "elasticache:DeleteCacheCluster",
          "elasticache:DeleteReplicationGroup"
        ]
        Resource = "arn:aws:elasticache:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Sid    = "EFSActions"
        Effect = "Allow"
        Action = [
          "elasticfilesystem:Describe*",
          "elasticfilesystem:PutFileSystemPolicy",
          "elasticfilesystem:DeleteFileSystemPolicy",
          "elasticfilesystem:TagResource",
          "elasticfilesystem:UntagResource",
          "elasticfilesystem:DeleteFileSystem"
        ]
        Resource = "arn:aws:elasticfilesystem:${var.aws_region}:${data.aws_caller_identity.current.account_id}:file-system/*"
      },
      {
        Sid    = "KinesisActions"
        Effect = "Allow"
        Action = [
          "kinesis:Describe*",
          "kinesis:ListStreams",
          "kinesis:ListTagsForStream",
          "kinesis:StartStreamEncryption",
          "kinesis:StopStreamEncryption",
          "kinesis:AddTagsToStream",
          "kinesis:RemoveTagsFromStream",
          "kinesis:DeleteStream"
        ]
        Resource = "arn:aws:kinesis:${var.aws_region}:${data.aws_caller_identity.current.account_id}:stream/*"
      },
      {
        Sid    = "SNSActions"
        Effect = "Allow"
        Action = [
          "sns:ListTopics",
          "sns:GetTopicAttributes",
          "sns:ListTagsForResource",
          "sns:SetTopicAttributes",
          "sns:TagResource",
          "sns:UntagResource",
          "sns:DeleteTopic"
        ]
        Resource = "arn:aws:sns:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Sid    = "LambdaActions"
        Effect = "Allow"
        Action = [
          "lambda:List*",
          "lambda:Get*",
          "lambda:UpdateFunctionConfiguration",
          "lambda:UpdateFunctionCode",
          "lambda:TagResource",
          "lambda:UntagResource",
          "lambda:DeleteFunction",
          "lambda:PutFunctionConcurrency"
        ]
        Resource = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Sid    = "RDSActions"
        Effect = "Allow"
        Action = [
          "rds:Describe*",
          "rds:ListTagsForResource",
          "rds:ModifyDBInstance",
          "rds:ModifyDBCluster",
          "rds:StopDBInstance",
          "rds:StopDBCluster",
          "rds:DeleteDBInstance",
          "rds:DeleteDBCluster",
          "rds:AddTagsToResource",
          "rds:RemoveTagsFromResource"
        ]
        Resource = "arn:aws:rds:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Sid    = "SQSNotificationQueues"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueUrl",
          "sqs:GetQueueAttributes"
        ]
        Resource = "arn:aws:sqs:*:172327596604:aikyam-cloud-custodian-*-notifications"
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name      = "CloudCustodianContainerDatabasePolicy"
      terraform = "True"
      oid-owned = "True"
    }
  )
}

# Attach all policies to execution role
resource "aws_iam_role_policy_attachment" "custodian_compute_network" {
  role       = aws_iam_role.custodian_execution.name
  policy_arn = aws_iam_policy.custodian_compute_network.arn
}

resource "aws_iam_role_policy_attachment" "custodian_iam_security" {
  role       = aws_iam_role.custodian_execution.name
  policy_arn = aws_iam_policy.custodian_iam_security.arn
}

resource "aws_iam_role_policy_attachment" "custodian_container_database" {
  role       = aws_iam_role.custodian_execution.name
  policy_arn = aws_iam_policy.custodian_container_database.arn
}

# ============================================================================
# CloudWatch Resources
# ============================================================================

# Optional: CloudWatch Log Group for local logging
resource "aws_cloudwatch_log_group" "custodian_local" {
  count             = var.create_local_log_group ? 1 : 0
  name              = "/aws/cloud-custodian/${var.environment}"
  retention_in_days = var.log_retention_days

  tags = merge(
    var.tags,
    {
      Name      = "cloud-custodian-logs"
      terraform = "True"
      oid-owned = "True"
    }
  )
}

# ============================================================================
# Outputs
# ============================================================================

output "account_id" {
  description = "AWS account ID of this member account"
  value       = data.aws_caller_identity.current.account_id
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule forwarding events to central account"
  value       = aws_cloudwatch_event_rule.forward_security_events_to_central.arn
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.forward_security_events_to_central.name
}

output "eventbridge_role_arn" {
  description = "ARN of the IAM role used by EventBridge for cross-account forwarding"
  value       = aws_iam_role.eventbridge_cross_account.arn
}

output "custodian_execution_role_arn" {
  description = "ARN of the Cloud Custodian execution role (to be assumed by central account)"
  value       = aws_iam_role.custodian_execution.arn
}

output "custodian_execution_role_name" {
  description = "Name of the Cloud Custodian execution role"
  value       = aws_iam_role.custodian_execution.name
}

output "external_id" {
  description = "External ID to use when assuming the Cloud Custodian execution role"
  value       = "cloud-custodian-${data.aws_caller_identity.current.account_id}"
}

output "remediation_policy_arns" {
  description = "ARNs of the IAM policies granting remediation permissions"
  value = {
    compute_network     = aws_iam_policy.custodian_compute_network.arn
    iam_security        = aws_iam_policy.custodian_iam_security.arn
    container_database  = aws_iam_policy.custodian_container_database.arn
  }
}

output "deployment_summary" {
  description = "Summary of deployed resources"
  value       = <<-EOT
    Member account setup complete for account: ${data.aws_caller_identity.current.account_id}
    
    Configuration:
    - EventBridge Rule: ${aws_cloudwatch_event_rule.forward_security_events_to_central.name}
    - Events forwarded to: ${var.central_event_bus_arn}
    - Execution Role: ${aws_iam_role.custodian_execution.arn}
    - External ID: cloud-custodian-${data.aws_caller_identity.current.account_id}
    
    Next steps:
    1. Add this account ID (${data.aws_caller_identity.current.account_id}) to the central account's policy mapping
    2. Upload/update account-policy-mapping.json in central account's S3 bucket
    3. Test event forwarding:
       aws events put-events --entries '[{"Source":"aws.ec2","DetailType":"Test Event","Detail":"{}"}]'
    4. Check central account Lambda logs for event processing
  EOT
}

output "test_assume_role_command" {
  description = "Command to test assuming the execution role from central account"
  value       = <<-EOT
    aws sts assume-role \
      --role-arn ${aws_iam_role.custodian_execution.arn} \
      --role-session-name test-session \
      --external-id cloud-custodian-${data.aws_caller_identity.current.account_id}
  EOT
}
