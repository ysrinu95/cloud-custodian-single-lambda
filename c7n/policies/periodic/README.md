# Cloud Custodian Periodic Policies

This directory contains Cloud Custodian policies that are executed on a periodic schedule via GitHub Actions workflow.

## 📋 Overview

Periodic policies are used for:
- **Compliance scanning** - Regular compliance checks across AWS resources
- **Resource inventory** - Tracking resource usage and configurations
- **Security audits** - Scheduled security posture assessments
- **Cost optimization** - Identifying unused or underutilized resources
- **Drift detection** - Monitoring configuration changes over time

## 🗂️ Policy Files

| Policy File | Description | Resources Covered |
|-------------|-------------|-------------------|
| `account.yml` | Account-level settings and configurations | AWS Account |
| `cloudwatch.yml` | CloudWatch logs and metrics monitoring | CloudWatch Logs, Alarms |
| `ec2.yml` | EC2 instances compliance and security | EC2 Instances |
| `ecs.yml` | ECS containers and tasks monitoring | ECS Services, Tasks |
| `eks.yml` | EKS clusters security and compliance | EKS Clusters |
| `elasticache.yml` | ElastiCache security configurations | ElastiCache Clusters |
| `guardduty.yml` | GuardDuty findings and configuration | GuardDuty |
| `iam.yml` | IAM users, roles, and policies audit | IAM Users, Roles, Policies |
| `lambda.yml` | Lambda functions security and config | Lambda Functions |
| `lb.yml` | Load balancers security and configuration | ALB, NLB, CLB |
| `rds.yml` | RDS databases security and compliance | RDS Instances, Clusters |
| `s3.yml` | S3 buckets security and compliance | S3 Buckets |
| `securityhub.yml` | Security Hub findings management | Security Hub |
| `aws-cloudfront-security.yml` | CloudFront distributions security | CloudFront |

## ⚙️ Execution Schedule

The periodic policies are executed via the GitHub Actions workflow: `.github/workflows/run-periodic-policies.yml`

### Automatic Schedules:
- **Daily at 6 AM UTC** - All periodic policies across all resources
- **Every 6 hours** - Critical policies only (S3, IAM, Security Hub)

### Manual Execution:
You can trigger the workflow manually via GitHub Actions UI with options:
- **Account ID** - Target AWS account to scan
- **Policy File** - Specific policy file to run (or "all")
- **Dry Run** - Preview mode without executing actions
- **Regions** - AWS regions to scan (comma-separated or "all")

## 🚀 Usage

### Running All Policies

```bash
# Via GitHub Actions UI
# Go to Actions → Run Cloud Custodian Periodic Policies → Run workflow
# Leave all inputs at default to run all policies
```

### Running Specific Policy

```bash
# Via GitHub Actions UI
# Go to Actions → Run Cloud Custodian Periodic Policies → Run workflow
# Set "Specific policy file" to: s3.yml
```

### Dry Run Mode

```bash
# Via GitHub Actions UI
# Enable "Dry run mode" checkbox
# This will scan resources but NOT execute any actions
```

### Multi-Region Execution

```bash
# Via GitHub Actions UI
# Set "AWS regions" to: us-east-1,us-west-2,eu-west-1
# Or set to "all" for all major regions
```

## 📊 Output and Results

### Artifacts
After execution, the workflow generates artifacts containing:
- `resources.json` - List of resources found by each policy
- `execution.log` - Detailed execution logs
- Policy-specific outputs organized by region and policy name

### GitHub Summary
The workflow generates a comprehensive summary showing:
- ✅ Successful policy executions
- ❌ Failed policy executions
- 📦 Total resources found
- Per-region and per-policy breakdown

### Notifications
Policy execution results are sent via:
- **SQS Queue** - `aikyam-cloud-custodian-periodic-notifications`
- **Email** - Configured in policy files (ysrinu95@gmail.com)
- **Security Hub** - Findings posted for failed compliance checks

## 📝 Policy Structure

Each periodic policy file follows this structure:

```yaml
vars:
  email-notify: &email-notify
    template: default.html
    priority_header: "1"
    from: ysrinu95@gmail.com
    to:
      - ysrinu95@gmail.com
    transport:
      type: sqs
      queue: https://sqs.us-east-1.amazonaws.com/172327596604/aikyam-cloud-custodian-periodic-notifications

policies:
  - name: policy-name
    resource: aws.resource-type
    description: |
      Policy description
    filters:
      - type: filter-type
        # filter configuration
    actions:
      - type: notify
        <<: *email-notify
        subject: "Alert subject"
        violation_desc: "Violation description"
```

## 🔧 Adding New Policies

1. Create a new YAML file in this directory
2. Follow the structure above
3. Test locally:
   ```bash
   custodian run -s output/test --dryrun policies/periodic/your-policy.yml
   ```
4. Validate syntax:
   ```bash
   custodian validate policies/periodic/your-policy.yml
   ```
5. Commit and push - will be included in next scheduled run

## 🛡️ Best Practices

### Resource Filtering
- Use `conditions` to limit policies to specific regions
- Add `filters` to target specific resource configurations
- Use tags to exclude test/dev resources

### Actions
- **Notify** - Always notify before taking destructive actions
- **Post-finding** - Create Security Hub findings for audit trail
- **Mark-for-op** - Tag resources for future cleanup instead of immediate deletion

### Performance
- Avoid overly broad filters that scan entire account
- Use `cache-period` to reduce API calls
- Limit policies to relevant regions using `conditions`

### Testing
- Always test with `--dryrun` first
- Start with notify-only actions
- Gradually add remediation actions after validation

## 📖 Documentation

- [Cloud Custodian Documentation](https://cloudcustodian.io/docs/)
- [AWS Resource Filters](https://cloudcustodian.io/docs/aws/resources/index.html)
- [Policy Actions Reference](https://cloudcustodian.io/docs/aws/policy/actions.html)
- [Notification Configuration](https://cloudcustodian.io/docs/tools/c7n-mailer.html)

## 🔍 Monitoring and Troubleshooting

### View Execution Results
1. Go to GitHub Actions → Run Cloud Custodian Periodic Policies
2. Click on latest workflow run
3. View execution summary and download artifacts

### CloudWatch Logs
```bash
aws logs tail /aws/lambda/cloud-custodian --follow
```

### Security Hub Findings
```bash
aws securityhub get-findings \
  --filters '{"ProductName": [{"Value": "Cloud Custodian", "Comparison": "EQUALS"}]}'
```

### SQS Messages
```bash
aws sqs receive-message \
  --queue-url https://sqs.us-east-1.amazonaws.com/172327596604/aikyam-cloud-custodian-periodic-notifications
```

## 🚨 Common Issues

### Policy Fails with Permission Error
- Ensure `CloudCustodianExecutionRole` has required permissions
- Check IAM policy for resource-specific permissions

### No Resources Found
- Verify resources exist in target region
- Check filter conditions aren't too restrictive
- Use `--verbose` flag for debugging

### Notifications Not Received
- Verify SQS queue permissions
- Check c7n-mailer is running
- Validate email configuration in policy

## 📞 Support

For issues or questions:
- Create an issue in the repository
- Review Cloud Custodian documentation
- Check workflow execution logs in GitHub Actions
