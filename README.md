# GCP Infrastructure — Terraform IaC + Monitoring + Security Hardening

Production-grade GCP infrastructure defined entirely in Terraform, with Prometheus + Grafana observability and defense-in-depth security hardening. Demonstrates VPC networking, GKE Autopilot, Cloud SQL, IAM least-privilege, pod security standards, network policies, secret management, container image scanning, and a containerized FastAPI application — all validated via `terraform plan` with zero cloud spend.

## Architecture

```
                         ┌─────────────────────────────────────────┐
                         │            GCP Project                  │
                         │          (cotter-cloud-dev)                │
                         │                                         │
                         │  ┌─────────────────────────────────┐   │
                         │  │     VPC (dev-main-vpc)           │   │
                         │  │     10.0.0.0/20                  │   │
                         │  │                                   │   │
                         │  │  ┌────────────────────────────┐  │   │
                         │  │  │  GKE Autopilot Cluster     │  │   │
                         │  │  │  (Private Nodes)           │  │   │
                         │  │  │                            │  │   │
                         │  │  │  ┌──────────┐             │  │   │
                         │  │  │  │ FastAPI  │             │  │   │
                         │  │  │  │ App Pod  │             │  │   │
                         │  │  │  └────┬─────┘             │  │   │
                         │  │  │       │ Private IP         │  │   │
                         │  │  └───────┼───────────────────┘  │   │
                         │  │          │                       │   │
                         │  │  ┌───────▼───────────────────┐  │   │
                         │  │  │  Cloud SQL Postgres       │  │   │
                         │  │  │  (Private IP only)        │  │   │
                         │  │  │  db-f1-micro              │  │   │
                         │  │  └───────────────────────────┘  │   │
                         │  └─────────────────────────────────┘   │
                         └─────────────────────────────────────────┘
```

## Modules

| Module | Purpose | Key Resources |
|--------|---------|---------------|
| **networking** | VPC, subnets, firewall rules, private service connection | `google_compute_network`, `google_compute_subnetwork`, `google_compute_firewall` |
| **iam** | Service accounts with least-privilege roles | `google_service_account`, `google_project_iam_member` |
| **gke** | GKE Autopilot cluster with private nodes and Workload Identity | `google_container_cluster` |
| **database** | Cloud SQL Postgres with private IP and automated backups | `google_sql_database_instance`, `google_sql_database` |
| **secrets** | Secret Manager with IAM-based access control | `google_secret_manager_secret`, `google_secret_manager_secret_iam_member` |
| **budget** | Billing budget with alerts at 50%, 80%, 100% of monthly limit | `google_billing_budget` |

## Design Decisions

### Why custom VPC (not default)?
The default VPC creates subnets in every region with wide-open firewall rules. A custom VPC with `auto_create_subnetworks = false` gives us explicit control over CIDR ranges and firewall rules — essential for security and avoiding IP conflicts.

### Why GKE Autopilot (not Standard)?
Autopilot removes node pool management, OS patching, and right-sizing decisions. Google manages the infrastructure; we only define workloads. For a dev environment, this means lower cost (pay-per-pod) and less operational overhead.

### Why private cluster?
GKE nodes with no public IPs can't be reached from the internet. All traffic flows through the VPC. This is defense in depth — even if a container is compromised, there's no direct internet path to the node.

### Why Workload Identity?
Without Workload Identity, pods typically use the node's service account (overly broad) or exported JSON keys (a security risk). Workload Identity maps Kubernetes service accounts directly to GCP service accounts — no keys to manage, no over-provisioned access.

### Why private IP for Cloud SQL?
A public IP on a database is an unnecessary attack surface. Private IP means the database is only reachable from within the VPC — the only path in is through the GKE cluster.

### Why a billing budget in Terraform?
Cost management is part of infrastructure. A $10 monthly budget with alerts at 50%, 80%, and 100% prevents surprise bills during development. Defining it in Terraform means the guardrail is version-controlled and deployed with everything else — it can't be accidentally deleted from the console.

### Why dedicated service accounts?
The default Compute Engine service account has `Editor` role on the project — far too much access. Dedicated service accounts with only the roles they need (artifact registry reader, log writer, Cloud SQL client) follow least-privilege principles.

### CIDR Planning
| Range | CIDR | Purpose |
|-------|------|---------|
| Subnet | `10.0.0.0/20` | 4,094 node IPs |
| Pods | `10.4.0.0/14` | 262,142 pod IPs |
| Services | `10.8.0.0/20` | 4,094 service IPs |
| Private services | `/16` | Cloud SQL, Memorystore |

Pod range is intentionally large — GKE allocates 256 IPs per node by default, so a `/14` supports scaling without re-architecting.

## Monitoring & Observability

Prometheus + Grafana deployed on GKE, with the FastAPI app instrumented using the RED method (Rate, Errors, Duration) — the industry standard for request-driven services.

