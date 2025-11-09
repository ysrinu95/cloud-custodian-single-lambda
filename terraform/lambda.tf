# Lambda Layer for Cloud Custodian

resource "aws_lambda_layer_version" "custodian_layer" {
  count = var.custodian_layer_arn == "" ? 1 : 0

  filename            = "${path.module}/../layers/cloud-custodian-layer.zip"
  layer_name          = "${var.project_name}-layer-${var.environment}"
  compatible_runtimes = ["python3.11", "python3.12"]
  description         = "Cloud Custodian and dependencies"

  # This will be created by the build script or GitHub Actions
  source_code_hash = fileexists("${path.module}/../layers/cloud-custodian-layer.zip") ? filebase64sha256("${path.module}/../layers/cloud-custodian-layer.zip") : null

  lifecycle {
    create_before_destroy = true
  }
}

# Lambda Function

data "archive_file" "lambda_function" {
  type        = "zip"
  output_path = "${path.module}/../dist/lambda-function.zip"

  source {
    content  = file("${path.module}/../src/lambda_${var.lambda_execution_mode}.py")
    filename = "lambda_function.py"
  }

  # Include policies directory
  source {
    content  = file("${path.module}/../policies/sample-policies.yml")
    filename = "policies/sample-policies.yml"
  }

  source {
    content  = file("${path.module}/../policies/test-policy.yml")
    filename = "policies/test-policy.yml"
  }
}

resource "aws_lambda_function" "custodian" {
  filename         = data.archive_file.lambda_function.output_path
  function_name    = "${var.project_name}-executor-${var.environment}"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_function.output_base64sha256
  runtime          = "python3.11"
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size

  layers = [
    var.custodian_layer_arn != "" ? var.custodian_layer_arn : aws_lambda_layer_version.custodian_layer[0].arn
  ]

  environment {
    variables = {
      POLICY_PATH   = var.policy_path
      POLICY_BUCKET = var.policy_bucket
      POLICY_KEY    = var.policy_key
      LOG_GROUP     = aws_cloudwatch_log_group.lambda_logs.name
      ENVIRONMENT   = var.environment
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda_logs,
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_custodian_policy
  ]

  tags = merge(
    var.tags,
    {
      Name          = "${var.project_name}-executor-${var.environment}"
      ExecutionMode = var.lambda_execution_mode
    }
  )
}

# CloudWatch Log Group

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.project_name}-executor-${var.environment}"
  retention_in_days = var.log_retention_days

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-logs-${var.environment}"
    }
  )
}
