# Non-Functional Requirements (NFR)

## Cloud Custodian Lambda Execution Platform
**Version:** 1.0  
**Date:** 2025-11-09  
**Architecture:** EventBridge → Lambda with Layers

---

## 1. Performance Requirements

### 1.1 Execution Performance
| Requirement ID | Description | Target | Measurement |
|----------------|-------------|--------|-------------|
| **NFR-PERF-001** | Average policy execution time | < 5 minutes | CloudWatch Metrics |
| **NFR-PERF-002** | P95 policy execution time | < 8 minutes | CloudWatch Metrics |
| **NFR-PERF-003** | P99 policy execution time | < 12 minutes | CloudWatch Metrics |
| **NFR-PERF-004** | Cold start latency | < 5 seconds | CloudWatch Logs |
| **NFR-PERF-005** | Warm execution latency | < 1 second | CloudWatch Logs |
| **NFR-PERF-006** | Maximum execution time | < 15 minutes | Lambda timeout |

### 1.2 Throughput
| Requirement ID | Description | Target | Measurement |
|----------------|-------------|--------|-------------|
| **NFR-PERF-007** | Concurrent policy executions | Up to 100 | Lambda concurrency |
| **NFR-PERF-008** | Policies per hour | 1000+ | EventBridge + Lambda |
| **NFR-PERF-009** | Resources scanned per minute | 10,000+ | Policy metrics |
| **NFR-PERF-010** | Maximum policies per execution | 50 | Handler limitation |

### 1.3 Resource Utilization
| Requirement ID | Description | Target | Measurement |
|----------------|-------------|--------|-------------|
| **NFR-PERF-011** | Lambda memory usage | < 80% allocated | CloudWatch Metrics |
| **NFR-PERF-012** | Lambda package size | < 50 MB | Build verification |
| **NFR-PERF-013** | Layer size (unzipped) | < 100 MB | Layer deployment |
| **NFR-PERF-014** | Temp storage usage | < 5 GB | /tmp monitoring |

---

## 2. Reliability Requirements

### 2.1 Availability
| Requirement ID | Description | Target | Measurement |
|----------------|-------------|--------|-------------|
| **NFR-REL-001** | Service availability | 99.9% | CloudWatch alarms |
| **NFR-REL-002** | Lambda execution success rate | > 99% | CloudWatch Metrics |
| **NFR-REL-003** | EventBridge rule reliability | > 99.9% | AWS SLA |
| **NFR-REL-004** | Maximum acceptable downtime | < 8 hours/year | Monitoring |

### 2.2 Fault Tolerance
| Requirement ID | Description | Target | Measurement |
|----------------|-------------|--------|-------------|
| **NFR-REL-005** | Retry attempts on failure | 2 retries | Lambda config |
| **NFR-REL-006** | Dead letter queue (DLQ) | Enabled | SQS/SNS config |
| **NFR-REL-007** | Error handling | Graceful degradation | Code review |
| **NFR-REL-008** | Partial failure handling | Continue on error | Handler logic |
| **NFR-REL-009** | State recovery | Idempotent operations | Policy design |

### 2.3 Disaster Recovery
| Requirement ID | Description | Target | Measurement |
|----------------|-------------|--------|-------------|
| **NFR-REL-010** | Recovery Time Objective (RTO) | < 1 hour | DR testing |
| **NFR-REL-011** | Recovery Point Objective (RPO) | < 1 hour | Backup schedule |
| **NFR-REL-012** | Infrastructure as Code backup | Git repository | Version control |
| **NFR-REL-013** | Configuration backup | Terraform state | S3 backend |
| **NFR-REL-014** | Multi-AZ deployment | Yes (Lambda default) | AWS design |

---

## 3. Scalability Requirements

### 3.1 Horizontal Scalability
| Requirement ID | Description | Target | Measurement |
|----------------|-------------|--------|-------------|
| **NFR-SCALE-001** | Lambda concurrent executions | 1000 (AWS default) | Service quotas |
| **NFR-SCALE-002** | Auto-scaling | Automatic | Lambda native |
| **NFR-SCALE-003** | Scale-up time | < 1 minute | Testing |
| **NFR-SCALE-004** | Scale-down time | Immediate | Lambda native |

