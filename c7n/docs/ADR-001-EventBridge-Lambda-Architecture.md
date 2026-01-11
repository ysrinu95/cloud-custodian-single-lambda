# Architecture Decision Record (ADR)

## ADR-001: Use EventBridge + Lambda with Layers for Cloud Custodian Execution

**Status:** Accepted  
**Date:** 2025-11-09  
**Decision Makers:** DevOps/Platform Team  
**Technical Story:** Need automated, scheduled execution of Cloud Custodian policies for AWS resource governance and compliance

---

## Context and Problem Statement

We need to implement automated Cloud Custodian policy execution to:
- Enforce tagging standards on AWS resources
- Monitor security compliance continuously
- Optimize costs by cleaning up unused resources
- Generate compliance reports regularly
- Respond to AWS resource events in near real-time

**Key Requirements:**
- Scheduled execution (hourly/daily)
- Event-driven execution capability
- Minimal operational overhead
- Cost-effective solution
- Easy to maintain and update policies
- Support for multiple AWS accounts (future)

**Options Considered:**
1. EventBridge → Lambda with Layer
2. EventBridge → ECS Task
3. EC2 with cron job
4. Cloud Custodian native Lambda mode (c7n deployment)

---

## Decision

**We will use EventBridge Rules triggering Lambda Functions with Lambda Layers containing Cloud Custodian packages.**

### Architecture Components:

```
┌─────────────────────────────────────────────────────────────┐
│                    EventBridge Rules                         │
│  - Schedule-based (rate/cron)                               │
│  - Event-driven (resource state changes)                    │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│                  Lambda Function                             │
│  - Runtime: Python 3.11                                     │
│  - Handler: lambda_native.lambda_handler                    │
│  - Timeout: 5-15 minutes                                    │
│  - Memory: 512-1024 MB                                      │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ├──► Lambda Layer (Cloud Custodian)
                     │    - c7n packages
                     │    - Dependencies
                     │    - Size: ~25-35 MB
                     │
                     ├──► IAM Role
                     │    - Read access to AWS resources
                     │    - Write access for remediation
                     │    - CloudWatch Logs access
                     │
                     ├──► CloudWatch Logs
                     │    - Execution logs
                     │    - Policy results
                     │    - Error tracking
                     │
                     └──► AWS Resources
                          - EC2, S3, RDS, Lambda, etc.
                          - Tag enforcement
                          - Compliance checks
                          - Cost optimization
```

---

## Decision Drivers

### Positive Drivers
1. **Operational Simplicity** - Serverless, no infrastructure management
2. **Cost Efficiency** - Pay per execution, no idle costs
3. **Native AWS Integration** - EventBridge, CloudWatch, IAM
4. **Scalability** - Automatic scaling, 1000 concurrent executions
5. **Fast Deployment** - Terraform automation, minutes to deploy
6. **Developer Experience** - Familiar serverless pattern
7. **Execution Time** - Most policies complete in < 5 minutes

### Constraints
1. Lambda 15-minute timeout limit
2. Lambda 250 MB package size limit (unzipped)
3. Lambda 10 GB memory limit
4. Cold start latency (~2-5 seconds)

---

## Considered Alternatives

### Alternative 1: ECS Task (Fargate)
**Pros:**
- No time limit
- Unlimited package size
- More control over environment
- Better for long-running workloads

**Cons:**
- Higher operational complexity
- Higher minimum cost
- Slower cold start (30-60s)
- Requires VPC/networking configuration
- More moving parts to maintain

**Why Rejected:** Overkill for our use case. Most policies execute in < 5 minutes, making Lambda's simpler model more suitable.

### Alternative 2: EC2 with Cron
**Pros:**
- Full control
- No time limits
- Can run any workload

**Cons:**
- Requires instance management
- Security patching overhead
- High availability complexity
- Fixed cost (runs 24/7)
- Manual scaling

**Why Rejected:** Too much operational overhead for a scheduled task. Lambda serverless model is more appropriate.

### Alternative 3: Cloud Custodian Native Lambda Deployment
**Pros:**
- Official c7n approach
- Built-in Lambda deployment
- Per-policy Lambda functions

**Cons:**
- Less flexible
- More Lambda functions to manage
- Harder to customize
- Not using Terraform fully
- Split deployment model

**Why Rejected:** We want full Terraform control and flexibility to customize the execution environment.

---

## Consequences

### Positive Consequences
✅ **Low Operational Overhead** - No servers, clusters, or infrastructure to manage  
✅ **Cost Effective** - Estimated $5-20/month for typical workloads  
✅ **Fast Iteration** - Update policies without redeploying infrastructure  
✅ **Automatic Scaling** - Handles concurrent policy executions automatically  
✅ **Built-in Monitoring** - CloudWatch metrics and logs out of the box  
✅ **Security** - IAM integration, VPC support if needed, encryption at rest  
✅ **Disaster Recovery** - Serverless, multi-AZ by default  

### Negative Consequences
⚠️ **Time Limit** - Cannot run policies exceeding 15 minutes  
⚠️ **Cold Starts** - First execution may be slower (~2-5 seconds)  
⚠️ **Package Size** - Must keep dependencies under 250 MB unzipped  
⚠️ **Debugging** - Slightly harder than container-based debugging  
⚠️ **Vendor Lock-in** - AWS Lambda specific (mitigated by using standard c7n)  

