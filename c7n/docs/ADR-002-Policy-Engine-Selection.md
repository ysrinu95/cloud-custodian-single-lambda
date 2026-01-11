# ADR-002: Cloud Policy Engine Selection — Cloud Custodian and Alternatives

**Date:** 2025-12-16  
**Status:** Proposed  
**Deciders:** Cloud Security Platform Team  

---

## Context

Our organization operates a large, multi-account AWS environment and requires a scalable, maintainable solution for:
- Automated remediation and compliance enforcement
- Runtime policy enforcement across cloud resources
- Multi-account and multi-region execution
- Integration with existing CI/CD pipelines and security tooling

This ADR evaluates tools and approaches for implementing these capabilities, considering operational cost, maintainability, coverage, and alignment with our existing AWS-centric infrastructure.

### Tools Evaluated

1. **Cloud Custodian** — Open-source policy-as-code engine
2. **Security Hub + Custom Runbooks** — AWS-native findings aggregation with Lambda/SSM automation
3. **AWS Config Rules** — Managed compliance service with custom rules
4. **Open Policy Agent (OPA) / Gatekeeper** — Policy decision engine
5. **IaC Static Scanners** — Checkov, TerraScan (prevention layer)
6. **Kubernetes Tools** — Gatekeeper, Kyverno, Falco (container/cluster security)
7. **Commercial CSPM** — Prisma Cloud, Dome9, Fugue, Wiz, Orca

---

## Decision

**Adopt Cloud Custodian as the primary runtime policy enforcement engine** for broad, repeatable cloud resource remediation and continuous compliance.

**Complementary approach:**
- **Prevention layer:** Checkov/TerraScan in CI for IaC scanning
- **Findings aggregation:** Security Hub for centralized visibility and targeted runbooks requiring human approval or complex orchestration
- **Kubernetes:** Gatekeeper/Kyverno for admission control; Falco for runtime detection
- **Future consideration:** Commercial CSPM if operational gaps justify licensing cost

---

## Detailed Tool Evaluation

### 1. Cloud Custodian

**Type:** Open-source, policy-as-code engine for cloud resource governance

**Description:**  
Cloud Custodian allows teams to define policies using declarative YAML that describe resource queries (filters) and remediation actions. It supports scheduled execution (CLI, Jenkins, GitHub Actions) and event-driven mode (EventBridge → Lambda).

#### Pros ✅

| Aspect | Benefit |
|--------|---------|
| **Declarative policies** | YAML-based policies are easy to author, review, version-control, and validate in CI |
| **Rich filter DSL** | Built-in filters for tags, configuration, metrics, relationships, age, and custom expressions |
| **Built-in actions** | Stop/terminate, tag, delete, modify security groups, invoke Lambda, notify (SQS/SNS/email) |
| **Multi-account/region** | Native support for cross-account execution with role assumption and region iteration |
| **Dual execution modes** | Event-driven (near real-time) and periodic (scheduled) in a single framework |
| **Validation tooling** | `custodian validate` and `--dryrun` reduce deployment risk and false positives |
| **Multi-cloud support** | AWS, Azure, GCP support (if future expansion needed) |
| **Active community** | Mature project with large policy library and production adoption at scale |
| **Cost** | Open-source, no licensing fees |

#### Cons ❌

| Aspect | Limitation |
|--------|-----------|
| **Operational overhead** | Requires infrastructure for execution (CI jobs, Lambda orchestration, scheduler) |
| **Learning curve** | Policy DSL and filter syntax require onboarding |
| **Custom extensions** | Advanced filters/actions may require Python development |
| **Interactive workflows** | Not designed for human-in-the-loop approvals without additional integration |

#### When to choose
- Large, multi-account environments
- Need for broad coverage across many resource types
- Policy-as-code workflows with CI/CD integration
- Automated remediation and continuous compliance enforcement

---

### 2. Security Hub + Custom Runbooks

**Type:** AWS-native findings aggregator with imperative automation (Lambda/SSM)

**Description:**  
Security Hub centralizes findings from AWS services (GuardDuty, Inspector, Macie, etc.) and third-party integrations. Runbooks are custom Lambda functions or SSM Automation documents triggered by findings.

#### Pros ✅