### 3.2 Vertical Scalability
| Requirement ID | Description | Target | Measurement |
|----------------|-------------|--------|-------------|
| **NFR-SCALE-005** | Lambda memory adjustment | 512-3008 MB | Configuration |
| **NFR-SCALE-006** | Timeout adjustment | 5-900 seconds | Configuration |
| **NFR-SCALE-007** | Layer size capacity | Up to 250 MB | AWS limit |

### 3.3 Load Handling
| Requirement ID | Description | Target | Measurement |
|----------------|-------------|--------|-------------|
| **NFR-SCALE-008** | Peak load handling | 10x normal load | Load testing |
| **NFR-SCALE-009** | Burst capacity | 3000 executions | Lambda burst |
| **NFR-SCALE-010** | Throttling strategy | Exponential backoff | SDK config |

---

## 4. Security Requirements

### 4.1 Authentication & Authorization
| Requirement ID | Description | Target | Measurement |
|----------------|-------------|--------|-------------|
| **NFR-SEC-001** | IAM role-based access | Yes | IAM policies |
| **NFR-SEC-002** | Least privilege principle | Enforced | Policy review |
| **NFR-SEC-003** | Service-to-service auth | IAM roles | Configuration |
| **NFR-SEC-004** | No hardcoded credentials | Zero | Code scan |

### 4.2 Data Protection
| Requirement ID | Description | Target | Measurement |
|----------------|-------------|--------|-------------|
| **NFR-SEC-005** | Data encryption at rest | AES-256 | AWS KMS |
| **NFR-SEC-006** | Data encryption in transit | TLS 1.2+ | AWS default |
| **NFR-SEC-007** | Secrets management | AWS Secrets Manager | Configuration |
| **NFR-SEC-008** | Environment variable encryption | KMS | Lambda config |
| **NFR-SEC-009** | CloudWatch Logs encryption | Yes | Log group config |

### 4.3 Network Security
| Requirement ID | Description | Target | Measurement |
|----------------|-------------|--------|-------------|
| **NFR-SEC-010** | VPC isolation (optional) | Supported | Lambda VPC config |
| **NFR-SEC-011** | Security group rules | Least privilege | Network review |
| **NFR-SEC-012** | Private subnet deployment | Optional | VPC design |
| **NFR-SEC-013** | NAT Gateway for internet | If VPC enabled | Network config |

### 4.4 Compliance & Audit
| Requirement ID | Description | Target | Measurement |
|----------------|-------------|--------|-------------|
| **NFR-SEC-014** | CloudTrail logging | Enabled | AWS config |
| **NFR-SEC-015** | Execution audit trail | Complete | CloudWatch Logs |
| **NFR-SEC-016** | Access logging | Enabled | CloudTrail |
| **NFR-SEC-017** | Policy change tracking | Git history | Version control |
| **NFR-SEC-018** | Compliance scanning | Weekly | Automated scan |

---

## 5. Maintainability Requirements

### 5.1 Deployability
| Requirement ID | Description | Target | Measurement |
|----------------|-------------|--------|-------------|
| **NFR-MAINT-001** | Deployment automation | 100% automated | CI/CD pipeline |
| **NFR-MAINT-002** | Deployment time | < 5 minutes | Pipeline metrics |
| **NFR-MAINT-003** | Zero-downtime deployment | Yes | Blue-green |
| **NFR-MAINT-004** | Rollback capability | < 2 minutes | Testing |
| **NFR-MAINT-005** | Infrastructure as Code | 100% | Terraform |

### 5.2 Observability
| Requirement ID | Description | Target | Measurement |
|----------------|-------------|--------|-------------|
| **NFR-MAINT-006** | Structured logging | JSON format | Log format |
| **NFR-MAINT-007** | Log retention | 7-30 days | CloudWatch config |
| **NFR-MAINT-008** | Metrics collection | Real-time | CloudWatch |
| **NFR-MAINT-009** | Distributed tracing | X-Ray enabled | Configuration |
| **NFR-MAINT-010** | Custom metrics | Policy-specific | CloudWatch |

