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

output "notification_queue_url" {
  description = "URL of the SQS notification queue (if created)"
  value       = var.create_notification_queue ? aws_sqs_queue.notifications[0].url : "N/A - Queue not created"
}

output "notification_queue_arn" {
  description = "ARN of the SQS notification queue (if created)"
  value       = var.create_notification_queue ? aws_sqs_queue.notifications[0].arn : "N/A - Queue not created"
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
    1. Note the Event Bus ARN: ${aws_cloudwatch_event_bus.centralized.arn}
    2. Deploy member account infrastructure using terraform/member-account/
    3. Upload policies to S3: aws s3 cp policies/ s3://${var.policy_bucket}/policies/ --recursive
    4. Upload account mapping: aws s3 cp config/account-policy-mapping.json s3://${var.policy_bucket}/config/
    5. Test event forwarding from a member account
    
    Lambda Function: ${aws_lambda_function.custodian_cross_account_executor.function_name}
    CloudWatch Logs: ${aws_cloudwatch_log_group.lambda_logs.name}
  EOT
}