| Aspect | Benefit |
|--------|---------|
| **Centralized findings** | Single pane of glass for security alerts across AWS services |
| **Native AWS integration** | Direct integration with AWS Console, Config, CloudWatch |
| **Flexible workflows** | Runbooks can perform arbitrary logic, call internal APIs, integrate with ticketing/chatops |
| **Human-in-the-loop** | Well-suited for investigative workflows requiring approval or escalation |

#### Cons ❌

| Aspect | Limitation |
|--------|-----------|
| **Many runbooks = many codebases** | Each finding type requires custom Lambda/SSM document with pagination, retries, auth |
| **Duplication of logic** | Resource discovery, filtering, remediation patterns repeated across runbooks |
| **Reactive only** | Findings-based; not designed for scheduled inventory checks or proactive scans |
| **Maintenance overhead** | More code to test, deploy, and maintain as coverage grows |
| **Limited reusability** | Hard to standardize without building and maintaining shared libraries |

#### When to choose
- Targeted runbooks requiring orchestration or human approval
- Investigation workflows that need step-by-step automation
- Integration with Security Hub as the primary triage interface

---

### 3. AWS Config Rules

**Type:** AWS-managed compliance service with configuration snapshot and rules engine

**Description:**  
AWS Config continuously records resource configuration and evaluates compliance against rules (AWS-managed or custom Lambda). Can trigger SSM Automation for remediation.

#### Pros ✅

| Aspect | Benefit |
|--------|---------|
| **Fully managed** | No infrastructure to maintain; AWS handles collection and evaluation |
| **Native compliance** | Built-in rules for common compliance frameworks (CIS, PCI-DSS) |
| **Configuration history** | Point-in-time snapshots for audit and drift detection |

#### Cons ❌

| Aspect | Limitation |
|--------|-----------|
| **Limited flexibility** | Less expressive than Cloud Custodian for complex filters and cross-resource logic |
| **AWS-only** | No multi-cloud support |
| **Custom rules require Lambda** | Custom logic still means maintaining code |
| **Cost at scale** | Config recording and rule evaluations incur ongoing costs |

#### When to choose
- Need AWS-native compliance reports and dashboards
- Simple remediation requirements
- Preference for managed AWS services over open-source tooling

---

### 4. Open Policy Agent (OPA) / Gatekeeper

**Type:** Policy decision engine with Rego language

**Description:**  
OPA provides a powerful policy language (Rego) for making policy decisions. Gatekeeper is the Kubernetes-native implementation for admission control.

#### Pros ✅

| Aspect | Benefit |
|--------|---------|
| **Powerful policy language** | Rego is expressive and supports complex logic, data queries, and composition |
| **Embeddable** | Can be embedded in applications, pipelines, and services |
| **Kubernetes integration** | Gatekeeper provides admission control to prevent non-compliant workloads |

#### Cons ❌

| Aspect | Limitation |
|--------|-----------|
| **Decision engine only** | Doesn't include resource discovery, collection, or remediation execution |
| **Infrastructure required** | Must build collectors, runners, and remediation logic around OPA |
| **Not cloud-native** | Better suited for in-cluster or pipeline decisions than multi-account cloud remediation |

#### When to choose
- Kubernetes admission control (Gatekeeper)
- Embedding policy decisions in CI/CD or applications
- Need for fine-grained policy logic with data queries

---

### 5. IaC Static Scanners (Checkov, TerraScan)

**Type:** Pre-deployment static analysis tools for Infrastructure-as-Code

**Description:**  
These tools scan Terraform, CloudFormation, Kubernetes manifests, and other IaC templates at commit time to identify misconfigurations before deployment.

#### Pros ✅

| Aspect | Benefit |
|--------|---------|
| **Shift-left security** | Catches issues in CI/CD before resources are provisioned |
| **Fast feedback** | Developers get immediate feedback in PRs |
| **Low operational cost** | Runs in CI pipelines; no runtime infrastructure |
| **Wide IaC support** | Terraform, CloudFormation, Kubernetes, Helm, Dockerfiles |

#### Cons ❌

| Aspect | Limitation |
|--------|-----------|
| **Static analysis only** | Cannot detect runtime drift or existing misconfigurations |
| **False positives** | May flag valid patterns that need exceptions/suppressions |
| **No remediation** | Only identifies issues; doesn't fix deployed resources |

