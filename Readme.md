# Production-Grade EKS CI/CD Platform

## Objective

Design and implement a production-ready Kubernetes platform on AWS EKS
with automated CI/CD, autoscaling, and observability.

---

## Tech Stack

- AWS EKS
- Terraform (Infrastructure as Code)
- GitHub Actions (CI/CD)
- Amazon ECR (Container Registry)
- Helm (Kubernetes package manager)
- Prometheus & Grafana (Monitoring)
- PostgreSQL

---

## Architecture Overview

Developer → GitHub → CI Pipeline → Docker Build → ECR → EKS → ALB → Users

---

## Phases

### Phase 1 – Application
- REST API service
- Health & readiness probes
- PostgreSQL integration
- Prometheus metrics endpoint

### Phase 2 – Containerization
- Multi-stage Docker build
- Non-root user
- Optimized image size

### Phase 3 – Infrastructure
- VPC (Multi-AZ)
- EKS cluster
- Managed node groups
- IAM OIDC provider
- Remote Terraform state

### Phase 4 – Kubernetes Deployment
- Helm chart
- Rolling updates
- Resource limits
- Ingress with ALB
- Secrets management

### Phase 5 – CI/CD
- Lint & unit tests
- Docker build & scan
- Push to ECR
- Automated deployment to EKS

### Phase 6 – Scaling & Reliability
- Horizontal Pod Autoscaler
- Cluster Autoscaler
- PodDisruptionBudget
- Failure simulation

### Phase 7 – Monitoring
- Prometheus installation
- Grafana dashboards
- Basic alerting

---

## Key Outcomes

- Zero-downtime rolling deployments
- Auto-scaling under load
- Secure CI/CD with OIDC
- Production-ready infrastructure design
- Full observability setup

---

## Skills Demonstrated

- Kubernetes architecture
- EKS networking
- CI/CD automation
- Infrastructure as Code
- Observability & monitoring
- Deployment strategies
- Cloud security best practices