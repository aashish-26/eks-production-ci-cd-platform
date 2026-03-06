# Interview Prep — EKS CI/CD Platform

Questions and answers based on real decisions made in this project.

---

## Architecture & Design

**Q: Walk me through the architecture of this project.**

The platform runs a Node.js REST API on AWS EKS. Infrastructure is provisioned with Terraform across three layers — networking (VPC, subnets), compute (EKS cluster and managed node groups), and supporting services (ECR, ALB controller, Cluster Autoscaler). The application is packaged as a Docker image, stored in ECR, and deployed to Kubernetes via Helm. GitHub Actions handles the full CI/CD pipeline using OIDC authentication — no static AWS credentials. Traffic enters through an AWS ALB, which routes to the app pods via NodePort. PostgreSQL runs in a separate namespace. Prometheus and Grafana provide observability.

---

**Q: Why did you choose EKS over ECS or a self-managed cluster?**

EKS provides managed Kubernetes control plane — AWS handles upgrades, availability, and etcd backups. Compared to ECS, Kubernetes gives portability across clouds and a richer ecosystem (Helm, operators, KEDA, etc.). Compared to self-managed K8s (kops, kubeadm), EKS eliminates the operational overhead of running the control plane. It also integrates natively with AWS services — ALB Ingress Controller, IRSA, EBS CSI driver — which we use throughout this project.

---

**Q: Why did you add the AWS Load Balancer Controller (ALB)?**

Kubernetes by default provisions a Classic Load Balancer or NLB for `LoadBalancer` type services, but those are less efficient and feature-limited. The ALB Ingress Controller creates an Application Load Balancer from an `Ingress` resource, which gives:
- Path-based and host-based routing
- Native integration with AWS WAF, ACM (TLS), and Cognito
- Target type `ip` (direct pod routing) or `instance` (NodePort-based)
- A single ALB shared across multiple services, reducing cost

Without it, each service would need its own load balancer.

---

**Q: Why did you add the Cluster Autoscaler?**

Without Cluster Autoscaler, the node group stays at a fixed size. When the HPA scales pods up and there's not enough node capacity, new pods stay in `Pending` state indefinitely. Cluster Autoscaler watches for pending pods and triggers EC2 Auto Scaling Group changes to add or remove nodes. This means the cluster right-sizes itself under load rather than requiring manual intervention.

---

**Q: Why did you use Helm instead of plain Kubernetes YAML?**

Plain YAML would mean duplicating manifests for every environment or every image tag change. Helm provides:
- **Templating** — `{{ .Values.image.tag }}` injected at deploy time, so CI only needs `--set image.tag=sha-abc123`
- **Release management** — `helm upgrade --install` handles first deploy and subsequent updates in one command, with rollback via `helm rollback`
- **Packaging** — the entire application (Deployment, Service, Ingress, ConfigMap, Secret, HPA, PDB, ServiceAccount) is one versioned unit
- **Values overrides** — the same chart works for dev and prod with different values files

---

**Q: Why separate `database` and `default` namespaces for PostgreSQL and the app?**

Namespace separation gives isolation — network policies, RBAC, and resource quotas can be scoped independently. It also reflects ownership: the database is a shared infrastructure concern while the app namespace is owned by the application team. In production you would use ExternalSecrets or Vault to share credentials across namespaces rather than copying secrets.

---

## Kubernetes Concepts

**Q: What is IRSA and why did you use it?**

IRSA (IAM Roles for Service Accounts) lets Kubernetes pods assume AWS IAM roles without distributing static credentials. It works by:
1. EKS creates an OIDC identity provider
2. A trust policy on the IAM role allows `sts:AssumeRoleWithWebIdentity` from a specific service account
3. The EKS Pod Identity webhook injects `AWS_WEB_IDENTITY_TOKEN_FILE` into the pod
4. The AWS SDK exchanges the token for temporary STS credentials

We used IRSA for the ALB controller (needs EC2 and ELB permissions) and the Cluster Autoscaler (needs Auto Scaling Group permissions). No credentials stored in Kubernetes secrets.

---

**Q: What is the difference between a Liveness probe and a Readiness probe?**

| Probe | Action on failure | Purpose |
|---|---|---|
| Liveness | Kubernetes **restarts** the container | Detect deadlocks — process is stuck, not serving |
| Readiness | Kubernetes **removes pod from Service endpoints** | Detect temporary unavailability — pod is alive but not ready for traffic |

In this project:
- Liveness hits `GET /health` — fast, no external dependency, just confirms the process is alive
- Readiness hits `GET /ready` — tests the PostgreSQL connection; if the DB is unreachable, the pod stops receiving traffic but is not restarted

---

**Q: What is a PodDisruptionBudget and why did you add one?**

