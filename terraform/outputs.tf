output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.custodian.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.custodian.arn
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

output "lambda_layer_arn" {
  description = "ARN of the Cloud Custodian Lambda layer"
  value       = var.custodian_layer_arn != "" ? var.custodian_layer_arn : aws_lambda_layer_version.custodian_layer[0].arn
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule"
  value       = var.enable_eventbridge_rule ? aws_cloudwatch_event_rule.custodian_multi_resource_events[0].name : null
}

output "log_group_name" {
  description = "Name of the CloudWatch Log Group"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "execution_mode" {
  description = "Lambda execution mode (native or cli)"
  value       = var.lambda_execution_mode
}
