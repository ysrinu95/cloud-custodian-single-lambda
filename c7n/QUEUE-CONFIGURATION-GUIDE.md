# Cloud Custodian Queue Configuration Guide

## Queue URLs

### Real-Time Queue (Event-Driven Policies)
```
https://sqs.us-east-1.amazonaws.com/172327596604/aikyam-cloud-custodian-realtime-notifications
```
**Use for:** Policies with `mode.type: cloudtrail` that trigger on AWS events

**Characteristics:**
- Immediate processing (sub-second)
- Processed by `cross-account-executor` Lambda
- Basic HTML formatting via `realtime_notifier.py`
- SNS notifications sent immediately

### Periodic Queue (Scheduled & Ad-Hoc Policies)
```
https://sqs.us-east-1.amazonaws.com/172327596604/aikyam-cloud-custodian-periodic-notifications
```
**Use for:** 
- Policies with `mode.type: periodic` (scheduled execution)
- Ad-hoc/manual policies (no mode defined)

**Characteristics:**
- Processed every 5 minutes by `mailer` Lambda
- Rich email formatting with Jinja2 templates
- 0-5 minute latency
- Full template variable rendering

## Decision Tree

```
Is your policy event-driven (mode.type: cloudtrail)?
│
├─ YES → Use REALTIME queue
│   └─ Benefits: Immediate alerts, sub-second latency
│
└─ NO → Use PERIODIC queue
    └─ Benefits: Rich email templates, batch efficiency
```

## Configuration Examples

### Real-Time Event-Driven Policy

```yaml
policies:
  - name: security-group-expose-port-22
    resource: security-group
    description: Alert immediately when SSH port is exposed to internet
    mode:
      type: cloudtrail
      events:
        - source: ec2.amazonaws.com
          event: AuthorizeSecurityGroupIngress
          ids: "requestParameters.groupId"
      role: arn:aws:iam::{account_id}:role/CloudCustodianExecutionRole
    filters:
      - type: ingress
        Cidr:
          value: "0.0.0.0/0"
        Ports: [22]
    actions:
      - type: notify
        transport:
          type: sqs
          queue: https://sqs.us-east-1.amazonaws.com/172327596604/aikyam-cloud-custodian-realtime-notifications
        subject: '[URGENT] Security Group Port 22 Exposed - {account_id}'
        to:
          - security-alerts@example.com
```

### Periodic Scheduled Policy

```yaml
policies:
  - name: s3-unencrypted-buckets-daily-report
    resource: s3
    description: Daily report of unencrypted S3 buckets
    mode:
      type: periodic
      schedule: "rate(1 day)"
      role: arn:aws:iam::{account_id}:role/CloudCustodianExecutionRole
    filters:
      - type: bucket-encryption
        state: false
    actions:
      - type: notify
        transport:
          type: sqs
          queue: https://sqs.us-east-1.amazonaws.com/172327596604/aikyam-cloud-custodian-periodic-notifications
        template: s3-unencrypted-buckets
        subject: '[Daily Report] Unencrypted S3 Buckets - {account_id}'
        to:
          - compliance-reports@example.com
```

### Ad-Hoc Manual Policy

```yaml
policies:
  - name: ec2-instances-without-tags
    resource: ec2
    description: Find EC2 instances missing required tags (run manually)
    filters:
      - type: value
        key: "tag:Environment"
        value: absent
    actions:
      - type: notify
        transport:
          type: sqs
          queue: https://sqs.us-east-1.amazonaws.com/172327596604/aikyam-cloud-custodian-periodic-notifications
        subject: 'EC2 Instances Missing Environment Tag - {account_id}'
        to:
          - ops-team@example.com
```

## Current Policy Queue Assignments

All existing policies in this repository are currently configured to use the **PERIODIC queue** because they are ad-hoc/manual policies (no mode defined).

To convert an existing policy to real-time:
1. Add `mode.type: cloudtrail` with appropriate events
2. Update the queue URL to the realtime queue
3. Consider using simpler subject/body (templates not supported for realtime)

## Getting Queue URLs from Terraform

```bash
# Get realtime queue URL
terraform -chdir=terraform/ad-hoc/central/cloud-custodian output realtime_queue_url

# Get periodic queue URL  
terraform -chdir=terraform/ad-hoc/central/cloud-custodian output periodic_queue_url
```

## Monitoring Queue Health

### CloudWatch Metrics to Watch

**Real-Time Queue:**
```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/SQS \
  --metric-name ApproximateAgeOfOldestMessage \
  --dimensions Name=QueueName,Value=aikyam-cloud-custodian-realtime-notifications \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Maximum
```

**Periodic Queue:**
```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/SQS \
  --metric-name ApproximateNumberOfMessagesVisible \
  --dimensions Name=QueueName,Value=aikyam-cloud-custodian-periodic-notifications \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

## Troubleshooting

### Messages Not Processing from Real-Time Queue

1. Check Lambda logs:
   ```bash
   aws logs tail /aws/lambda/cloud-custodian-cross-account-executor --follow
   ```

2. Verify REALTIME_QUEUE_URL environment variable:
   ```bash
   aws lambda get-function-configuration \
     --function-name cloud-custodian-cross-account-executor \
     --query 'Environment.Variables.REALTIME_QUEUE_URL'
   ```

3. Check SQS permissions in IAM policy

### Messages Not Processing from Periodic Queue

1. Check mailer Lambda logs:
   ```bash
   aws logs tail /aws/lambda/cloud-custodian-mailer --follow
   ```

2. Verify EventBridge schedule is enabled:
   ```bash
   aws events list-rules --name-prefix cloud-custodian-mailer
   ```

3. Verify QUEUE_URL environment variable:
   ```bash
   aws lambda get-function-configuration \
     --function-name cloud-custodian-mailer \
     --query 'Environment.Variables.QUEUE_URL'
   ```

## Migration Checklist

- [x] Update all existing policies to use periodic queue (completed)
- [ ] Apply Terraform changes to create new queues
- [ ] Test periodic queue with existing policies
- [ ] Create new real-time policies for critical alerts
- [ ] Update documentation and runbooks
- [ ] Train team on queue selection criteria

---

**Last Updated:** December 19, 2024  
**Related Documentation:** [SEPARATE-QUEUES-ARCHITECTURE.md](../../terraform/ad-hoc/central/cloud-custodian/SEPARATE-QUEUES-ARCHITECTURE.md)
