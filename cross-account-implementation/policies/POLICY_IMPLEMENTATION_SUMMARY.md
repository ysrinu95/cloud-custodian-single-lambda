# Cloud Custodian Policy Implementation Summary

This document maps the requirements from CloudCustodian_Policies.txt to the implemented policy files.

## Policy Files Created

1. **aws-alb-security.yml** - Application Load Balancer & ELB policies
2. **aws-ec2-security.yml** - EC2, AMI, EBS policies
3. **aws-security-groups.yml** - Security Group rules (all ports)
4. **aws-s3-security.yml** - S3 bucket security policies
5. **aws-rds-security.yml** - RDS security policies
6. **aws-iam-security.yml** - IAM security policies
7. **aws-cloudfront-security.yml** - CloudFront security policies
8. **aws-container-security.yml** - ECR, EKS security policies
9. **aws-data-encryption.yml** - ElastiCache, EFS, Elasticsearch, Kinesis, Redshift, SNS
10. **aws-waf-security.yml** - WAF logging policies

## Policy Coverage Matrix

| Requirement | Policy Name | File | Detection Type |
|------------|-------------|------|----------------|
| AWS ALB listening on port 80 without redirect to HTTPS | alb-http-no-redirect-to-https | aws-alb-security.yml | realtime/periodic |
| AWS AMI is publicly accessible | ami-publicly-accessible | aws-ec2-security.yml | realtime/periodic |
| AWS ALB not using latest predefined security policy | alb-outdated-ssl-policy | aws-alb-security.yml | realtime/periodic |
| AWS CloudFront using insecure SSL protocols | cloudfront-insecure-ssl-protocols | aws-cloudfront-security.yml | cloudtrail/periodic |
| AWS CloudFront logging not to central bucket | cloudfront-logging-not-central | aws-cloudfront-security.yml | cloudtrail/periodic |
| AWS CloudFront TLS version 1.1 or lower | cloudfront-tls-v11-or-lower | aws-cloudfront-security.yml | cloudtrail/periodic |
| AWS EBS snapshot not encrypted | ebs-snapshot-unencrypted | aws-ec2-security.yml | realtime/periodic |
| AWS EBS snapshots accessible to public | ebs-snapshot-public | aws-ec2-security.yml | realtime/periodic |
| AWS EC2 instance older than 30 days | ec2-instance-older-than-30-days | aws-ec2-security.yml | periodic |
| AWS ECR repository exposed to public | ecr-repository-public | aws-container-security.yml | cloudtrail/periodic |
| AWS EKS cluster with excessive public connectivity | eks-cluster-public-access | aws-container-security.yml | cloudtrail/periodic |
| AWS EKS control plane logging disabled | eks-control-plane-logging-disabled | aws-container-security.yml | cloudtrail/periodic |
| AWS ELB logging not to central bucket | elb-logging-not-central-bucket | aws-alb-security.yml | cloudtrail/periodic |
| AWS ElastiCache Redis encryption at rest disabled | elasticache-redis-no-encryption-at-rest | aws-data-encryption.yml | cloudtrail/periodic |
| AWS ElastiCache Redis in-transit encryption disabled (Replication) | elasticache-redis-no-transit-encryption-replication | aws-data-encryption.yml | cloudtrail/periodic |
| AWS ElastiCache Redis in-transit encryption disabled (Standalone) | elasticache-redis-no-transit-encryption-standalone | aws-data-encryption.yml | cloudtrail/periodic |
| AWS EFS encryption disabled | efs-encryption-disabled | aws-data-encryption.yml | cloudtrail/periodic |
| AWS ELBv2 listener TLS not configured | elbv2-no-tls-listener | aws-alb-security.yml | cloudtrail/periodic |
| AWS Elasticsearch encryption at rest disabled | elasticsearch-encryption-disabled | aws-data-encryption.yml | cloudtrail/periodic |
| AWS IAM expired SSL/TLS certificates | iam-expired-ssl-certificates | aws-iam-security.yml | periodic |
| AWS IAM user has both console and access keys | iam-user-console-and-keys | aws-iam-security.yml | periodic |
| AWS Kinesis streams not encrypted | kinesis-stream-not-encrypted | aws-data-encryption.yml | periodic |
| AWS NLB not using latest security policy | nlb-outdated-ssl-policy | aws-alb-security.yml | periodic |
| AWS Security Group CIFS 445 from internet | sg-allow-cifs-from-internet | aws-security-groups.yml | periodic |
| AWS Security Group RDP 3389 from internet | sg-allow-rdp-from-internet | aws-security-groups.yml | periodic |
| AWS RDS cluster encryption disabled | rds-cluster-encryption-disabled | aws-rds-security.yml | cloudtrail/periodic |
| AWS RDS instance publicly accessible | rds-instance-publicly-accessible | aws-rds-security.yml | cloudtrail/periodic |
| AWS RDS snapshots accessible to public | rds-snapshot-public | aws-rds-security.yml | cloudtrail/periodic |
| AWS Redshift not encrypted | redshift-cluster-not-encrypted | aws-data-encryption.yml | cloudtrail/periodic |
| AWS Redshift logging not to central bucket | redshift-logging-not-central | aws-data-encryption.yml | cloudtrail/periodic |
| AWS S3 bucket global PUT permissions | s3-global-put-permissions | aws-s3-security.yml | cloudtrail/periodic |
| AWS S3 bucket global permissions (GET/LIST) | s3-global-permissions | aws-s3-security.yml | cloudtrail/periodic |
| AWS S3 public access block disabled | s3-public-access-block-disabled | aws-s3-security.yml | cloudtrail/periodic |
| AWS S3 bucket global view ACL | s3-global-view-acl | aws-s3-security.yml | cloudtrail/periodic |
| AWS S3 bucket no secure transport policy | s3-no-secure-transport-policy | aws-s3-security.yml | cloudtrail/periodic |
| AWS S3 bucket public via ACL | s3-public-via-acl | aws-s3-security.yml | cloudtrail/periodic |
| AWS S3 bucket no server-side encryption | s3-no-server-side-encryption | aws-s3-security.yml | cloudtrail/periodic |
| AWS SNS topic encryption disabled | sns-topic-no-encryption | aws-data-encryption.yml | cloudtrail/periodic |
| AWS Security Group allows CIFS port 445 | sg-allow-cifs-from-internet | aws-security-groups.yml | cloudtrail/periodic |
| AWS Security Group allows DNS port 53 | sg-allow-risky-ports-from-internet | aws-security-groups.yml | cloudtrail/periodic |
| AWS Security Group allows FTP-Data port 20 | sg-allow-risky-ports-from-internet | aws-security-groups.yml | cloudtrail/periodic |
| AWS Security Group allows FTP port 21 | sg-allow-risky-ports-from-internet | aws-security-groups.yml | cloudtrail/periodic |
| AWS Security Group allows MSQL port 4333 | sg-allow-risky-ports-from-internet | aws-security-groups.yml | cloudtrail/periodic |
| AWS Security Group allows MYSQL port 3306 | sg-allow-mysql-from-internet | aws-security-groups.yml | cloudtrail/periodic |
| AWS Security Group allows NetBIOS ports 137-139 | sg-allow-risky-ports-from-internet | aws-security-groups.yml | cloudtrail/periodic |
| AWS Security Group allows Oracle port 1521 | sg-allow-oracle-from-internet | aws-security-groups.yml | cloudtrail/periodic |
| AWS Security Group allows POP3 port 110 | sg-allow-risky-ports-from-internet | aws-security-groups.yml | cloudtrail/periodic |
| AWS Security Group allows PostgreSQL port 5432 | sg-allow-postgresql-from-internet | aws-security-groups.yml | cloudtrail/periodic |
| AWS Security Group allows RDP port 3389 | sg-allow-rdp-from-internet | aws-security-groups.yml | cloudtrail/periodic |
| AWS Security Group allows SMTP port 25 | sg-allow-risky-ports-from-internet | aws-security-groups.yml | cloudtrail/periodic |
| AWS Security Group allows SQL Server port 1433 | sg-allow-sqlserver-from-internet | aws-security-groups.yml | cloudtrail/periodic |
| AWS Security Group allows SQL Server port 1434 | sg-allow-risky-ports-from-internet | aws-security-groups.yml | cloudtrail/periodic |
| AWS Security Group allows SSH port 22 | sg-allow-ssh-from-internet | aws-security-groups.yml | cloudtrail/periodic |
| AWS Security Group allows Telnet port 23 | sg-allow-telnet-from-internet | aws-security-groups.yml | cloudtrail/periodic |
| AWS Security Group allows VNC ports 5500/5900 | sg-allow-risky-ports-from-internet | aws-security-groups.yml | cloudtrail/periodic |
| AWS Security Group allows Windows RPC port 135 | sg-allow-risky-ports-from-internet | aws-security-groups.yml | cloudtrail/periodic |
| AWS Security Group allows MongoDB port 27017 | sg-allow-mongodb-from-internet | aws-security-groups.yml | cloudtrail/periodic |
| AWS Security Group allows uncommon ports | (covered by specific port policies) | aws-security-groups.yml | cloudtrail/periodic |
| AWS Security Group overly permissive to all traffic | sg-allow-all-traffic | aws-security-groups.yml | cloudtrail/periodic |
| AWS Access keys not rotated for 365 days | iam-access-keys-not-rotated | aws-iam-security.yml | cloudtrail/periodic |
| EC2 IMDSv1 enabled | ec2-imdsv1-enabled | aws-ec2-security.yml | cloudtrail/periodic |
| EC2 with unencrypted EBS volumes | ec2-unencrypted-ebs-volume | aws-ec2-security.yml | cloudtrail/periodic |
| WAF Classic logging not to central stream | waf-classic-logging-not-central | aws-waf-security.yml | cloudtrail/periodic |
| CIFS with IGW route | sg-cifs-with-igw-route | aws-security-groups.yml | periodic |
| RDP with IGW route | sg-rdp-with-igw-route | aws-security-groups.yml | periodic |