A PDB defines how many pods of a deployment can be voluntarily disrupted at once — for example during a node drain or cluster upgrade. Without a PDB, a node drain could evict all pods of a deployment simultaneously, causing downtime. We set `maxUnavailable: 1`, so at most one pod can be down at any time. This guarantees at least one pod is always serving traffic during rolling node replacements.

---

**Q: What is the difference between `target-type: ip` and `target-type: instance` for the ALB?**

| | `target-type: ip` | `target-type: instance` |
|---|---|---|
| Traffic path | ALB → Pod IP:containerPort | ALB → NodeIP:NodePort → kube-proxy → Pod |
| Service type needed | ClusterIP | NodePort or LoadBalancer |
| Security group | ALB controller must open ALB SG → node SG on containerPort | ALB controller must open ALB SG → node SG on NodePort range |
| Latency | Lower (one less hop) | Slightly higher |

We switched from `ip` to `instance` because the IAM policy permission for `ec2:AuthorizeSecurityGroupIngress` had a tag condition that restricted it to ALB-owned security groups. The node SG is EKS-owned with different tags, so the rule addition failed with 403.

---

**Q: Why does the Ingress use `pathType: Prefix` instead of `Exact` or `ImplementationSpecific`?**

`Exact` only matches the exact path. `ImplementationSpecific` in AWS ALB maps to a literal path pattern match — so `/` only matches requests to `/`, not `/health` or `/orders`. `Prefix` with `/` matches all paths that begin with `/`, which is all HTTP paths. We need a catch-all rule so any path on the ALB is routed to the backend.

---

**Q: What is a Horizontal Pod Autoscaler and how does it work?**

HPA periodically queries the Metrics Server for CPU (and optionally memory or custom metrics) usage across all pods in a deployment. It computes the desired replica count as:

```
desiredReplicas = ceil(currentReplicas × (currentMetric / targetMetric))
```

We set `targetCPUUtilizationPercentage: 60` with min 2 and max 5 replicas. When average CPU exceeds 60%, HPA scales up. A scale-down happens more conservatively (5-minute stabilization window by default) to avoid flapping.

---

## CI/CD

**Q: Why did you use GitHub Actions OIDC instead of storing AWS credentials as secrets?**

Static credentials (access key + secret) stored as GitHub secrets are a long-lived security risk — they don't expire, and if they leak (log output, third-party action), they're valid until manually rotated. OIDC is a federated identity approach:
1. GitHub issues a signed JWT token for each workflow run
2. AWS STS verifies the token against the GitHub OIDC provider
3. STS issues temporary credentials (15-minute default session)

No credentials are stored anywhere. The trust is scoped to a specific repository and branch via the IAM trust policy condition.

---

**Q: What does the Trivy step do and why is it in the pipeline?**

Trivy scans the built Docker image for known CVEs (Common Vulnerabilities and Exposures) from public databases (NVD, Alpine secdb, etc.). We configured it with `exit-code: 1` and `severity: CRITICAL`, so the pipeline fails if any critical vulnerabilities are found. This acts as a security gate — a vulnerable image cannot be deployed to production.

During this project, Trivy caught `CVE-2025-15467` in `libssl3`/`libcrypto3` 3.3.3-r0 in the `node:18-alpine` base image. The fix was `RUN apk upgrade --no-cache libssl3 libcrypto3` in the Dockerfile.

---

**Q: Why does the pipeline copy the PostgreSQL secret on every deploy?**

Kubernetes secrets are namespace-scoped. PostgreSQL is deployed to the `database` namespace, but the app pods run in `default`. The app needs `PGPASSWORD` at startup. Rather than duplicating secrets manually or using a secrets operator, the CI step extracts the secret, strips namespace-specific metadata, and applies it to the `default` namespace on every deploy. This keeps it in sync even if the PostgreSQL password rotates.

In production, this would be replaced with AWS Secrets Manager + External Secrets Operator.

---

**Q: What is the smoke test doing and why is it the last step?**

The smoke test is a lightweight end-to-end validation. It gets the ALB hostname from the Ingress object and sends an HTTP request to `/health`, expecting a 200. It retries 10 times with 15-second intervals to allow the ALB target group time to register healthy targets after a new deployment.

It acts as a deployment gate — if the app is not reachable through the full network path (GitHub Actions → internet → ALB → NodePort → pod), the pipeline fails and alerts the team. It catches infrastructure misconfigurations that Helm's `--wait` cannot detect (Helm only checks pod readiness, not external reachability).

---

## Infrastructure & Terraform

**Q: Why do you use remote Terraform state?**

Local state works on a single machine but breaks team workflows — two engineers running `terraform apply` simultaneously can corrupt state. Remote state in S3 + DynamoDB provides:
- **Shared state** — all team members work from the same source of truth
- **Locking** — DynamoDB prevents concurrent applies
- **Versioning** — S3 versioning enables state recovery if corruption occurs

