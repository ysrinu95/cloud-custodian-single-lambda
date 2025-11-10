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

# Optional: Additional policy for specific resources
# Uncomment and customize as needed

# resource "aws_iam_policy" "custodian_additional_policy" {
#   name        = "${var.project_name}-custodian-additional-${var.environment}"
#   description = "Additional permissions for Cloud Custodian"
#
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Action = [
#           "organizations:ListAccounts",
#           "organizations:DescribeAccount"
#         ]
#         Resource = "*"
#       }
#     ]
#   })
# }
#
# resource "aws_iam_role_policy_attachment" "lambda_additional_policy" {
#   role       = aws_iam_role.lambda_role.name
#   policy_arn = aws_iam_policy.custodian_additional_policy.arn
# }
