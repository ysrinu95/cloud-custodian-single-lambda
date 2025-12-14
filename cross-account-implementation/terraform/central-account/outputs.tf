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
  value       = var.lambda_layer_path != "" ? aws_lambda_layer_version.custodian_layer[0].arn : "N/A - Layer not created"
}

output "lambda_layer_version" {
  description = "Version of the Cloud Custodian Lambda layer (if created)"
  value       = var.lambda_layer_path != "" ? aws_lambda_layer_version.custodian_layer[0].version : "N/A"
}

output "policy_bucket_name" {
  description = "Name of the S3 bucket for policies"
  value       = var.policy_bucket
}

output "policy_bucket_arn" {
  description = "ARN of the S3 bucket for policies (if created)"
  value       = var.create_policy_bucket ? aws_s3_bucket.policies[0].arn : "N/A - Bucket not created by this module"
}

output "sqs_queue_url" {
  description = "URL of the SQS queue for Cloud Custodian notifications"
  value       = aws_sqs_queue.custodian_mailer.url
}

output "sqs_queue_arn" {
  description = "ARN of the SQS queue for Cloud Custodian notifications"
  value       = aws_sqs_queue.custodian_mailer.arn
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for notifications"
  value       = aws_sns_topic.custodian_notifications.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for notifications"
  value       = aws_sns_topic.custodian_notifications.name
}

output "mailer_lambda_function_name" {
  description = "Name of the mailer Lambda function"
  value       = aws_lambda_function.custodian_mailer.function_name
}

output "notification_email" {
  description = "Email address subscribed to SNS notifications"
  value       = var.notification_email
}

output "member_account_ids" {
  description = "List of member account IDs configured"
  value       = var.member_account_ids
}

output "deployment_instructions" {
  description = "Next steps for deployment"
  value       = <<-EOT
    Central account infrastructure deployed successfully!
    
    Next steps:
    1. ⚠️  CONFIRM EMAIL SUBSCRIPTION: Check ${var.notification_email} inbox and confirm SNS subscription
    2. Note the Event Bus ARN: ${aws_cloudwatch_event_bus.centralized.arn}
    3. Note the SQS Queue URL: ${aws_sqs_queue.custodian_mailer.url}
    4. Note the SNS Topic ARN: ${aws_sns_topic.custodian_notifications.arn}
    5. Deploy member account infrastructure using terraform/member-account/
    6. Upload policies to S3: aws s3 cp policies/ s3://${var.policy_bucket}/policies/ --recursive
    7. Upload account mapping: aws s3 cp config/account-policy-mapping.json s3://${var.policy_bucket}/config/
    8. Test event forwarding from a member account
    
    Lambda Functions:
    - Executor: ${aws_lambda_function.custodian_cross_account_executor.function_name}
    - Mailer: ${aws_lambda_function.custodian_mailer.function_name}
    
    CloudWatch Logs:
    - Executor: ${aws_cloudwatch_log_group.lambda_logs.name}
    - Mailer: ${aws_cloudwatch_log_group.mailer_logs.name}
    
    Notification Flow:
    Policy Execution → SQS Queue → Mailer Lambda → SNS Topic → Email (${var.notification_email})
  EOT
}
