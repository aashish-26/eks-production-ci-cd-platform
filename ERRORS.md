# Errors & Issues Encountered

A complete record of every error hit during this project, its root cause, and the fix applied.

---

## 1. `CreateContainerConfigError` — App Pods Failing to Start

**Symptom**
```
kubectl get pods
NAME                          READY   STATUS                       RESTARTS
eks-app-eks-app-xxx           0/1     CreateContainerConfigError   0
```

**Root cause (two separate issues)**

1. The `postgresql` Secret existed in the `database` namespace but the app pod was in `default` — Kubernetes secrets are namespace-scoped and cannot be referenced cross-namespace.
2. `values.yaml` referenced `passwordKey: postgresql-password` but the Bitnami PostgreSQL chart creates the key as `postgres-password`.

**Fix**

Copy the secret from `database` to `default` namespace on every deploy (added as a CI step):
```bash
kubectl get secret postgresql -n database -o json \
  | jq 'del(.metadata.resourceVersion,.metadata.uid,
            .metadata.creationTimestamp,.metadata.annotations,
            .metadata.ownerReferences)
        | .metadata.namespace = "default"' \
  | kubectl apply -f -
```

Corrected `helm/app-chart/values.yaml`:
```yaml
passwordKey: postgres-password   # was: postgresql-password
```

---

## 2. Helm Upgrade — `context deadline exceeded`

**Symptom**
```
Error: UPGRADE FAILED: context deadline exceeded
```

