variable "aws_region" {
  description = "AWS region for this member account"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name for this member account (e.g., production, development, staging)"
  type        = string
  default     = "prod"
}

variable "central_account_id" {
  description = "AWS account ID of the central security account"
  type        = string
  validation {
    condition     = can(regex("^\\d{12}$", var.central_account_id))
    error_message = "Central account ID must be a 12-digit AWS account ID."
  }
}

variable "central_environment" {
  description = "Environment name used in the central account (must match central account setup)"
  type        = string
  default     = "prod"
}

variable "central_event_bus_arn" {
  description = "ARN of the EventBridge custom bus in the central account"
  type        = string
  validation {
    condition     = can(regex("^arn:aws:events:[a-z0-9-]+:\\d{12}:event-bus/", var.central_event_bus_arn))
    error_message = "Central event bus ARN must be a valid EventBridge ARN."
  }
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
  default     = {}
}