The S3 bucket and DynamoDB table are bootstrapped with `bootstrap-state.sh` before Terraform can run.

---

**Q: Why did you split Terraform into modules?**

Modules enforce separation of concerns and reusability. Each module (`vpc`, `eks`, `ecr`, `alb`, `cluster-autoscaler`) owns its resources and exposes only what callers need through outputs. This means:
- The VPC module doesn't know about EKS — it just outputs subnet IDs
- The EKS module doesn't know about the ALB — it outputs the OIDC provider URL
- Each module can be tested and updated independently
- The `dev` environment composes them as needed; a `prod` environment could use the same modules with different variables

---

**Q: What are EKS Access Entries and why did you use them?**

EKS Access Entries (introduced in EKS API v2023) are the modern replacement for the `aws-auth` ConfigMap for granting IAM principals access to a Kubernetes cluster. We used them to grant the GitHub Actions IAM role `AmazonEKSClusterAdminPolicy` so `kubectl` commands in the CI pipeline could authenticate. Previously, you had to edit the `aws-auth` ConfigMap manually — Access Entries are managed declaratively via Terraform.

---

**Q: Why use a multi-stage Docker build?**

A multi-stage build separates the build environment from the runtime environment:
- **Stage 1 (builder)** — installs all dev dependencies (`npm install`), runs the build if needed
- **Stage 2 (runner)** — copies only the production artifacts (`node_modules` from `npm install --omit=dev`), no build tools

This keeps the final image small and reduces the attack surface — the runner image doesn't contain compilers, build tools, or dev dependencies that could be exploited.

---

**Q: Why does the Dockerfile run the app as a non-root user?**

By default, Docker containers run as root (UID 0). If an attacker exploits the application, they get root inside the container. We create a dedicated `app` user and group:
```dockerfile
RUN addgroup -S app && adduser -S app -G app
USER app
```
This follows the principle of least privilege. Combined with read-only filesystems and dropped capabilities, it significantly limits what an attacker can do if they gain container access.

---

## Troubleshooting

**Q: How did you debug the 503 error in the smoke test?**

The debugging process was:
1. Confirmed pods were `1/1 Running` — ruled out application crash
2. Port-forwarded directly to the service — got 200, confirmed the app was healthy
3. Checked ALB target group health — targets had empty health result (no healthy targets registered)
4. Checked ALB controller logs — found repeated `ec2:AuthorizeSecurityGroupIngress 403` errors against the node security group
5. Traced to the IAM policy — `AuthorizeSecurityGroupIngress` had a `Condition` requiring the `elbv2.k8s.aws/cluster` tag, which the EKS node SG doesn't have
6. Fixed by removing the tag condition from the Authorize/Revoke actions in `iam-policy.json`, ran `terraform apply`, restarted the controller

---

**Q: You went through 404 → 504 → 503 on the smoke test. What did each mean?**

- **404** — The ALB had no matching listener rule. First because of host-header mismatch (`eks-app.example.com` vs ALB DNS), then because `pathType: ImplementationSpecific` only matched exact `/` not `/health`
- **504** — The ALB found a matching rule and forwarded the request to the target group, but the connection to the target timed out. This happened because `target-type: ip` couldn't reach pod IPs — the node security group blocked the ALB
- **503** — The ALB target group had no healthy targets. With `target-type: instance`, the ALB controller tried to add a security group rule to allow traffic to the NodePort range but kept getting 403 because the IAM policy had a tag condition that didn't match the node SG

Each status code pointed to a different layer of the stack.

---

**Q: How does Prometheus scrape metrics from your application?**

The app exposes a `/metrics` endpoint using the `prom-client` library, which serves metrics in Prometheus text format. The `kube-prometheus-stack` Helm chart deploys Prometheus with a `ServiceMonitor` custom resource that tells Prometheus which services to scrape and at what interval. Prometheus polls `/metrics` periodically, stores the time-series data, and Grafana queries it via PromQL.

---

**Q: What would you change in production?**

- Replace copied PostgreSQL secrets with **AWS Secrets Manager + External Secrets Operator**
- Add **TLS termination** at the ALB with an ACM certificate
- Use a **real domain** with Route 53 instead of the raw ALB DNS hostname
- Enable **AWS WAF** on the ALB
- Set up **PodSecurityAdmission** to enforce non-root containers cluster-wide
- Move to **multi-AZ NAT gateways** for HA (currently single NAT to save cost)
- Add **Velero** for Kubernetes resource backup
- Enable **EKS control plane logging** to CloudWatch
- Use **separate AWS accounts** for dev and prod (AWS Organizations)
