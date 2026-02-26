# GCP Infrastructure — Terraform IaC + Monitoring

Production-grade GCP infrastructure defined entirely in Terraform, with Prometheus + Grafana observability. Demonstrates VPC networking, GKE Autopilot, Cloud SQL, IAM least-privilege, application instrumentation with RED method metrics, and a containerized FastAPI application — all validated via `terraform plan` with zero cloud spend.

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
- **Grafana admin password hardcoded** — deliberate simplification; production would use GCP Secret Manager

### Grafana Dashboard
A pre-provisioned "FastAPI — RED Method" dashboard with 4 panels:
1. **Request Rate** — `sum(rate(http_requests_total[5m])) by (endpoint)`
2. **Error Rate (5xx)** — filtered to 5xx status codes only
3. **Request Duration** — p50, p95, p99 latency percentiles
4. **Requests In Progress** — current concurrency gauge

The dashboard loads automatically via Grafana's provisioning system (ConfigMap → volume mount → file provider).

## CI/CD

GitHub Actions runs on every code change — no manual validation needed.

| Workflow | Trigger | What it does |
|----------|---------|--------------|
| **Terraform CI** | Pull request → `main` | Format check → Init + Validate → Plan (posted as PR comment) |
| **Docker CI** | Push to `main` / PR touching `app/` | Builds the container image to verify the app still compiles |
| **K8s Manifest Lint** | PR touching `k8s/` | Validates all manifests with `kubectl --dry-run=client` |

The Terraform CI pipeline uses a read-only service account (`terraform-ci`) that can run `terraform plan` but never create or modify resources. Production would replace the JSON key with [Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation) for keyless authentication.

## Project Structure

```
gcp-infrastructure/
├── .github/workflows/         # CI/CD pipelines
│   ├── terraform-ci.yml       # Terraform validation on PRs
│   ├── docker-ci.yml          # Docker build on merge + PRs touching app/
│   └── k8s-lint.yml           # K8s manifest validation on PRs touching k8s/
├── modules/                   # Reusable Terraform modules
│   ├── networking/            # VPC, subnets, firewall rules
│   ├── iam/                   # Service accounts, role bindings
│   ├── gke/                   # GKE Autopilot cluster
│   ├── database/              # Cloud SQL Postgres
│   └── budget/                # Billing budget alerts
├── environments/
│   └── dev/                   # Dev environment wiring
├── k8s/monitoring/            # Kubernetes monitoring stack
│   ├── namespace.yaml         # Dedicated monitoring namespace
│   ├── prometheus/            # Prometheus server
│   │   ├── rbac.yaml          # ServiceAccount + ClusterRole
│   │   ├── configmap.yaml     # Scrape config with K8s service discovery
│   │   ├── deployment.yaml    # Prometheus pod (health probes, resource limits)
│   │   └── service.yaml       # ClusterIP service
│   └── grafana/               # Grafana dashboards
│       ├── configmap-datasource.yaml          # Auto-provision Prometheus
│       ├── configmap-dashboard-provider.yaml  # Dashboard file provider
│       ├── configmap-dashboard.yaml           # FastAPI RED method dashboard
│       ├── deployment.yaml    # Grafana pod with provisioning mounts
│       └── service.yaml       # ClusterIP service
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
- **Security hardening** (Project 4): Kubernetes network policies, pod security standards, secret management via Secret Manager
- **Alerting rules**: Prometheus alertmanager with PagerDuty/Slack integration for SLO breaches
- **Persistent storage for Prometheus**: PersistentVolumeClaim instead of emptyDir
- **Grafana secrets**: Admin password via GCP Secret Manager instead of hardcoded value
- **Multi-region**: Regional GKE clusters with global load balancing
- **Secret management**: Replace hardcoded DB password with GCP Secret Manager
- **DNS + TLS**: Cloud DNS + managed certificates via cert-manager
- **Workload Identity Federation**: Replace CI service account key with keyless auth
