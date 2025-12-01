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

output "remediation_policy_arn" {
  description = "ARN of the IAM policy granting remediation permissions"
  value       = aws_iam_policy.custodian_remediation.arn
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