### Mitigation Strategies
1. **Time Limit**: Monitor execution times; split long policies if needed
2. **Cold Starts**: Use provisioned concurrency if critical
3. **Package Size**: Optimize layer, exclude boto3/botocore (30-40 MB saved)
4. **Debugging**: Use CloudWatch Insights, X-Ray for tracing
5. **Vendor Lock-in**: Keep policies in standard c7n format, reusable elsewhere

---

## Implementation Details

### Technology Stack
- **Compute**: AWS Lambda (Python 3.11)
- **Orchestration**: Amazon EventBridge
- **Dependencies**: Lambda Layers
- **IaC**: Terraform
- **CI/CD**: GitHub Actions
- **Monitoring**: CloudWatch Logs + Metrics
- **Package Management**: pip, requirements.txt

### Execution Modes
We support two modes (native mode recommended):

1. **Native Mode (Recommended)**
   - Uses c7n as Python library
   - Direct `policy.run()` execution
   - Better performance and error handling

2. **CLI Mode (Optional)**
   - Executes `custodian run` via subprocess
   - For CLI feature compatibility

### Deployment Model
```
GitHub Repository
      ↓
GitHub Actions Workflow
      ↓
1. Build Lambda Layer (c7n packages)
2. Package Lambda Function (handler code)
3. Terraform Apply
      ↓
AWS Infrastructure (Lambda + EventBridge)
```

---

## Risks and Mitigations

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Lambda timeout (15 min) | High | Low | Monitor execution times; optimize policies |
| Package size limit | Medium | Very Low | Current size ~30 MB, 88% headroom |
| Cold start latency | Low | Medium | Acceptable for scheduled tasks |
| IAM permissions too broad | High | Medium | Principle of least privilege; regular audits |
| Policy errors | Medium | Medium | Dry-run mode; testing in dev; CloudWatch alerts |
| Cost overrun | Medium | Low | CloudWatch billing alarms; execution limits |

---

## Compliance and Security

### Security Measures
- IAM roles with least privilege
- CloudWatch Logs encryption
- VPC integration capability (if needed)
- Secrets Manager for sensitive data
- Lambda environment variable encryption

### Compliance Alignment
- **SOC 2**: Audit logging via CloudWatch
- **GDPR**: No PII in logs
- **HIPAA**: Encryption at rest and in transit
- **PCI DSS**: Network isolation options

---

## Success Metrics

### Performance Metrics
- Average execution time < 5 minutes
- Cold start time < 5 seconds
- Success rate > 99%
- P95 execution time < 8 minutes

### Operational Metrics
- Deployment time < 5 minutes
- Zero-downtime deployments
- Mean time to recovery < 1 hour
- Policy update time < 2 minutes

### Cost Metrics
- Cost per execution < $0.01
- Monthly cost < $20 (typical workload)
- Cost per policy < $0.002

---

## Review and Update

**Review Schedule:** Quarterly  
**Next Review Date:** 2026-02-09  

**Triggers for Re-evaluation:**
- Consistent Lambda timeouts (> 5% of executions)
- Package size approaching 200 MB
- Cost exceeds $50/month
- Need for execution time > 15 minutes
- Multi-region requirements

---

## References

- [Cloud Custodian Documentation](https://cloudcustodian.io/)
- [AWS Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
- [AWS Lambda Limits](https://docs.aws.amazon.com/lambda/latest/dg/gettingstarted-limits.html)
- [EventBridge Documentation](https://docs.aws.amazon.com/eventbridge/)
- Internal: Size estimation analysis (`scripts/estimate_size.py`)
- Internal: Lambda vs ECS comparison (`docs/LAMBDA_VS_ECS.md`)

---

## Approval

**Approved By:** [DevOps Lead, Platform Architect]  
**Approval Date:** 2025-11-09  
**Implementation Target:** 2025-11-15  

---

## Change Log

| Date | Version | Changes | Author |
|------|---------|---------|--------|
| 2025-11-09 | 1.0 | Initial ADR | DevOps Team |

---

## Appendix A: Cost Analysis

### Scenario 1: Small Workload
- Executions: Every hour (720/month)
- Duration: 3 minutes average
- Memory: 512 MB
- **Cost: ~$2.50/month**

### Scenario 2: Medium Workload
- Executions: Every hour (720/month)
- Duration: 8 minutes average
- Memory: 1024 MB
- **Cost: ~$8.50/month**

### Scenario 3: Large Workload
- Executions: Every 15 minutes (2,880/month)
- Duration: 5 minutes average
- Memory: 1024 MB
- **Cost: ~$18.00/month**

---

## Appendix B: Alternatives Decision Matrix

| Criteria | Lambda | ECS Task | EC2 Cron | Score Weight |
|----------|--------|----------|----------|--------------|
| Operational Simplicity | 10 | 6 | 3 | 25% |
| Cost (typical workload) | 9 | 7 | 4 | 20% |
| Deployment Speed | 10 | 6 | 4 | 15% |
| Scalability | 10 | 8 | 3 | 15% |
| Time Flexibility | 5 | 10 | 10 | 10% |
| Debugging | 7 | 8 | 9 | 5% |
| Security | 9 | 8 | 6 | 10% |
| **TOTAL** | **8.6** | **7.2** | **4.5** | **100%** |

**Winner: Lambda with score of 8.6/10**
