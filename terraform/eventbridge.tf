# EventBridge Rule for S3 bucket events via CloudTrail

resource "aws_cloudwatch_event_rule" "custodian_s3_events" {
  count = var.enable_eventbridge_rule ? 1 : 0

  name        = "${var.project_name}-s3-events-${var.environment}"
  description = "Trigger Cloud Custodian Lambda on S3 bucket creation or configuration changes"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["s3.amazonaws.com"]
      eventName = [
        "CreateBucket",
        "PutBucketAcl",
        "PutBucketPolicy",
        "PutBucketPublicAccessBlock",
        "DeleteBucketPublicAccessBlock",
        "PutBucketCors",
        "PutBucketWebsite"
      ]
    }
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-s3-events-${var.environment}"
    }
  )
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  count = var.enable_eventbridge_rule ? 1 : 0

  rule      = aws_cloudwatch_event_rule.custodian_s3_events[0].name
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
  source_arn    = aws_cloudwatch_event_rule.custodian_s3_events[0].arn
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
