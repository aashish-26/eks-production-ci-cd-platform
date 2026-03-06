# ============================================================
# Monitoring Module
#
# Installs the kube-prometheus-stack Helm chart, which bundles:
#
#   - Prometheus Operator   manages Prometheus instances via CRDs
#   - Prometheus            scrapes metrics from pods and nodes
#   - Alertmanager          routes alerts (email, Slack, PagerDuty)
#   - Grafana               visualisation dashboards
#   - Node Exporter         node-level CPU / memory / disk metrics
#   - Kube-State-Metrics    Kubernetes object state metrics
#
# The app exposes /metrics which Prometheus scrapes automatically
# if a ServiceMonitor CRD is created (add in a future iteration).
# ============================================================

terraform {
  required_providers {
    helm = { source = "hashicorp/helm" }
  }
}

# Namespace is created by the helm_release below via create_namespace = true.
# We do NOT manage it as a separate kubernetes_namespace_v1 resource because
# Terraform's resource fails with "already exists" on re-apply if a previous
# apply partially completed. Helm's create_namespace is idempotent — it creates
# the namespace if absent and silently skips creation if it already exists.

resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = var.namespace
  create_namespace = true   # idempotent; safe to re-run if namespace exists
  version          = "61.0.0"

  # kube-prometheus-stack deploys ~8 workloads (Prometheus Operator, Prometheus,
  # Alertmanager, Grafana, Node Exporter DaemonSet, kube-state-metrics + CRDs).
  # Default Helm timeout is 5 min which is not enough. 15 min is safe.
  timeout = 900   # 15 minutes

  # atomic = true rolls back automatically on failure, but that causes Terraform
  # to report error + delete the release, making re-apply unpredictable.
  # atomic = false leaves the release in place so you can inspect with `helm status`.
  atomic          = false
  cleanup_on_fail = false

  # After initial deployment, never let Terraform upgrade this release.
  # kube-prometheus-stack is a large chart (~8 workloads + CRDs) — Helm upgrades
  # consistently exceed any reasonable timeout. Manage upgrades manually:
  #   helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  #     -n monitoring --reuse-values
  lifecycle {
    ignore_changes = all
  }

  # All chart values — including the sensitive admin password — are expressed
  # as a single HCL object. Because var.grafana_admin_password is declared
  # sensitive = true in variables.tf, Terraform automatically redacts the
  # entire yamlencode() result in plan/apply output, so no set_sensitive block
  # is needed and the value is never printed to the terminal.
  values = [
    yamlencode({
      grafana = {
        adminPassword = var.grafana_admin_password
        service = {
          type = "LoadBalancer"
        }
        # Persistence keeps dashboards across pod restarts.
        # PVC is already bound to gp3 StorageClass.
        persistence = {
          enabled = true
          size    = "1Gi"
        }
      }

      prometheus = {
        prometheusSpec = {
          scrapeInterval = "30s"
          # No PVC — ephemeral storage only. Data lost on pod restart; fine for dev.
          storageSpec                             = {}
          serviceMonitorSelectorNilUsesHelmValues = false
        }
      }

      alertmanager = {
        alertmanagerSpec = {
          storage = {}   # ephemeral storage
        }
      }

      # -------------------------------------------------------
      # Disable scrapers that target the EKS managed control
      # plane. AWS does not expose these endpoints so the
      # ServiceMonitors fail → chart never becomes Ready → timeout.
      # -------------------------------------------------------
      kubeControllerManager = {
        enabled = false
      }
      kubeScheduler = {
        enabled = false
      }
      kubeEtcd = {
        enabled = false
      }
      kubeProxy = {
        enabled = false
      }

      nodeExporter = {
        enabled = true
      }

      kubeStateMetrics = {
        enabled = true
      }
    })
  ]
}