### Why Prometheus + Grafana?
Prometheus is the CNCF standard for Kubernetes monitoring. Grafana provides visualization. Together they're the most widely adopted open-source monitoring stack — and they're what a team would actually run alongside GKE.

### Why the RED Method?
RED focuses on what matters for request-driven services: how many requests are we getting (Rate), how many are failing (Errors), and how long they take (Duration). This directly maps to user experience and SLO targets.

### Why Hand-Written Middleware?
The ~30-line middleware class is intentional. Libraries like `prometheus-fastapi-instrumentator` work fine, but hand-written middleware means I can explain every metric label and every line in an interview. It also demonstrates understanding of ASGI middleware, label cardinality, and route template resolution.

### Metrics Exposed

| Metric | Type | Labels | Purpose |
|--------|------|--------|---------|
| `http_requests_total` | Counter | method, endpoint, status | Request rate + error rate |
| `http_request_duration_seconds` | Histogram | method, endpoint | Latency percentiles (p50/p95/p99) |
| `http_requests_in_progress` | Gauge | method, endpoint | Current concurrency / saturation |

### Key Design Details
- **Path label uses route template** (`/items/{item_id}`) not resolved path (`/items/42`) — prevents label cardinality explosion, a real production concern that would overwhelm Prometheus
- **Prometheus service discovery via annotations** — app pods get `prometheus.io/scrape: "true"`, Prometheus finds them automatically via Kubernetes SD
- **ClusterIP for both services** — no external access; use `kubectl port-forward` for debugging
- **emptyDir for Prometheus storage** — simplification for portfolio; production would use a PersistentVolumeClaim
- **Grafana admin password via K8s Secret** — loaded via `secretKeyRef`; production would use the Secrets Store CSI Driver to sync directly from GCP Secret Manager

### Grafana Dashboard
A pre-provisioned "FastAPI — RED Method" dashboard with 4 panels:
1. **Request Rate** — `sum(rate(http_requests_total[5m])) by (endpoint)`
2. **Error Rate (5xx)** — filtered to 5xx status codes only
3. **Request Duration** — p50, p95, p99 latency percentiles
4. **Requests In Progress** — current concurrency gauge

The dashboard loads automatically via Grafana's provisioning system (ConfigMap → volume mount → file provider).

## Security Hardening

Defense-in-depth applied at every layer: infrastructure (VPC, firewall, private cluster), workload (pod security, network policies), and secrets (Secret Manager, no hardcoded credentials).

### Pod Security Standards

All namespaces enforce the PSA `restricted` profile — the strictest built-in level in Kubernetes 1.25+. This requires:
- Containers run as non-root
- Read-only root filesystem
- All Linux capabilities dropped
- Seccomp profile set to `RuntimeDefault`
- No privilege escalation

**Why `restricted` over `baseline`?** Our containers already comply (Prometheus runs as UID 65534, Grafana as UID 472, the FastAPI app as a dedicated `appuser`). There's no reason to use a weaker profile when the workloads already meet the strictest standard.

**Why PSA over OPA/Gatekeeper?** PSA is built into Kubernetes — zero extra infrastructure to deploy, maintain, or troubleshoot. It validates the same constraints. For a platform without custom admission policies, PSA is the right tool.

### Network Policies

Default deny-all on every namespace, with explicit allow policies for each legitimate traffic flow. This is the same zero-trust principle as the VPC deny-all firewall rule from the networking module — nothing communicates unless explicitly allowed.

| Policy | Namespace | What it allows |
|--------|-----------|----------------|
| `default-deny-all` | monitoring | Blocks all ingress + egress (baseline) |
| `allow-dns` | monitoring | UDP/TCP port 53 for service name resolution |
| `allow-grafana-to-prometheus` | monitoring | Grafana → Prometheus on port 9090 |
| `allow-prometheus-scrape` | monitoring | Prometheus → pod network for metrics collection |
| `allow-prometheus-apiserver` | monitoring | Prometheus → kube-apiserver (172.16.0.0/28) for service discovery |
| `default-deny-all` | app | Blocks all ingress + egress (baseline) |
| `allow-app-egress` | app | App → Cloud SQL private IP (5432) + DNS |
| `allow-prometheus-scrape` | app | Prometheus (monitoring ns) → app pods on port 8080 |

**One policy per file** — makes it auditable. "Who can talk to the database?" → read one file.

### Secret Management

| Layer | Before | After |
|-------|--------|-------|
| Database password | Hardcoded `"changeme..."` in Terraform | `var.db_password` (sensitive) → Secret Manager |
| Grafana password | Hardcoded `admin` in deployment YAML | K8s Secret → `secretKeyRef` in deployment |
| Secret storage | None | GCP Secret Manager with IAM-based access |
| Pod access | N/A | Workload Identity → `secretmanager.secretAccessor` role |

**Why Secret Manager over Vault?** Secret Manager is a managed GCP service — no infrastructure to operate. It's IAM-integrated, which pairs directly with the Workload Identity setup from Project 1. The app's GCP service account already exists; we just grant it `secretAccessor`.

