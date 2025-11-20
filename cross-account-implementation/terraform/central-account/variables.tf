variable "aws_region" {
  description = "AWS region for central account resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "member_account_ids" {
  description = "List of AWS member account IDs that will send events"
  type        = list(string)
  validation {
    condition     = length(var.member_account_ids) > 0
    error_message = "At least one member account ID must be provided."
  }
}

variable "policy_bucket" {
  description = "S3 bucket name for storing Cloud Custodian policies"
  type        = string
}

variable "create_policy_bucket" {
  description = "Whether to create the S3 policy bucket (set to false if bucket already exists)"
  type        = bool
  default     = true
}

variable "lambda_package_path" {
  description = "Path to the Lambda deployment package (zip file)"
  type        = string
  default     = "lambda-function.zip"
}

variable "lambda_layer_path" {
  description = "Path to the Lambda layer package (zip file with Cloud Custodian)"
  type        = string
  default     = ""
}

variable "custodian_version" {
  description = "Cloud Custodian version for layer description"
  type        = string
  default     = "0.9.30"
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 900
  validation {
    condition     = var.lambda_timeout >= 60 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 60 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 512
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "log_level" {
  description = "Logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL)"
  type        = string
  default     = "INFO"
  validation {
    condition     = contains(["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"], var.log_level)
    error_message = "Log level must be one of: DEBUG, INFO, WARNING, ERROR, CRITICAL."
  }
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention value."
  }
}

variable "create_notification_queue" {
  description = "Whether to create SQS queue for notifications"
  type        = bool
  default     = false
}

variable "notification_queue_arn" {
  description = "ARN of existing SQS queue for notifications (if not creating new one)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
