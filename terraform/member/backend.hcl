# Backend Configuration for Cloud Custodian Terraform State
# This file defines the S3 backend configuration for storing Terraform state

# Dev Environment Backend Config
bucket         = "ysr95-cloud-custodian-tf-bkt"
key            = "member/cloud-custodian/terraform.tfstate"
dynamodb_table = "terraform-state-lock"
encrypt        = true
region         = "us-east-1"
