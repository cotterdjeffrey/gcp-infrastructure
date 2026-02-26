# GCP Infrastructure — Terraform IaC

Production-grade GCP infrastructure defined entirely in Terraform. Demonstrates VPC networking, GKE Autopilot, Cloud SQL, IAM least-privilege, and a containerized FastAPI application — all validated via `terraform plan` with zero cloud spend.

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

## CI/CD

GitHub Actions runs on every code change — no manual validation needed.

| Workflow | Trigger | What it does |
|----------|---------|--------------|
| **Terraform CI** | Pull request → `main` | Format check → Init + Validate → Plan (posted as PR comment) |
| **Docker CI** | Push to `main` | Builds the container image to verify the app still compiles |

The Terraform CI pipeline uses a read-only service account (`terraform-ci`) that can run `terraform plan` but never create or modify resources. Production would replace the JSON key with [Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation) for keyless authentication.

## Project Structure

```
gcp-infrastructure/
├── .github/workflows/    # CI/CD pipelines
│   ├── terraform-ci.yml  # Terraform validation on PRs
│   └── docker-ci.yml     # Docker build on merge to main
├── modules/              # Reusable Terraform modules
│   ├── networking/       # VPC, subnets, firewall rules
│   ├── iam/              # Service accounts, role bindings
│   ├── gke/              # GKE Autopilot cluster
│   ├── database/         # Cloud SQL Postgres
│   └── budget/           # Billing budget alerts
├── environments/
│   └── dev/              # Dev environment wiring
├── app/                  # FastAPI application + Dockerfile
└── docs/                 # Validation artifacts
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

Built with 12-factor principles: configuration via environment variables, stateless processes, and a multi-stage Docker build running as a non-root user.

## What I'd Add in Production

- **Monitoring** (Project 3): Prometheus + Grafana on GKE for metrics and alerting
- **Security hardening** (Project 4): Kubernetes network policies, pod security standards, secret management via Secret Manager
- **Multi-region**: Regional GKE clusters with global load balancing
- **Secret management**: Replace hardcoded DB password with GCP Secret Manager
- **DNS + TLS**: Cloud DNS + managed certificates via cert-manager
- **Workload Identity Federation**: Replace CI service account key with keyless auth
