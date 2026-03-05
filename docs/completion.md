# Deployment & Infrastructure Changes — Completion Report

Date: 2026-03-05

Summary
-------
This document records the actions performed and files added/updated in the
workspace to complete the remaining setup steps for the EKS-based app CI/CD
and observability platform. It also lists the next steps and how to run them.

What I added in this commit
---------------------------
- GitHub Actions workflow: `.github/workflows/ci-cd.yml`
  - Builds the Node app image, tags it with the commit SHA prefix, pushes to
    ECR at `848928399250.dkr.ecr.ap-south-1.amazonaws.com/eks-app`, and deploys
    the Helm chart `helm/app-chart` to the `default` namespace.
  - Uses GitHub OIDC to assume an AWS role. Set the following repository
    secrets before running: `AWS_ROLE_TO_ASSUME`, `EKS_CLUSTER_NAME`.

- Terraform ALB placeholder: `terraform/environments/dev/alb.tf`
  - Contains a safe, commented guide and example commands to create the IAM
    role for the AWS Load Balancer Controller and to install the controller
    via Helm. This avoids making destructive changes without your explicit
    apply — I can convert this into a full Terraform module on request.

- Completion document: `docs/completion.md` (this file)

What was already present / validated
------------------------------------
- Terraform region defaults were set to `ap-south-1` for the `dev` environment.
- Duplicate variable/output declarations in the Terraform modules were fixed
  earlier (modules: `ecr`, `eks`, `vpc`), and `vpc` subnet/AZ indexing was
  corrected.
- A user-provisioned remote backend bucket name `terraform-backend-proj1` and
  lock table `terraform-backend-proj1-locks` are configured in
  `terraform/environments/dev/backend.tf`.
- EKS cluster was created via Terraform (user reported nodes are Ready).
- Docker image was built and pushed to ECR at
  `848928399250.dkr.ecr.ap-south-1.amazonaws.com/eks-app`.
- Helm chart `helm/app-chart` was scaffolded and deployed with HPA and PDB.
- Prometheus/Grafana (kube-prometheus-stack) and Bitnami PostgreSQL were
  installed to `monitoring` and `database` namespaces respectively; the app
  was redeployed with DB env vars referencing the DB secret.

Outstanding / Next steps (actions you should run)
-------------------------------------------------
1) Install the AWS Load Balancer Controller (ALB)
   - Option A (recommended quick): use `eksctl` to create the IAM service
     account and use the Helm command shown in `terraform/environments/dev/alb.tf`.
   - Option B: Ask me to convert the placeholder into a Terraform module that
     creates the full role & policy and the service account (IRSA). I can then
     update `terraform/environments/dev` to call it.

2) Wait for Prometheus / Grafana pods to become Ready (first-time init may
   take several minutes). Verify with:
   ```bash
   kubectl get pods -n monitoring
   kubectl get pods -n database
   kubectl get pods -n default -l app.kubernetes.io/name=eks-app
   kubectl logs -n default -l app.kubernetes.io/name=eks-app --tail=200
   ```

3) Configure GitHub repository secrets required by the workflow
   - `AWS_ROLE_TO_ASSUME` - the role ARN that GitHub Actions will assume
     (create via OIDC trust to GitHub or using Terraform/Console)
   - `EKS_CLUSTER_NAME` - name of the cluster to target with `aws eks update-kubeconfig`

4) Run the pipeline
   - Push to `main` or run the workflow manually to build/push image and deploy.

If you want me to continue and fully implement the Terraform-native ALB
installation (IAM role + policy + service account + Helm release), say so and
I will add the module and wire it into `terraform/environments/dev` and then
create the required IAM policy JSON inline (sourced from AWS docs).

Why we made these choices
-------------------------
- GitHub OIDC for CI/CD: avoids long-lived AWS credentials in GitHub Secrets and
  allows short-lived role assumption with least privilege.
- Remote Terraform backend (S3 + DynamoDB): enables collaboration and locks to
  prevent concurrent state mutations.
- Helm for app, monitoring and DB: simplifies lifecycle operations, upgrades
  and rollbacks.
- ALB (AWS Load Balancer Controller): required to provision ALB resources for
  Kubernetes Ingress configured with AWS annotations; we intentionally left the
  ALB install as an explicit step so you can verify IAM policy and trust setup
  before the controller is granted permissions.

Files added
-----------
- .github/workflows/ci-cd.yml
- terraform/environments/dev/alb.tf
- docs/completion.md

Need me to execute anything now?
-------------------------------
I can:
- Convert the ALB placeholder into a full Terraform module and invocation.
- Create the IAM policy JSON and Terraform resources (role, policy, role policy
  attachment and IRSA SA) and wire a Helm release for the controller.
- Update the workflow or add environment-specific variables.

Which of the above should I do next? (I recommend: create the Terraform ALB
module and wire it into the dev environment.)