**Root cause**
`helm upgrade --install` with `--wait --timeout 5m` silently waited for pods that could not start (due to error #1 above).

**Fix**
Resolved by fixing the underlying `CreateContainerConfigError`. The `--wait` flag is correct to keep — it caused the deadline to surface only because of the secret issue.

---

## 3. GitHub Actions OIDC — `Not authorized to perform sts:AssumeRoleWithWebIdentity`

**Symptom**
```
Error: Not authorized to perform sts:AssumeRoleWithWebIdentity
```

**Root cause**
`terraform.tfvars` had the placeholder value:
```hcl
github_repo = "YOUR_GITHUB_USERNAME/YOUR_REPO_NAME"
```
The IAM trust policy was deployed with the literal placeholder, so no real GitHub repository could match the condition.

**Fix**
Updated `terraform.tfvars` with the actual repository:
```hcl
github_repo = "aashish-26/eks-production-ci-cd-platform"
```
Then ran `terraform apply` to push the corrected trust policy.

---

## 4. ALB Controller — `ec2:CreateSecurityGroup` AccessDenied (403)

**Symptom**
```
kubectl describe svc kube-prometheus-stack-grafana -n monitoring
FailedBuildModel: AccessDenied ec2:CreateSecurityGroup
```

**Root cause**
The original `iam-policy.json` for the ALB controller was an incomplete subset of the required permissions — missing `ec2:CreateSecurityGroup`, `ec2:AuthorizeSecurityGroupIngress`, `ec2:CreateTags`, and several ELB actions.

**Fix**
Replaced `terraform/modules/alb/iam-policy.json` with the full official AWS Load Balancer Controller IAM policy, then ran `terraform apply`.

---

## 5. ALB Controller — `DescribeListenerAttributes` AccessDenied

**Symptom**
```
AccessDenied: elasticloadbalancing:DescribeListenerAttributes
```

**Root cause**
The updated policy was still missing `elasticloadbalancing:DescribeListenerAttributes`, a permission added in ALB controller v3.x.

**Fix**
Added to the Describe statement in `iam-policy.json`:
```json
"elasticloadbalancing:DescribeListenerAttributes"
```
Ran `terraform apply`, then restarted the ALB controller to force fresh STS credentials:
```bash
kubectl rollout restart deployment aws-load-balancer-controller -n kube-system
```

---

## 6. Grafana Service — `EXTERNAL-IP <pending>` Forever

**Symptom**
```
kubectl get svc kube-prometheus-stack-grafana -n monitoring
NAME                           TYPE           EXTERNAL-IP   ...
kube-prometheus-stack-grafana  LoadBalancer   <pending>
```

**Root cause**
Default NLB scheme is `internal` — not reachable from the internet.

**Fix**
Annotated the service to force internet-facing:
```bash
kubectl annotate svc kube-prometheus-stack-grafana -n monitoring \
  service.beta.kubernetes.io/aws-load-balancer-scheme=internet-facing \
  service.beta.kubernetes.io/aws-load-balancer-type=external \
  --overwrite
```

Immediate workaround while waiting for NLB:
```bash
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring
```

---

## 7. Trivy Scan — CRITICAL CVE Blocking CI Pipeline

**Symptom**
```
CVE-2025-15467  CRITICAL  libssl3   3.3.3-r0  fixed: 3.3.6-r0
CVE-2025-15467  CRITICAL  libcrypto3 3.3.3-r0  fixed: 3.3.6-r0
```

**Root cause**
`node:18-alpine` base image shipped with `libssl3`/`libcrypto3` 3.3.3-r0, which contains a critical RCE vulnerability.

**Fix**
Added targeted upgrade in Stage 2 of `app/Dockerfile`:
```dockerfile
RUN apk upgrade --no-cache libssl3 libcrypto3
```

---

## 8. kubectl in CI — `the server has asked for the client to provide credentials`

**Symptom**
```
error: You must be logged in to the server
(the server has asked for the client to provide credentials)
```

**Root cause**
The GitHub Actions IAM role (`github-actions-eks-deploy`) had `eks:DescribeCluster` permission to generate a token, but was never added to the EKS cluster's access configuration. The API server rejected the token.

**Fix**
Added an EKS access entry in `terraform/modules/eks/main.tf`:
```hcl
access_entries = {
  github_actions = {
    principal_arn = aws_iam_role.github_actions.arn
    policy_associations = {
      cluster_admin = {
        policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
        access_scope = { type = "cluster" }
      }
    }
  }
}
```

---

## 9. Smoke Test — `404` (ALB Host-Header Mismatch)

**Symptom**
```
Attempt 1: got 404 - retrying in 15s...
```

**Root cause**
`values.yaml` had `host: eks-app.example.com`. The ALB listener rule only matched requests with that exact Host header. The smoke test hit the raw ALB DNS hostname, which didn't match — so the ALB returned its default 404 response.

**Fix**
Cleared the host to empty string in `helm/app-chart/values.yaml`:
```yaml
hosts:
- host: ""   # empty = match all hostnames
```
Updated the ingress template to conditionally omit the `host:` field when empty.

---

## 10. Smoke Test — `404` (ALB Path Not Matching)

**Symptom**
```
Attempt 1: got 404 - retrying in 15s...
```
(After fixing issue #9 — host was now `*` but still 404.)

**Root cause**
`pathType: ImplementationSpecific` with path `/` creates a literal exact-match rule in the ALB. A request to `/health` does not match `/` exactly, so the ALB default action returned 404.

**Fix**
Changed to `Prefix` path type in `values.yaml`:
```yaml
pathType: Prefix   # was: ImplementationSpecific
```
`Prefix` with `/` matches all paths including `/health`, `/ready`, `/metrics`.

---

## 11. Smoke Test — `504` (ALB Cannot Reach Pod IP)

**Symptom**
```
Attempt 1: got 504 - retrying in 15s...
```

**Root cause**
`target-type: ip` routes ALB traffic directly to pod IPs on port 8080. The EKS node security group had no inbound rule allowing the ALB security group to reach pods on that port.

**Fix**
Switched to `target-type: instance` and changed the service type to `NodePort`:
```yaml
# values.yaml
service:
  type: NodePort
alb.ingress.kubernetes.io/target-type: instance
```
With instance target type, traffic goes ALB → nodeIP:NodePort → kube-proxy → pod, using the node's existing network path. Also added healthcheck-path annotation:
```yaml
alb.ingress.kubernetes.io/healthcheck-path: /health
```

---

## 12. Smoke Test — `503` (ALB Controller Cannot Add Security Group Rule)

**Symptom**
```
Attempt 1: got 503 - retrying in 15s...
...
Attempt 10: got 503 - retrying in 15s...
Smoke test FAILED
```

ALB controller logs:
```
UnauthorizedOperation: not authorized to perform: ec2:AuthorizeSecurityGroupIngress
on resource: sg-03c282081d06be555
because no identity-based policy allows the ec2:AuthorizeSecurityGroupIngress action
```

**Root cause**
The IAM policy for the ALB controller allowed `ec2:AuthorizeSecurityGroupIngress` only on security groups tagged `elbv2.k8s.aws/cluster`. The node security group (`sg-03c282081d06be555`) is owned by EKS, not the ALB controller, so it does not carry that tag. Every attempt to add the backend SG rule was denied.

The ALB controller needs to add an inbound rule to the node SG allowing its own security group (`sg-0b37c618da6ce411a`) to reach nodes on the NodePort range.

**Fix**
Split the statement in `terraform/modules/alb/iam-policy.json` — removed the tag condition from `AuthorizeSecurityGroupIngress` and `RevokeSecurityGroupIngress`, kept it only on `DeleteSecurityGroup`:

```json
{
  "Effect": "Allow",
  "Action": [
    "ec2:AuthorizeSecurityGroupIngress",
    "ec2:RevokeSecurityGroupIngress"
  ],
  "Resource": "*"
},
{
  "Effect": "Allow",
  "Action": ["ec2:DeleteSecurityGroup"],
  "Resource": "*",
  "Condition": {
    "Null": { "aws:ResourceTag/elbv2.k8s.aws/cluster": "false" }
  }
}
```

Then applied and restarted the controller:
```bash
terraform apply -auto-approve
kubectl rollout restart deployment aws-load-balancer-controller -n kube-system
```

---

## 13. Trivy Scan — Binary Installation Failure

**Symptom**
```
aquasecurity/trivy info checking GitHub for tag 'v0.60.0'
aquasecurity/trivy info found version: 0.60.0 for v0.60.0/Linux/64bit
Error: Process completed with exit code 1.
```

**Root cause**
`aquasecurity/trivy-action@0.30.0` uses `setup-trivy@v0.2.2` internally, which attempted to download Trivy v0.60.0 from GitHub releases but failed (likely due to rate limiting, network issues, or the release being incomplete/problematic).

**Fix**
Updated `.github/workflows/ci-cd.yml` to use the `master` branch (more stable) and pin to a known working Trivy version:
```yaml
- name: Scan image with Trivy
  uses: aquasecurity/trivy-action@master
  with:
    trivy-version: '0.58.1'
    # ... rest of config
```

---

## Summary Table

| # | Error | Status Code / Message | Root Cause | Fix |
|---|---|---|---|---|
| 1 | Pod start failure | `CreateContainerConfigError` | Secret in wrong namespace + wrong key name | Copy secret in CI; fix `passwordKey` |
| 2 | Helm timeout | `context deadline exceeded` | Pods couldn't start (cascades from #1) | Fix #1 |
| 3 | OIDC auth | `Not authorized AssumeRoleWithWebIdentity` | Placeholder `github_repo` in tfvars | Update tfvars, terraform apply |
| 4 | ALB controller | `ec2:CreateSecurityGroup 403` | Incomplete IAM policy | Replace with full official policy |
| 5 | ALB controller | `DescribeListenerAttributes 403` | Missing permission in policy | Add action, terraform apply |
| 6 | Grafana LB | `EXTERNAL-IP <pending>` | Default NLB scheme is internal | Add internet-facing annotation |
| 7 | Trivy scan | `CRITICAL CVE-2025-15467` | Outdated libssl3 in base image | `apk upgrade libssl3 libcrypto3` in Dockerfile |
| 8 | kubectl in CI | `server asked for credentials` | GitHub Actions role not in EKS access config | Add EKS access entry in Terraform |
| 9 | Smoke test | `404` | ALB host-header rule required exact domain match | Clear `host:` to empty (catch-all) |
| 10 | Smoke test | `404` | `ImplementationSpecific` path only matches exact `/` | Change to `pathType: Prefix` |
| 11 | Smoke test | `504` | ALB couldn't reach pod IPs — node SG blocked port 8080 | Switch to `target-type: instance` + `NodePort` service |
| 12 | Smoke test | `503` | ALB controller denied `AuthorizeSecurityGroupIngress` on node SG (tag condition too restrictive) | Remove tag condition from Authorize/Revoke SG rules |
| 13 | Trivy scan | `Process completed with exit code 1` | Trivy v0.60.0 binary download failed from GitHub releases | Pin trivy-action to `@master` with explicit `trivy-version: '0.58.1'` |
