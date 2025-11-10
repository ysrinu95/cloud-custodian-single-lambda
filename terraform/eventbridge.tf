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

# Optional: Additional EventBridge rules for specific triggers
# Uncomment and customize as needed

# Example: Trigger on EC2 instance state change
# resource "aws_cloudwatch_event_rule" "ec2_state_change" {
#   name        = "${var.project_name}-ec2-state-change-${var.environment}"
#   description = "Trigger on EC2 instance state change"
#
#   event_pattern = jsonencode({
#     source      = ["aws.ec2"]
#     detail-type = ["EC2 Instance State-change Notification"]
#     detail = {
#       state = ["running"]
#     }
#   })
# }
#
# resource "aws_cloudwatch_event_target" "ec2_lambda_target" {
#   rule      = aws_cloudwatch_event_rule.ec2_state_change.name
#   target_id = "CloudCustodianLambdaEC2"
#   arn       = aws_lambda_function.custodian.arn
#
#   input = jsonencode({
#     policy_source = "file"
#     policy_path   = "/var/task/policies/ec2-policy.yml"
#   })
# }
#
# resource "aws_lambda_permission" "allow_eventbridge_ec2" {
#   statement_id  = "AllowExecutionFromEventBridgeEC2"
#   action        = "lambda:InvokeFunction"
#   function_name = aws_lambda_function.custodian.function_name
#   principal     = "events.amazonaws.com"
#   source_arn    = aws_cloudwatch_event_rule.ec2_state_change.arn
# }