### 5.3 Monitoring & Alerting
| Requirement ID | Description | Target | Measurement |
|----------------|-------------|--------|-------------|
| **NFR-MAINT-011** | Error alerting | < 5 minutes | SNS/Slack |
| **NFR-MAINT-012** | Performance degradation alerts | Yes | CloudWatch Alarms |
| **NFR-MAINT-013** | Cost anomaly alerts | Yes | AWS Budgets |
| **NFR-MAINT-014** | Execution failure alerts | Real-time | EventBridge |
| **NFR-MAINT-015** | Dashboard availability | 24/7 | CloudWatch Dashboard |

### 5.4 Testability
| Requirement ID | Description | Target | Measurement |
|----------------|-------------|--------|-------------|
| **NFR-MAINT-016** | Unit test coverage | > 80% | Coverage report |
| **NFR-MAINT-017** | Integration testing | Automated | CI pipeline |
| **NFR-MAINT-018** | Local testing capability | Yes | Mock framework |
| **NFR-MAINT-019** | Dry-run mode | Supported | Handler feature |

---

## 6. Usability Requirements

### 6.1 Developer Experience
| Requirement ID | Description | Target | Measurement |
|----------------|-------------|--------|-------------|
| **NFR-USE-001** | Local development setup | < 10 minutes | Documentation |
| **NFR-USE-002** | Policy syntax | Standard c7n YAML | Validation |
| **NFR-USE-003** | Documentation completeness | 100% | Doc review |
| **NFR-USE-004** | Example policies | 10+ examples | Repository |
| **NFR-USE-005** | Error messages | Clear and actionable | Code review |

### 6.2 Operational Experience
| Requirement ID | Description | Target | Measurement |
|----------------|-------------|--------|-------------|
| **NFR-USE-006** | Policy update process | < 5 minutes | Procedure |
| **NFR-USE-007** | Troubleshooting guide | Available | Documentation |
| **NFR-USE-008** | Log searchability | < 1 minute | CloudWatch Insights |
| **NFR-USE-009** | Manual invocation | Supported | AWS Console/CLI |

---

## 7. Cost Requirements

### 7.1 Cost Efficiency
| Requirement ID | Description | Target | Measurement |
|----------------|-------------|--------|-------------|
| **NFR-COST-001** | Monthly cost (typical workload) | < $20 | AWS Billing |
| **NFR-COST-002** | Cost per execution | < $0.01 | CloudWatch Metrics |
| **NFR-COST-003** | Cost per policy | < $0.002 | Analysis |
| **NFR-COST-004** | Lambda memory optimization | Right-sized | Monitoring |

### 7.2 Cost Monitoring
| Requirement ID | Description | Target | Measurement |
|----------------|-------------|--------|-------------|
| **NFR-COST-005** | Cost allocation tags | 100% tagged | Tag policy |
| **NFR-COST-006** | Budget alerts | Enabled | AWS Budgets |
| **NFR-COST-007** | Cost anomaly detection | Enabled | AWS Cost Anomaly |
| **NFR-COST-008** | Monthly cost reports | Automated | Cost Explorer |

---

## 8. Compatibility Requirements

### 8.1 Platform Compatibility
| Requirement ID | Description | Target | Measurement |
|----------------|-------------|--------|-------------|
| **NFR-COMPAT-001** | Python version | 3.11+ | Lambda runtime |
| **NFR-COMPAT-002** | Cloud Custodian version | 0.9.36+ | requirements.txt |
| **NFR-COMPAT-003** | Terraform version | 1.0+ | Version constraint |
| **NFR-COMPAT-004** | AWS Provider version | 5.0+ | Provider config |

### 8.2 Integration Compatibility
| Requirement ID | Description | Target | Measurement |
|----------------|-------------|--------|-------------|
| **NFR-COMPAT-005** | EventBridge integration | Native | AWS service |
| **NFR-COMPAT-006** | CloudWatch integration | Native | AWS service |
| **NFR-COMPAT-007** | SNS notification support | Yes | Configuration |
| **NFR-COMPAT-008** | S3 policy storage | Supported | Handler feature |

---

## 9. Capacity Requirements

### 9.1 Lambda Capacity
| Requirement ID | Description | Target | Measurement |
|----------------|-------------|--------|-------------|
| **NFR-CAP-001** | Concurrent executions | 100 reserved | Lambda config |
| **NFR-CAP-002** | Memory allocation | 512-1024 MB | Configuration |
| **NFR-CAP-003** | Timeout setting | 300-900 seconds | Configuration |
| **NFR-CAP-004** | Temp storage (/tmp) | 512 MB - 10 GB | Configuration |