## Implementation Details

### Detection Types

1. **Real-time**: Policies that can detect resources immediately when created via CloudTrail events
2. **Periodic**: Policies that run on schedule to scan existing resources
3. **CloudTrail/Periodic**: Can be triggered by CloudTrail events or run periodically

### Actions Implemented

All policies include:
- **notify**: Send alerts to SQS queue for email notifications
- **Detailed remediation steps**: CLI commands to fix violations
- **Risk descriptions**: Security impact of violations

Some policies also include automatic remediation actions:
- `delete-global-grants`: Remove public S3 ACL permissions
- `set-public-block`: Enable S3 public access block
- `set-bucket-encryption`: Enable S3 encryption
- `modify-db`: Make RDS instances private
- `set-metadata-access`: Enforce EC2 IMDSv2
- `remove-launch-permissions`: Make AMIs private
- `set-permissions`: Remove public snapshot access
- `update-config`: Enable EKS control plane logging
- `encrypt`: Enable Kinesis encryption

### Central Logging Requirements

Several policies enforce centralized logging to buckets/streams with "lp-cl" prefix:
- CloudFront access logs
- ELB access logs
- Redshift audit logs
- WAF logs (via Kinesis Firehose)

All logging must include proper service prefixes (e.g., `service=cloudfront`).

## Next Steps

1. **Upload policies to S3**: 
   ```bash
   aws s3 sync policies/ s3://ysr95-custodian-policies/policies/
   ```

2. **Update account-policy-mapping.json**: Map policies to CloudTrail events for real-time detection

3. **Test policies**: Run in dryrun mode first
   ```bash
   custodian run -s output/ policies/aws-s3-security.yml --dryrun
   ```

4. **Schedule periodic execution**: Set up Lambda triggers or EC2 cron jobs for periodic policies

5. **Configure notifications**: Ensure SQS queue is properly configured with SNS for email delivery

## Notes

- All policies are configured to send notifications to the central SQS queue
- Policies include both detection and remediation guidance
- Some resources cannot have encryption enabled after creation (EFS, RDS, Redshift, ElastiCache) - these require recreation
- Security Group policies cover all required ports from the original requirements
- IAM and certificate policies are global (no region specified)