#### When to choose
- Always use as prevention layer in CI/CD
- Pair with runtime tools (Cloud Custodian) for complete coverage

---

### 6. Kubernetes Tools (Gatekeeper, Kyverno, Falco)

**Type:** Kubernetes-native policy and security tooling

**Description:**  
- **Gatekeeper/Kyverno:** Admission controllers for policy enforcement at pod/workload creation
- **Falco:** Runtime detection for anomalous behavior in containers

#### Pros ✅

| Aspect | Benefit |
|--------|---------|
| **Kubernetes-native** | Purpose-built for cluster policy and runtime security |
| **Admission control** | Prevents non-compliant workloads from being deployed |
| **Runtime detection** | Falco detects suspicious activity (Falco) |

#### Cons ❌

| Aspect | Limitation |
|--------|-----------|
| **Cluster-scoped only** | Not a replacement for cloud-wide resource governance |
| **Separate tooling** | Requires integration with cloud-level enforcement |

#### When to choose
- Kubernetes clusters requiring admission control or runtime detection
- Complement with cloud-level tools for complete coverage

---

### 7. Commercial CSPM / Cloud Security Platforms

**Type:** SaaS or managed platforms (Prisma Cloud, Dome9, Fugue, Wiz, Orca)

**Description:**  
Full-featured cloud security platforms with scanning, compliance, remediation, dashboards, integrations, and vendor support.

#### Pros ✅

| Aspect | Benefit |
|--------|---------|
| **Turnkey solution** | Pre-built policies, dashboards, integrations, and reporting |
| **Vendor support** | SLAs, professional services, and ongoing feature development |
| **Advanced analytics** | Risk scoring, attack path analysis, and business context |
| **Multi-cloud** | Unified platform for AWS, Azure, GCP, Kubernetes |

#### Cons ❌

| Aspect | Limitation |
|--------|-----------|
| **Cost** | Licensing fees based on accounts, resources, or spend |
| **Vendor lock-in** | Migration between vendors is complex |
| **Overlap** | May duplicate capabilities of existing tooling investments |
| **Less customization** | Less control over policy logic and execution compared to open-source |

#### When to choose
- Operational scale or feature gaps justify licensing cost
- Need for vendor support and SLAs
- Require advanced analytics and reporting for executive visibility

---

## Comparison Matrix

| Capability | Cloud Custodian | Security Hub Runbooks | AWS Config | OPA/Gatekeeper | Checkov/TerraScan | K8s Tools | Commercial CSPM |
|------------|-----------------|----------------------|------------|----------------|-------------------|-----------|-----------------|
| **Policy as Code** | ✅ YAML | ❌ Imperative code | ⚠️ Custom Lambda | ✅ Rego | ✅ Built-in checks | ✅ YAML/Rego | ⚠️ UI/API |
| **Multi-account** | ✅ Native | ⚠️ Custom per runbook | ✅ Aggregator | ❌ | ✅ CI scans | ❌ | ✅ Native |
| **Event-driven** | ✅ EventBridge | ✅ Findings-based | ✅ Config changes | ❌ | ❌ | ✅ Admission | ✅ Native |
| **Scheduled** | ✅ CLI/CI | ❌ | ❌ | ❌ | ✅ CI | ❌ | ✅ Native |
| **Remediation** | ✅ Built-in actions | ⚠️ Custom per runbook | ⚠️ SSM Automation | ❌ Decision only | ❌ Detection only | ⚠️ K8s only | ✅ Built-in |
| **Multi-cloud** | ✅ AWS/Azure/GCP | ❌ AWS only | ❌ AWS only | ⚠️ Custom | ✅ Multi-IaC | ❌ | ✅ Multi-cloud |
| **Cost** | 🆓 Open-source | 💰 Lambda costs | 💰 Config fees | 🆓 Open-source | 🆓 Open-source | 🆓 Open-source | 💰💰 Licensing |
| **Maintenance** | ⚠️ Policies | ❌ Many codebases | ⚠️ Rules | ⚠️ Collectors | ✅ Low | ⚠️ Cluster-scoped | ✅ Vendor managed |

---

## Recommendation: Layered Security Approach

### Primary Strategy

