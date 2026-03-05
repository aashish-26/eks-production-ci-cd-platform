# Production-Grade EKS CI/CD Platform — Project Guide

## Table of Contents

1. [What This Project Is](#what-this-project-is)
2. [Architecture Diagram](#architecture-diagram)
3. [Project Flow (End-to-End)](#project-flow-end-to-end)
4. [Technology Choices & Why](#technology-choices--why)
5. [Component Breakdown](#component-breakdown)
   - [app/ - The Application](#app---the-application)
   - [terraform/ - Infrastructure as Code](#terraform---infrastructure-as-code)
   - [helm/app-chart/ - Kubernetes Manifest Templates](#helmapp-chart---kubernetes-manifest-templates)
6. [GitHub Actions Setup (Step-by-Step)](#github-actions-setup-step-by-step)
   - [Prerequisites](#prerequisites)
   - [Step 1 - Create the GitHub OIDC Provider in AWS](#step-1---create-the-github-oidc-provider-in-aws)
   - [Step 2 - Create the IAM Role for GitHub Actions](#step-2---create-the-iam-role-for-github-actions)
   - [Step 3 - Attach Required Permissions to the Role](#step-3---attach-required-permissions-to-the-role)
   - [Step 4 - Grant the IAM Role K8s RBAC Access](#step-4---grant-the-iam-role-k8s-rbac-access)
   - [Step 5 - Add GitHub Repository Secrets](#step-5---add-github-repository-secrets)
   - [Step 6 - Push to Main and Watch the Pipeline](#step-6---push-to-main-and-watch-the-pipeline)
7. [How to Run the Full Project](#how-to-run-the-full-project)
   - [0. Prerequisites (install once)](#0-prerequisites-install-once)
   - [1. Bootstrap Remote State (once per AWS account)](#1-bootstrap-remote-state-once-per-aws-account)
   - [2. Provision Infrastructure](#2-provision-infrastructure)
   - [3. Install PostgreSQL (one-time, in-cluster)](#3-install-postgresql-one-time-in-cluster)
   - [4. Run Locally](#4-run-locally)
   - [5. Trigger the Pipeline](#5-trigger-the-pipeline)
   - [6. Verify Deployment](#6-verify-deployment)
8. [Completeness Status](#completeness-status)
9. [Security Notes](#security-notes)

---

## What This Project Is

This project is a **production-grade container platform on AWS** built around an automated GitOps-style CI/CD pipeline. It demonstrates how a real engineering team would ship, secure, and operate a microservice at scale.

A **Node.js REST API** application is:

- Packaged inside a **Docker** multi-stage image (Alpine-based, non-root user)
- Stored and versioned in **Amazon ECR** (Elastic Container Registry)
- Deployed to an **Amazon EKS** (Elastic Kubernetes Service) cluster via **Helm**
- All of the above is triggered **automatically on every `git push` to `main`** via a **GitHub Actions** workflow

Infrastructure is defined entirely in **Terraform**, the Kubernetes workload is templated in **Helm**, and no static AWS credentials are stored anywhere — authentication uses AWS OIDC federation with short-lived tokens.

---

## Architecture Diagram

```
+------------------+
|  Developer       |
|  Laptop          |
|                  |
|  git push main   |
+--------+---------+
         |
         v
+--------+----------------------------------------------------+
|  GitHub Actions CI/CD Pipeline                              |
|                                                             |
|  1. checkout         6. ECR push                           |
|  2. npm ci           7. Trivy scan (block on CRITICAL)     |
|  3. docker build     8. helm upgrade --install             |
|  4. AWS OIDC auth    9. smoke test (GET /health via ALB)   |
|  5. ECR login       10. pass/fail                          |
+--------+----------------------------------------------------+
         |
         v
+--------+----------------------------------------------------+
|  AWS Cloud                                                  |
|                                                             |
|  +-------------------+    +-----------------------------+  |
|  |  Amazon ECR       |    |  VPC                        |  |
|  |  (image registry) |    |  +-------------------------+|  |
|  +-------------------+    |  |  EKS Cluster            ||  |
|                           |  |                         ||  |
|  +-------------------+    |  |  app pods (x2-5)        ||  |
|  |  AWS ALB          |    |  |  postgres               ||  |
|  |  (public ingress) |--->|  |  aws-lb-controller      ||  |
|  +-------------------+    |  |  (kube-system)          ||  |
|          ^                |  +-------------------------+|  |
|          |                +-----------------------------+  |
|     Internet                                               |
+------------------------------------------------------------+

Traffic path:
  Internet --> AWS ALB --> Service (ClusterIP:80) --> pods:8080
```

---

## Project Flow (End-to-End)

The following 15 steps describe the complete lifecycle of a change from a developer's machine to live production traffic:

1. **Developer pushes to `main`** — a `git push origin main` is executed from the local workstation.

2. **GitHub Actions triggers** — the `.github/workflows/ci-cd.yml` workflow is activated by the `push` event on the `main` branch.

3. **Checkout** — the `actions/checkout` step clones the repository at the exact commit SHA into the runner environment.

4. **`npm ci`** — runs inside the `app/` directory to perform a clean, reproducible install of all Node.js dependencies from `package-lock.json`.

5. **Derive image tag from commit SHA (7 chars)** — the image tag is set to the first 7 characters of `GITHUB_SHA` (e.g., `a3f9c12`), ensuring every image is uniquely and traceably versioned.

6. **AWS OIDC authentication (no static credentials)** — GitHub's Actions runner presents a short-lived OIDC JWT token to AWS STS. AWS validates the token against the IAM OIDC provider configured for `token.actions.githubusercontent.com` and issues temporary credentials for the designated IAM role. No AWS access keys are stored in GitHub Secrets.

7. **ECR login** — the runner authenticates to Amazon ECR using the temporary credentials obtained in the previous step via `aws ecr get-login-password | docker login`.

8. **Docker build** — the image is built using the `app/` directory as the Docker build context. The `Dockerfile` uses a multi-stage build on Alpine Linux and runs the application as a non-root user for security.

9. **Push to ECR** — the newly built image (tagged with the commit SHA) is pushed to the ECR repository.

10. **Trivy scan** — the Aqua Security Trivy vulnerability scanner scans the image for known CVEs. The pipeline is **blocked and fails** if any `CRITICAL` severity vulnerabilities are found.

11. **Update kubeconfig for EKS** — `aws eks update-kubeconfig` updates the runner's kubeconfig so that subsequent `kubectl` and `helm` commands target the correct cluster.

12. **`helm upgrade --install`** — Helm renders and applies the chart, which creates or updates the following Kubernetes resources: `Deployment`, `Service`, `Ingress`, `HorizontalPodAutoscaler` (HPA), and `PodDisruptionBudget` (PDB).

13. **ALB controller provisions AWS ALB** — the AWS Load Balancer Controller running in `kube-system` watches for new `Ingress` resources and automatically provisions an AWS Application Load Balancer with the appropriate listener rules and target groups.

14. **Smoke test** — the pipeline polls `GET /health` via the ALB hostname with up to **10 retries** and a **15-second gap** between each attempt, confirming the new pods are live and responding before marking the pipeline as successful.

15. **Traffic flows** — live traffic flows: `Internet → ALB → Service (ClusterIP:80) → pods:8080`.

---

## Technology Choices & Why

| Technology | What We Use It For | Why This Choice |
|---|---|---|
| **AWS EKS** | Managed Kubernetes control plane | Eliminates control plane operational burden; integrates natively with IAM, ALB, and EBS/EFS |
| **Terraform** | Provisioning all AWS infrastructure (VPC, EKS, ECR, ALB) | Declarative, reproducible IaC; state locking via S3 + DynamoDB prevents concurrent drift |
| **Helm** | Templating and packaging Kubernetes manifests | Parameterizes environment-specific values (image tag, replicas) without duplicating YAML; enables atomic upgrades and rollbacks |
| **GitHub Actions** | CI/CD pipeline execution | Native GitHub integration; OIDC federation eliminates stored credentials; large action marketplace |
| **AWS OIDC + IAM role** | Authenticating the pipeline to AWS | Zero static secrets; tokens are short-lived and scoped to specific branches; industry best practice |
| **Amazon ECR** | Private Docker image registry | Same AWS account; IAM-controlled access; automatic scan on push; no registry credentials to manage |
| **AWS ALB + ALB Controller** | Exposing the application to the internet | ALB natively integrates with EKS; supports path/host routing, TLS termination, and WAF attachment |
| **HPA** | Horizontal Pod Autoscaler for the app | Automatically scales pod count 2-5 based on CPU utilization, handling traffic spikes without manual intervention |
| **PDB** | PodDisruptionBudget | Guarantees at least 1 pod remains available during node drains or rolling upgrades, preventing full outages |
| **Trivy** | Container image CVE scanning | Fast, accurate, open-source; blocks the pipeline on CRITICAL vulnerabilities before images reach production |
| **Pino** | Structured JSON logging in the Node.js app | Extremely low-overhead logger; outputs structured JSON natively, which is required for log aggregation tools (CloudWatch, Datadog) |
| **prom-client** | Prometheus metrics exposition | De facto standard Node.js client; exposes `GET /metrics` in the format expected by Prometheus and Grafana |
| **Bitnami PostgreSQL** | In-cluster relational database (dev/staging) | Mature, battle-tested Helm chart; supports password secrets, persistence, and resource limits out of the box |

---

## Component Breakdown

### app/ - The Application

**Directory tree:**

```
app/
├── Dockerfile
├── docker-compose.yml
├── .env.example
├── package.json
├── package-lock.json
└── src/
    ├── index.js          # Express server entry point
    ├── db.js             # PostgreSQL connection pool (pg)
    ├── routes/
    │   ├── health.js     # GET /health and GET /ready
    │   ├── orders.js     # GET /orders
    │   └── metrics.js    # GET /metrics (prom-client)
    └── logger.js         # Pino structured JSON logger
```

**File explanations:**

- `Dockerfile` — Multi-stage build. Stage 1 (`builder`) installs all dependencies with `npm ci`. Stage 2 (`runtime`) copies only production artifacts onto a minimal Alpine image and switches to a non-root user (`node`).
- `docker-compose.yml` — Local development only. Brings up the Node.js app alongside a PostgreSQL container with environment variables wired together, enabling full local integration testing with a single command.
- `.env.example` — Template for local environment variables (`PORT`, `DATABASE_URL`, etc.). Should never contain real secrets; developers copy this to `.env` which is git-ignored.
- `package.json` — Declares dependencies (`express`, `pg`, `pino`, `prom-client`) and the `start` script.
- `src/index.js` — Creates and configures the Express application, registers all route handlers, and starts the HTTP server on `process.env.PORT` (default `8080`).
- `src/db.js` — Initialises a `pg.Pool` from `DATABASE_URL`. Exports a `query()` helper used by routes that need database access.
- `src/logger.js` — Exports a configured Pino logger instance with `level: 'info'` and JSON output, used consistently across all modules.

**Endpoints:**

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/health` | **Liveness probe** — returns `200 OK` immediately; confirms the process is running |
| `GET` | `/ready` | **Readiness probe** — performs a `SELECT 1` against PostgreSQL; returns `200` only when the database connection is healthy |
| `GET` | `/orders` | Returns mock order data as JSON; simulates a real business endpoint |
| `GET` | `/metrics` | Exposes Prometheus-format metrics scraped by `prom-client` (default Node.js process metrics + any custom counters/histograms) |

---

### terraform/ - Infrastructure as Code

**Directory tree:**

```
terraform/
├── environments/
│   └── dev/
│       ├── main.tf               # Root module; calls child modules
│       ├── variables.tf
│       ├── outputs.tf
│       ├── terraform.tfvars.example
│       └── bootstrap-state.sh    # Creates S3 bucket + DynamoDB table for remote state
└── modules/
    ├── vpc/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── ecr/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── eks/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    └── alb/
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

**Module descriptions:**

- **`vpc`** — Creates the foundational network layer: a VPC with public and private subnets across multiple Availability Zones, an Internet Gateway, NAT Gateways for private subnet egress, and the necessary route tables. All subnets are tagged appropriately for EKS and ALB auto-discovery.

- **`ecr`** — Provisions an Amazon ECR private repository for the application Docker image. Configures image scanning on push and sets a lifecycle policy to expire untagged images older than 30 days, preventing unbounded registry growth.

- **`eks`** — Creates the EKS cluster (control plane) and managed node groups (EC2 worker nodes). Configures IAM roles for the cluster and nodes, enables IRSA (IAM Roles for Service Accounts) via the OIDC provider on the cluster, and outputs the cluster endpoint and certificate authority data needed by `kubectl`.

- **`alb`** — Deploys the **AWS Load Balancer Controller** into the EKS cluster as a Helm release. This controller watches Kubernetes `Ingress` resources and automatically provisions and configures AWS Application Load Balancers. Requires an IAM role annotated on its ServiceAccount (IRSA) with permissions to manage ALB resources.

**Module dependency order:**

```
vpc ──┬──> eks ──> alb
      └──> ecr
```

The `vpc` module must be applied first as both `eks` and `ecr` depend on subnet and VPC IDs it outputs. The `alb` module depends on the EKS cluster being available to deploy the Helm chart into.

---

### helm/app-chart/ - Kubernetes Manifest Templates

**Directory tree:**

```
helm/app-chart/
├── Chart.yaml
├── values.yaml
└── templates/
    ├── _helpers.tpl
    ├── deployment.yaml
    ├── service.yaml
    ├── ingress.yaml
    ├── hpa.yaml
    └── pdb.yaml
```

**`_helpers.tpl` — Named Template Definitions:**

The `_helpers.tpl` file defines three reusable named templates that are referenced throughout every other template file:

1. **`eks-app.name`** — Returns the chart name (or an override from `nameOverride` in `values.yaml`), truncated to 63 characters to comply with Kubernetes DNS label length limits.

2. **`eks-app.fullname`** — Combines the Helm release name with the chart name (e.g., `my-release-eks-app`) to produce the full resource name used in `metadata.name` fields. Also truncated to 63 characters.

3. **`eks-app.labels`** — Emits the standard set of Kubernetes recommended labels applied to every resource: `helm.sh/chart`, `app.kubernetes.io/name`, `app.kubernetes.io/instance`, `app.kubernetes.io/managed-by`. Using this helper ensures consistent labeling across all manifests.

**Key `values.yaml` settings:**

| Key | Description |
|---|---|
| `image.repository` | Full ECR repository URI (e.g., `123456789.dkr.ecr.us-east-1.amazonaws.com/eks-app`). Set per environment. |
| `image.tag` | Docker image tag; overridden at deploy time by the pipeline to the 7-character commit SHA (e.g., `a3f9c12`). |
| `containerPort` | The port the Node.js process listens on inside the container. Default: `8080`. |
| `db.host` | PostgreSQL service hostname (e.g., `postgresql.database.svc.cluster.local`). Injected as an environment variable. |
| `db.passwordSecret` | Name of the Kubernetes `Secret` containing the database password key. Mounted as an environment variable via `secretKeyRef`. |

---

## GitHub Actions Setup (Step-by-Step)

### Prerequisites

Ensure the following tools are installed and configured on your local machine before beginning:

| Tool | Minimum Version | Install |
|---|---|---|
| AWS CLI | v2 | `https://aws.amazon.com/cli/` |
| Terraform | >= 1.5 | `https://developer.hashicorp.com/terraform/install` |
| kubectl | >= 1.27 | `https://kubernetes.io/docs/tasks/tools/` |
| Helm | >= 3.12 | `https://helm.sh/docs/intro/install/` |

---

### Step 1 - Create the GitHub OIDC Provider in AWS

This Terraform resource registers GitHub Actions as a trusted OIDC identity provider in your AWS account. It must exist before any IAM role trust policy can reference it.

```hcl
resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  # SHA-1 thumbprint of the GitHub Actions OIDC certificate root CA
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1"
  ]

  tags = {
    Name = "github-actions-oidc-provider"
  }
}
```

---

### Step 2 - Create the IAM Role for GitHub Actions

This role is assumed by the GitHub Actions runner via the OIDC provider. The trust policy restricts assumption to tokens issued specifically for pushes to the `main` branch of your repository.

```hcl
data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:YOUR_ORG/YOUR_REPO:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_actions_eks_deploy" {
  name               = "github-actions-eks-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json

  tags = {
    Name = "github-actions-eks-deploy"
  }
}
```

Replace `YOUR_ORG/YOUR_REPO` with your actual GitHub organisation and repository name (e.g., `acme-corp/platform-api`).

---

### Step 3 - Attach Required Permissions to the Role

The role needs two categories of permissions: ECR operations to push images, and EKS read access to update kubeconfig.

```hcl
resource "aws_iam_role_policy" "github_actions_permissions" {
  name = "github-actions-ci-cd-permissions"
  role = aws_iam_role.github_actions_eks_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRAuthToken"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRImageOperations"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = "arn:aws:ecr:*:*:repository/eks-app"
      },
      {
        Sid    = "EKSDescribeCluster"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster"
        ]
        Resource = "*"
      }
    ]
  })
}
```

---

### Step 4 - Grant the IAM Role K8s RBAC Access

Kubernetes RBAC is separate from AWS IAM. The IAM role must be mapped to a Kubernetes user/group inside the cluster via the `aws-auth` ConfigMap in the `kube-system` namespace.

Edit the ConfigMap with:

```bash
kubectl edit configmap aws-auth -n kube-system
```

Add the following entry under the `mapRoles` key:

```yaml
mapRoles: |
  - rolearn: arn:aws:iam::<ACCOUNT_ID>:role/github-actions-eks-deploy
    username: github-actions
    groups:
      - system:masters
```

Replace `<ACCOUNT_ID>` with your 12-digit AWS account ID.

**Note:** `system:masters` grants cluster-admin privileges. For production, consider creating a more restrictive ClusterRole bound only to the namespaces the pipeline needs to modify.

---

### Step 5 - Add GitHub Repository Secrets

Navigate to your GitHub repository: **Settings > Secrets and variables > Actions > New repository secret**

Add the following secrets:

| Secret Name | Value |
|---|---|
| `AWS_ROLE_TO_ASSUME` | `arn:aws:iam::<ACCOUNT_ID>:role/github-actions-eks-deploy` |
| `EKS_CLUSTER_NAME` | `eks-dev-cluster` |

These values are referenced in the workflow YAML as `${{ secrets.AWS_ROLE_TO_ASSUME }}` and `${{ secrets.EKS_CLUSTER_NAME }}` respectively.

---

### Step 6 - Push to Main and Watch the Pipeline

Trigger the pipeline with:

```bash
git add .
git commit -m "ci: trigger pipeline"
git push origin main
```

Navigate to **Actions** tab in your GitHub repository. A successful pipeline run will show the following steps completing in order:

```
[✓] Set up job
[✓] Checkout repository
[✓] Set up Node.js
[✓] Install dependencies (npm ci)
[✓] Configure AWS credentials (OIDC)
[✓] Login to Amazon ECR
[✓] Build and push Docker image
[✓] Scan image with Trivy
[✓] Update kubeconfig for EKS
[✓] Deploy with Helm
[✓] Smoke test - GET /health
```

Total pipeline duration is typically 4-7 minutes on a standard GitHub-hosted runner.

---

## How to Run the Full Project

### 0. Prerequisites (install once)

Verify all required tools are present:

```bash
aws --version
# aws-cli/2.x.x Python/3.x.x ...

terraform --version
# Terraform v1.5.x

kubectl version --client
# Client Version: v1.27.x

helm version
# version.BuildInfo{Version:"v3.12.x", ...}
```

---

### 1. Bootstrap Remote State (once per AWS account)

Terraform requires an S3 bucket and DynamoDB table for remote state storage before `terraform init` can run.

```bash
cd terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your AWS region, account ID, etc.

bash bootstrap-state.sh
# Creates:
#   S3 bucket:        terraform-state-<account-id>-<region>
#   DynamoDB table:   terraform-state-lock
```

This only needs to be run once per AWS account. Subsequent `terraform` commands use this backend automatically.

---

### 2. Provision Infrastructure

```bash
cd terraform/environments/dev

terraform init
# Initialises providers and downloads modules

terraform plan
# Previews all resources to be created (~40-50 resources)
# Review carefully before proceeding

terraform apply
# Type 'yes' when prompted
# Takes approximately 15-20 minutes (EKS cluster creation dominates)

# Once complete, configure kubectl
aws eks update-kubeconfig \
  --region us-east-1 \
  --name eks-dev-cluster

# Verify nodes are Ready
kubectl get nodes
# NAME                          STATUS   ROLES    AGE   VERSION
# ip-10-0-1-x.ec2.internal      Ready    <none>   2m    v1.29.x
# ip-10-0-2-x.ec2.internal      Ready    <none>   2m    v1.29.x
```

---

### 3. Install PostgreSQL (one-time, in-cluster)

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

helm upgrade --install postgresql bitnami/postgresql \
  --namespace database \
  --create-namespace \
  --set auth.postgresPassword=changeme_in_prod \
  --set auth.database=ordersdb \
  --set primary.persistence.size=10Gi \
  --wait

# Verify PostgreSQL is running
kubectl get pods -n database
# NAME                    READY   STATUS    RESTARTS   AGE
# postgresql-0            1/1     Running   0          90s
```

**Important:** Replace `changeme_in_prod` with a strong, randomly generated password. Store it in AWS Secrets Manager or a similarly secure store before deploying to staging or production.

---

### 4. Run Locally

```bash
cd app
cp .env.example .env
# Edit .env if needed (default values work for docker-compose)

docker-compose up
# Starts the Node.js app on :8080 and PostgreSQL on :5432

# In another terminal, test the endpoints:
curl http://localhost:8080/health
# {"status":"ok"}

curl http://localhost:8080/orders
# [{"id":1,"item":"Widget","qty":10}, ...]

curl http://localhost:8080/ready
# {"status":"ok","db":"connected"}
```

---

### 5. Trigger the Pipeline

Push any change to the `main` branch:

```bash
git add .
git commit -m "feat: your change description"
git push origin main
```

Monitor the pipeline at `https://github.com/YOUR_ORG/YOUR_REPO/actions`.

---

### 6. Verify Deployment

```bash
# Check pods are running
kubectl get pods -n default
# NAME                        READY   STATUS    RESTARTS   AGE
# eks-app-7d9f8b6c4-abc12     1/1     Running   0          2m
# eks-app-7d9f8b6c4-def34     1/1     Running   0          2m

# Get the ALB hostname from the Ingress
kubectl get ingress -n default
# NAME      CLASS   HOSTS                    ADDRESS                              PORTS   AGE
# eks-app   alb     eks-app.example.com      k8s-xxxx.us-east-1.elb.amazonaws.com  80      3m

# Smoke test via ALB hostname
ALB_HOST=$(kubectl get ingress eks-app -n default \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

curl http://${ALB_HOST}/health
# {"status":"ok"}
```

---

## Completeness Status

| Phase | Description | Status | Notes |
|---|---|---|---|
| 1 | AWS Infrastructure (VPC, EKS, ECR) | Complete | All Terraform modules written and applied |
| 2 | Node.js Application | Complete | All endpoints, structured logging, Prometheus metrics |
| 3 | Docker / ECR | Complete | Multi-stage Dockerfile, ECR push workflow |
| 4 | Helm Chart | Complete | Deployment, Service, Ingress, HPA, PDB templates |
| 5 | GitHub Actions CI/CD | Mostly Complete | Workflow runs end-to-end; OIDC IaC not yet codified in Terraform |
| 6 | Observability | Partial | `/metrics` endpoint ready; Prometheus + Grafana Helm releases not yet provisioned in Terraform |
| 7 | Security Hardening | Mostly Complete | Non-root image, Trivy scanning, IRSA; real domain and credential rotation pending |

### What Still Remains

1. **EKS version update 1.29 to 1.30+** — EKS 1.29 is approaching end-of-life; the `eks` module must be updated and a node group rolling upgrade performed.

2. **Unit tests** — add a `test` script to `app/package.json` (e.g., using Jest or Mocha) and add a test step to the GitHub Actions workflow so that failing tests block the build.

3. **Cluster Autoscaler `helm_release`** — the Cluster Autoscaler is currently installed manually; it should be converted to a `helm_release` Terraform resource inside the `eks` module for reproducibility.

4. **Prometheus + Grafana `helm_release` in Terraform** — the `kube-prometheus-stack` chart should be provisioned via Terraform `helm_release` resources so that the monitoring stack is part of the infrastructure definition, not a manual step.

5. **ECR lifecycle policy resource** — add an `aws_ecr_lifecycle_policy` Terraform resource to the `ecr` module to automatically expire images older than a defined threshold and limit untagged image accumulation.

6. **GitHub OIDC IaC (`aws_iam_openid_connect_provider` + role)** — the OIDC provider and IAM role described in Steps 1-3 of this guide were applied manually and should be codified as Terraform resources and added to the `environments/dev` root module.

7. **Real domain** — replace the placeholder `eks-app.example.com` in `values.yaml` and the Ingress template with a real domain managed in Route 53, with a `CertificateManager` cert attached to the ALB for TLS termination.

8. **Remove `token.txt` file from repo and rotate the credential** — a file containing a credential was accidentally committed. It must be removed from the entire git history using `git filter-repo` or BFG Repo Cleaner, and the exposed credential must be immediately rotated/revoked.

---

## Security Notes

| Control | Implementation |
|---|---|
| **No static AWS keys** | GitHub Actions authenticates via AWS OIDC federation. The pipeline receives short-lived STS tokens scoped to a single IAM role; no `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` is stored in GitHub Secrets or the codebase. |
| **Non-root container** | The `Dockerfile` creates a dedicated `node` user and switches to it with `USER node` before the `CMD` instruction. The application process never runs as UID 0 inside the container. |
| **Image CVE scanning** | Trivy is invoked in the CI pipeline immediately after the image is pushed to ECR. The pipeline step is configured with `exit-code: 1` on `CRITICAL` severity, blocking any deployment of images with known critical vulnerabilities. |
| **ECR scan on push** | ECR is configured with `scan_on_push = true`, providing a secondary vulnerability scan independent of the CI pipeline, with results visible in the AWS Console. |
| **IRSA for ALB controller** | The AWS Load Balancer Controller uses an IAM Role for Service Accounts (IRSA). Its Kubernetes `ServiceAccount` is annotated with the IAM role ARN, and the role trust policy is scoped to that specific service account — no node-level IAM permissions are used. |
| **DB password from K8s Secret** | The PostgreSQL password is stored in a Kubernetes `Secret` and injected into the application pod as an environment variable via `secretKeyRef`. The password is never hardcoded in `values.yaml`, Helm templates, or application source code. |
| **PDB prevents full outage** | A `PodDisruptionBudget` with `minAvailable: 1` is deployed alongside the application. This ensures that voluntary disruptions (node drains, cluster upgrades) cannot take down all application replicas simultaneously, maintaining availability during maintenance windows. |
