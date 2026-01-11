# Cloud Custodian Lambda Function Source

This directory contains the source code for the Cloud Custodian Lambda function.

## Files

- **lambda_native.py** - Main Lambda handler for Cloud Custodian event processing
- **validator.py** - Policy validation logic
- **policy_executor.py** - Policy execution logic

## Migration

These files were moved from `c7n/src/` to this location on November 11, 2025 to consolidate all Lambda-related code under the `terraform/ad-hoc/lambda_functions/` directory structure.

## Build Process

The Lambda function is built automatically during Terraform deployment via the `null_resource.lambda_function_build` resource in `cloud-custodian.tf`. The build process:

1. Copies these Python files to a temporary build directory
2. Packages them into `lambda-function.zip`
3. The zip file is then used by the `aws_lambda_function.custodian` resource

## Deployment

The Lambda function is deployed as part of the Cloud Custodian infrastructure via:
```bash
# Via Jenkins adhoc.groovy pipeline
configpath: dev/platform/cloud-custodian
action: apply
```

## Related Resources

- Layer requirements: `../c7n-layer/requirements.txt`
- Terraform configuration: `../../dev/platform/cloud-custodian/cloud-custodian.tf`
- Policies (uploaded to S3): `../../../../c7n/policies/`
- Config (uploaded to S3): `../../../../c7n/config/policy-mapping.json`