**Cloud Custodian** as the primary runtime policy enforcement engine for:
- Broad, automated remediation across accounts and regions
- Continuous compliance and drift detection
- Event-driven and scheduled policy execution

### Complementary Tools

1. **Prevention (CI/CD):** Checkov/TerraScan for IaC scanning
2. **Findings & Triage:** Security Hub for centralized visibility
3. **Targeted Runbooks:** Lambda/SSM for complex workflows requiring human approval
4. **Kubernetes:** Gatekeeper/Kyverno for admission control; Falco for runtime detection
5. **Commercial CSPM:** Evaluate only if operational gaps justify licensing cost

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Prevention Layer                          │
│  Checkov/TerraScan → CI/CD → Block non-compliant IaC       │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│              Runtime Enforcement (Cloud Custodian)           │
│  ┌──────────────────┐         ┌──────────────────┐         │
│  │  Event-Driven    │         │    Scheduled     │         │
│  │ EventBridge→λ    │         │  Jenkins/GHA     │         │
│  │ Near real-time   │         │  Inventory scans │         │
│  └──────────────────┘         └──────────────────┘         │
│           ↓                            ↓                     │
│  ┌────────────────────────────────────────────────┐         │
│  │  Policies (YAML) → Filters → Actions           │         │
│  │  • Stop/Delete  • Tag  • Notify  • Remediate   │         │
│  └────────────────────────────────────────────────┘         │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│          Findings Aggregation (Security Hub)                 │
│  ┌──────────────────────────────────────────────┐           │
│  │ Ingest: GuardDuty, Inspector, Config, C7N   │           │
│  │ Triage: Prioritize, enrich, filter          │           │
│  │ Runbooks: Human approval, orchestration      │           │
│  └──────────────────────────────────────────────┘           │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│            Kubernetes Layer (Gatekeeper/Falco)               │
│  Admission Control → Policy Enforcement in Clusters         │
└─────────────────────────────────────────────────────────────┘
```

---

## Implementation Plan

### Phase 0: Pilot (2-4 weeks)

1. Select 3-5 high-value policies:
   - Public S3 buckets
   - Overly permissive IAM policies
   - Unencrypted RDS/EBS volumes
2. Implement Cloud Custodian policies in YAML
3. Run in non-prod account with `--dryrun` for validation
4. Integrate `custodian validate` into policy PR CI

### Phase 1: Production Rollout (1-2 months)

1. Deploy central mailer and SQS pipeline (already present in repo)
2. Schedule periodic execution via Jenkins/GitHub Actions
3. Enable event-driven mode for high-priority policies
4. Establish metrics: findings count, MTTR, false positives

### Phase 2: Optimization (Ongoing)

1. Consolidate runbooks to complex workflows only
2. Add dashboards for business value reporting
3. Expand policy coverage based on risk assessment
4. Integrate with Security Hub for unified findings view

---

## Consequences

### Positive
- Reduced operational overhead by centralizing policy logic in YAML
- Improved policy consistency and reusability across accounts
- Faster remediation through automation
- Better auditability via version-controlled policies

### Negative
- Team must adopt policy-as-code practices and CI validation workflows
- Initial learning curve for Cloud Custodian DSL
- Requires infrastructure for policy execution (Lambdas, CI jobs)

### Risks & Mitigations
| Risk | Mitigation |
|------|------------|
| Policy logic errors cause outages | Use `--dryrun`, staged rollouts, exception tags |
| False positives disrupt operations | Implement exemption tags (e.g., `c7n-exception`) and review process |
| Operational complexity | Centralize policy repository, standardize templates, automate validation |

---

## Related Decisions

- **ADR-001:** EventBridge → Lambda Architecture (existing)
- **Future ADR:** Multi-cloud expansion strategy

---

## References

- [Cloud Custodian Documentation](https://cloudcustodian.io)
- [AWS Security Hub](https://aws.amazon.com/security-hub/)
- [Checkov](https://www.checkov.io)
- [Open Policy Agent](https://www.openpolicyagent.org)
- [Gatekeeper](https://open-policy-agent.github.io/gatekeeper/)

---

## Status Log

**2025-12-16** — Proposed by Cloud Security Platform Team  
**Next Review:** Q1 2026 — Evaluate pilot results and decide on production rollout
