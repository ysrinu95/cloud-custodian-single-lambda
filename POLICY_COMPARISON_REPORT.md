# Policy Comparison Report

## Summary

**Comparison Date:** January 14, 2026

### Files Compared:
1. **CloudCustodian_Policies.txt** - Contains 78 unique Cloud Custodian policies
2. **prisma-cloud-aws-policies.csv** - Contains 455 Prisma Cloud AWS policies

### Comparison Results:
- **Total Prisma Cloud Policies:** 455
- **Matched Policies:** 168 (37%)
- **Non-Matched Policies:** 287 (63%)

## What Was Done:

1. **Read and Parsed** both policy files:
   - Extracted policy names from CloudCustodian_Policies.txt
   - Loaded all policies from prisma-cloud-aws-policies.csv

2. **Comparison Logic:**
   - Compared policies based on AWS service keywords (s3, rds, ebs, ec2, iam, eks, elb, cloudfront, security group, encryption, public, kms, ssl, tls, snapshot, cloudtrail, cloudwatch, elasticsearch, redshift, kinesis, lambda, sns, sqs, waf, elasticache, guardduty, acl, vpc, ami, emr, neptune)
   - Considered policies as "matched" if they:
     - Share common AWS service keywords
     - Have 3 or more significant words in common

3. **Output Generated:**
   - **prisma-cloud-aws-policies.csv** - Main comparison file with separate columns
   - **policy-comparison-detailed.csv** - Detailed comparison (same as main file)
   - **non-matched-policies.csv** - Only non-matched policies for easy review
   - **prisma-cloud-aws-policies.csv.backup** - Backup of original file

## File Structure:

### Main Comparison File (prisma-cloud-aws-policies.csv)

The file now has the following columns:

| Column | Description |
|--------|-------------|
| **Cloud_Custodian_Policy** | Matching Cloud Custodian policy name (empty if no match) |
| **Prisma_Cloud_Policy** | Prisma Cloud policy name |
| **Matched** | TRUE/FALSE flag indicating if policies match |
| **Severity** | Severity level (CRITICAL, HIGH, MEDIUM, LOW, INFO) |
| **Category** | Policy category (e.g., AWS IAM Policies, AWS S3 Policies) |
| **Checkov_ID** | Checkov compliance check ID |

### Example Rows:

#### Matched Policy Example:
```csv
Cloud_Custodian_Policy,Prisma_Cloud_Policy,Matched,Severity,Category,Checkov_ID
"AWS S3 bucket has global view ACL permissions enabled- realtime/periodic","Bucket ACL grants WRITE permission to AWS users",TRUE,CRITICAL,AWS S3 Policies,Unknown ID
```

#### Non-Matched Policy Example:
```csv
Cloud_Custodian_Policy,Prisma_Cloud_Policy,Matched,Severity,Category,Checkov_ID
,"AWS Access key enabled on root account",FALSE,HIGH,AWS IAM Policies,CKV_AWS_348
```

## Key Insights:

### Matched Policies (168):
These are Prisma Cloud policies that have similar counterparts in the Cloud Custodian policies. The matching Cloud Custodian policy name is shown in the first column. Examples include:
- S3 bucket security policies
- EBS encryption policies  
- Security group policies
- RDS public access policies
- EC2 metadata service policies

### Non-Matched Policies (287):
These Prisma Cloud policies don't have clear matches in the Cloud Custodian policy set (Cloud_Custodian_Policy column is empty, Matched = FALSE). They include:
- Granular IAM policy checks
- Specific compliance requirements (Checkov)
- Additional encryption configurations
- Newer AWS services or features
- Configuration-specific checks (retention periods, version checks)
- Resource tagging policies
- Logging and monitoring configurations

## How to Use These Files:

### 1. Main Comparison File (prisma-cloud-aws-policies.csv)
- **Filter by Matched = TRUE**: See which Prisma policies have Cloud Custodian equivalents
- **Filter by Matched = FALSE**: Identify gaps in Cloud Custodian coverage
- **Filter by Severity**: Prioritize critical/high severity gaps
- **Sort by Category**: Group policies by AWS service

### 2. Non-Matched Policies Only (non-matched-policies.csv)
- Quick reference for policies needing implementation
- Useful for gap analysis
- Planning new Cloud Custodian policies

## Files Modified:

1. **[c7n/policies/prisma-cloud-aws-policies.csv](c7n/policies/prisma-cloud-aws-policies.csv)** - Main comparison file with all data and columns
2. **[c7n/policies/policy-comparison-detailed.csv](c7n/policies/policy-comparison-detailed.csv)** - Duplicate of main file
3. **[c7n/policies/non-matched-policies.csv](c7n/policies/non-matched-policies.csv)** - Filtered view of non-matched policies only
4. **[c7n/policies/prisma-cloud-aws-policies.csv.backup](c7n/policies/prisma-cloud-aws-policies.csv.backup)** - Backup of original file

## Statistics by Severity:

To see distribution by severity, open the CSV and create a pivot table or use:
```bash
# Count matched by severity
grep "TRUE" prisma-cloud-aws-policies.csv | cut -d',' -f4 | sort | uniq -c

# Count non-matched by severity
grep "FALSE" prisma-cloud-aws-policies.csv | cut -d',' -f4 | sort | uniq -c
```

## Next Steps:

1. **Review High/Critical Non-Matched Policies**: Focus on implementing Cloud Custodian versions of high-severity gaps
2. **Validate Matches**: Review the matched policies to ensure the comparison logic correctly identified similar policies
3. **Create New Policies**: Use the non-matched list to plan new Cloud Custodian policy development
4. **Excel Analysis**: Open in Excel/Google Sheets for advanced filtering, pivot tables, and visualization

