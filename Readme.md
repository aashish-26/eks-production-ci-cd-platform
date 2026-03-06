# Production-Grade EKS CI/CD Platform

A production-ready Kubernetes platform on AWS EKS with automated CI/CD, autoscaling, and observability.

---

## Architecture

```
Developer → GitHub Push
              ↓
        GitHub Actions
         ├── Lint & Test
         ├── Docker Build → ECR
         ├── Trivy Scan
         └── Helm Deploy → EKS
                            ↓
                    ALB Ingress (internet-facing)
                            ↓
                      Node:NodePort
                            ↓
                       App Pods (×2)
                            ↓
                    PostgreSQL (database ns)
```

---

## Tech Stack

| Layer | Tool |
|---|---|
| Cloud | AWS (EKS, ECR, ALB, IAM, VPC) |
| Infrastructure | Terraform |
| CI/CD | GitHub Actions |
| Container Runtime | Docker |
| Orchestration | Kubernetes + Helm |
| Database | PostgreSQL (Bitnami Helm chart) |
| Monitoring | Prometheus + Grafana (kube-prometheus-stack) |
| Security Scanning | Trivy |

---

## Repository Structure

```
.
├── app/                        # Node.js application
│   ├── src/
│   │   ├── index.js            # Express routes
│   │   ├── server.js           # HTTP server + graceful shutdown
│   │   ├── logger.js           # Pino logger
│   │   └── metrics.js          # Prometheus metrics
│   ├── Dockerfile              # Multi-stage build
│   └── docker-compose.yml      # Local development
├── helm/app-chart/             # Helm chart
│   ├── templates/
│   └── values.yaml
├── terraform/
│   ├── environments/dev/       # Root module (entry point)
│   └── modules/
│       ├── vpc/
│       ├── eks/
│       ├── ecr/
│       ├── alb/
│       └── cluster-autoscaler/
└── .github/workflows/
    └── ci-cd.yml               # Full pipeline
```

---

## Prerequisites

- AWS CLI configured with admin credentials
- Terraform >= 1.5
- kubectl
- Helm >= 3
- Docker

---

## 1. Bootstrap Terraform State

Creates the S3 bucket and DynamoDB table used for remote Terraform state.

```bash
chmod +x terraform/environments/dev/bootstrap-state.sh
./terraform/environments/dev/bootstrap-state.sh
```

---

## 2. Provision Infrastructure

```bash
cd terraform/environments/dev

# Copy and fill in your values
cp terraform.tfvars.example terraform.tfvars

terraform init
terraform plan
terraform apply
```

Terraform provisions: VPC (3 AZs), EKS cluster, managed node group, ECR repository, ALB controller (IRSA + Helm), Cluster Autoscaler (IRSA + Helm), GitHub Actions OIDC role, and gp3 StorageClass.

Outputs to note:
```bash
terraform output eks_cluster_name       # → EKS_CLUSTER_NAME GitHub secret
terraform output github_actions_role_arn # → AWS_ROLE_TO_ASSUME GitHub secret
terraform output ecr_repo_url           # → used by the pipeline
```

---

## 3. GitHub Secrets

Set the following secrets in **Settings → Secrets → Actions**:

| Secret | Value |
|---|---|
| `AWS_ROLE_TO_ASSUME` | ARN from `terraform output github_actions_role_arn` |
| `EKS_CLUSTER_NAME` | Name from `terraform output eks_cluster_name` |

---

## 4. Deploy PostgreSQL

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami

helm upgrade --install postgresql bitnami/postgresql \
  --namespace database --create-namespace \
  --set auth.username=postgres \
  --set auth.database=ordersdb
```

---

## 5. Deploy Monitoring

```bash
helm repo add prometheus-community \
  https://prometheus-community.github.io/helm-charts

helm upgrade --install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --version 61.0.0
```

Access Grafana locally:
```bash
kubectl port-forward svc/kube-prometheus-stack-grafana \
  3000:80 -n monitoring
# Open http://localhost:3000  (admin / prom-operator)
```

---

## 6. CI/CD Pipeline

Push to `main` triggers the full pipeline automatically:

```
Checkout → Install → Lint → Test → Set Tag → Configure AWS
  → ECR Login → Docker Build & Push → Trivy Scan
  → Update kubeconfig → Copy PostgreSQL Secret → Helm Deploy → Smoke Test
```

To trigger manually:
```bash
git push origin main
```

The pipeline uses GitHub OIDC to assume the IAM role — no long-lived AWS credentials stored as secrets.

---

## 7. Local Development

```bash
cd app
cp .env.example .env     # fill in DB connection values

# Run with Docker Compose (includes PostgreSQL)
docker compose up

# Or run directly
npm install
npm start
```

App endpoints:
- `GET /health` — liveness check, returns `{"status":"ok"}`
- `GET /ready` — readiness check, tests PostgreSQL connection
- `GET /orders` — sample orders response
- `GET /metrics` — Prometheus metrics

---

## 8. Manual Helm Deploy

To deploy outside of CI/CD:

```bash
aws eks update-kubeconfig \
  --name <cluster-name> \
  --region ap-south-1

# Copy PostgreSQL secret to default namespace
kubectl get secret postgresql -n database -o json \
  | jq 'del(.metadata.resourceVersion,.metadata.uid,
            .metadata.creationTimestamp,.metadata.annotations,
            .metadata.ownerReferences)
        | .metadata.namespace = "default"' \
  | kubectl apply -f -

helm upgrade --install eks-app helm/app-chart \
  --namespace default \
  --set image.repository=<ecr-url>/eks-app \
  --set image.tag=<tag> \
  --wait --timeout 5m
```

---

## 9. Verify Deployment

```bash
# Pods and service
kubectl get pods,svc -n default

# Ingress and ALB hostname
kubectl get ingress -n default

# Hit the health endpoint
curl http://$(kubectl get ingress -n default \
  -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')/health

# ALB controller logs (debug)
kubectl logs -n kube-system \
  -l app.kubernetes.io/name=aws-load-balancer-controller --tail=50

# Autoscaler logs
kubectl logs -n kube-system \
  -l app.kubernetes.io/name=cluster-autoscaler --tail=30
```

---

## 10. Tear Down

```bash
# Remove Helm releases first (deletes ALB and target groups from AWS)
helm uninstall eks-app -n default
helm uninstall kube-prometheus-stack -n monitoring
helm uninstall postgresql -n database

# Then destroy infrastructure
cd terraform/environments/dev
terraform destroy
```