**Why K8s Secret for Grafana (not CSI driver)?** The Secrets Store CSI Driver + GCP provider is the production path — it syncs secrets from Secret Manager directly into the pod without a K8s Secret object. But the CSI driver requires CRDs that won't validate in CI without a running cluster. The K8s Secret pattern here demonstrates the same `secretKeyRef` flow and validates cleanly. The README documents the upgrade path.

### Container Image Scanning

Trivy runs in CI on every Docker build and every Terraform/K8s config change:
- **Image scan**: Checks the built container for CVEs in OS packages and application dependencies (CRITICAL + HIGH severity gate)
- **IaC scan**: Checks Terraform and Kubernetes manifests for misconfigurations (CRITICAL + HIGH severity gate)

**Why Trivy over Snyk/Grype?** Open source, first-party GitHub Action, scans both container images and IaC configs in one tool. No API keys or paid accounts needed.

## CI/CD

GitHub Actions runs on every code change — no manual validation needed.

| Workflow | Trigger | What it does |
|----------|---------|--------------|
| **Terraform CI** | Pull request → `main` | Format check → Init + Validate → Plan (posted as PR comment) |
| **Docker CI** | Push to `main` / PR touching `app/` | Builds the container image + Trivy vulnerability scan |
| **K8s Manifest Lint** | PR touching `k8s/` | Validates all manifests with kubeconform |
| **Security Scan** | PR touching `modules/`, `environments/`, `k8s/` | Trivy IaC misconfiguration scan on Terraform + K8s configs |

The Terraform CI pipeline uses a read-only service account (`terraform-ci`) that can run `terraform plan` but never create or modify resources. Production would replace the JSON key with [Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation) for keyless authentication.

## Project Structure

```
gcp-infrastructure/
├── .github/workflows/         # CI/CD pipelines
│   ├── terraform-ci.yml       # Terraform validation on PRs
│   ├── docker-ci.yml          # Docker build + Trivy image scan
│   ├── k8s-lint.yml           # K8s manifest validation with kubeconform
│   └── security-scan.yml      # Trivy IaC misconfiguration scan
├── modules/                   # Reusable Terraform modules
│   ├── networking/            # VPC, subnets, firewall rules
│   ├── iam/                   # Service accounts, role bindings
│   ├── gke/                   # GKE Autopilot cluster
│   ├── database/              # Cloud SQL Postgres
│   ├── secrets/               # GCP Secret Manager + IAM bindings
│   └── budget/                # Billing budget alerts
├── environments/
│   └── dev/                   # Dev environment wiring
├── k8s/
│   ├── monitoring/            # Monitoring stack (Prometheus + Grafana)
│   │   ├── namespace.yaml     # Namespace with PSA restricted labels
│   │   ├── network-policies/  # Network policies (default-deny + allow rules)
│   │   ├── prometheus/        # Prometheus (deployment, RBAC, config, service)
│   │   └── grafana/           # Grafana (deployment, secret, configs, service)
│   └── app/                   # Application namespace
│       ├── namespace.yaml     # Namespace with PSA restricted labels
│       └── network-policies/  # Network policies (default-deny + allow rules)
├── app/                       # FastAPI application + Dockerfile
└── docs/                      # Validation artifacts
```

## Validation

```bash
# Format check
terraform fmt -check -recursive

# Syntax and logic validation
cd environments/dev
terraform init
terraform validate

# Full execution plan (no resources created)
terraform plan

# App container build
cd app
docker build -t gcp-infra-app .
docker run -p 8080:8080 gcp-infra-app
```

## The Application

A FastAPI microservice with:
- `/health` — Liveness probe (is the process alive?)
- `/ready` — Readiness probe (can we reach the database?)
- `/status` — App metadata for monitoring
- `/items` — CRUD operations on a Postgres-backed resource
- `/metrics` — Prometheus metrics (request rate, error rate, latency histograms)

Built with 12-factor principles: configuration via environment variables, stateless processes, and a multi-stage Docker build running as a non-root user.

## What I'd Add in Production

- ~~**Monitoring** (Project 3): Prometheus + Grafana on GKE for metrics and alerting~~ **Done** — see [Monitoring & Observability](#monitoring--observability) above
- ~~**Security hardening** (Project 4): Network policies, pod security, secret management, container scanning~~ **Done** — see [Security Hardening](#security-hardening) above
- **Secrets Store CSI Driver**: Sync secrets directly from GCP Secret Manager into pods, eliminating K8s Secret objects entirely
- **Alerting rules**: Prometheus alertmanager with PagerDuty/Slack integration for SLO breaches
- **Persistent storage for Prometheus**: PersistentVolumeClaim instead of emptyDir
- **Multi-region**: Regional GKE clusters with global load balancing
- **DNS + TLS**: Cloud DNS + managed certificates via cert-manager
- **Workload Identity Federation**: Replace CI service account key with keyless auth