### 9.2 Data Capacity
| Requirement ID | Description | Target | Measurement |
|----------------|-------------|--------|-------------|
| **NFR-CAP-005** | Resources per execution | 100,000+ | Testing |
| **NFR-CAP-006** | Policies per file | 100 | Best practice |
| **NFR-CAP-007** | Log data volume | 10 MB per execution | Monitoring |
| **NFR-CAP-008** | Policy file size | < 1 MB | Validation |

---

## 10. Compliance Requirements

### 10.1 Regulatory Compliance
| Requirement ID | Description | Target | Measurement |
|----------------|-------------|--------|-------------|
| **NFR-COMP-001** | GDPR compliance | Yes | Audit |
| **NFR-COMP-002** | SOC 2 compliance | Yes | Controls |
| **NFR-COMP-003** | HIPAA compliance support | Yes | AWS BAA |
| **NFR-COMP-004** | PCI DSS compliance support | Yes | Network isolation |

### 10.2 Data Residency
| Requirement ID | Description | Target | Measurement |
|----------------|-------------|--------|-------------|
| **NFR-COMP-005** | Region-specific deployment | Configurable | Terraform vars |
| **NFR-COMP-006** | Data locality | Single region | Configuration |
| **NFR-COMP-007** | Cross-region replication | Optional | DR config |

---

## 11. Environmental Requirements

### 11.1 Multi-Environment Support
| Requirement ID | Description | Target | Measurement |
|----------------|-------------|--------|-------------|
| **NFR-ENV-001** | Development environment | Isolated | Terraform workspace |
| **NFR-ENV-002** | Staging environment | Isolated | Terraform workspace |
| **NFR-ENV-003** | Production environment | Isolated | Terraform workspace |
| **NFR-ENV-004** | Environment parity | 95%+ | Configuration review |

### 11.2 Multi-Account Support
| Requirement ID | Description | Target | Measurement |
|----------------|-------------|--------|-------------|
| **NFR-ENV-005** | Cross-account execution | Supported | IAM cross-account |
| **NFR-ENV-006** | AWS Organizations support | c7n-org | Configuration |
| **NFR-ENV-007** | Account isolation | Enforced | IAM boundaries |

---

## 12. Documentation Requirements

| Requirement ID | Description | Target | Measurement |
|----------------|-------------|--------|-------------|
| **NFR-DOC-001** | Architecture documentation | Complete | ADR |
| **NFR-DOC-002** | Deployment guide | Step-by-step | README |
| **NFR-DOC-003** | Operations runbook | Complete | docs/ |
| **NFR-DOC-004** | Troubleshooting guide | Complete | docs/ |
| **NFR-DOC-005** | API documentation | Inline comments | Code review |
| **NFR-DOC-006** | Policy examples | 10+ samples | policies/ |

---

## Acceptance Criteria

The system is considered acceptable when:

1. ✅ All P0 (Critical) NFRs are met
2. ✅ 95%+ of P1 (High) NFRs are met
3. ✅ 80%+ of P2 (Medium) NFRs are met
4. ✅ Successful completion of performance testing
5. ✅ Successful completion of security audit
6. ✅ Deployment automation validated
7. ✅ Monitoring and alerting operational
8. ✅ Documentation complete and reviewed

---

## Priority Classification

| Priority | Description | Count |
|----------|-------------|-------|
| **P0** | Critical - System unusable without | 25 |
| **P1** | High - Significant impact | 40 |
| **P2** | Medium - Moderate impact | 35 |
| **P3** | Low - Nice to have | 10 |

---

## Testing Requirements

Each NFR must be validated through:
- **Performance**: Load testing, benchmark testing
- **Reliability**: Chaos engineering, failure injection
- **Security**: Penetration testing, vulnerability scanning
- **Scalability**: Load testing, stress testing
- **Maintainability**: Code review, documentation review

---

## Review and Updates

**Review Frequency:** Quarterly  
**Next Review:** 2026-02-09  
**Owner:** Platform Engineering Team  
**Approvers:** DevOps Lead, Security Team, Platform Architect

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2025-11-09 | Initial NFR document | DevOps Team |
