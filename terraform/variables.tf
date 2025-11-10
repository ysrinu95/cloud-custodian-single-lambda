variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "cloud-custodian"
}

variable "lambda_execution_mode" {
  description = "Lambda execution mode: 'native' (library) or 'cli' (subprocess)"
  type        = string
  default     = "native"
  
  validation {
    condition     = contains(["native", "cli"], var.lambda_execution_mode)
    error_message = "Lambda execution mode must be either 'native' or 'cli'"
  }
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 300
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 512
}

variable "policy_bucket" {
  description = "S3 bucket containing Cloud Custodian policy files and policy mapping configuration"
  type        = string
  default     = ""
}

variable "policy_mapping_key" {
  description = "S3 key for policy mapping JSON file"
  type        = string
  default     = "config/policy-mapping.json"
}

variable "policy_mapping_key" {
  description = "S3 key for policy mapping JSON file"
  type        = string
  default     = "config/policy-mapping.json"
}

variable "policy_path" {
  description = "Path to policy file in Lambda package"
  type        = string
  default     = "/var/task/policies/sample-policies.yml"
}

variable "custodian_layer_arn" {
  description = "ARN of the Cloud Custodian Lambda layer (will be created if not provided)"
  type        = string
  default     = ""
}

variable "enable_eventbridge_rule" {
  description = "Enable EventBridge rule for S3 CloudTrail events"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention period in days"
  type        = number
  default     = 7
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}
