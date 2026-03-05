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
    kubernetes = { source = "hashicorp/kubernetes" }
    helm       = { source = "hashicorp/helm" }
  }
}

# Dedicated namespace keeps monitoring workloads isolated from app workloads
resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name
  version    = "~> 61.0"   # pin major to avoid breaking CRD changes

  # All chart values — including the sensitive admin password — are expressed
  # as a single HCL object. Because var.grafana_admin_password is declared
  # sensitive = true in variables.tf, Terraform automatically redacts the
  # entire yamlencode() result in plan/apply output, so no set_sensitive block
  # is needed and the value is never printed to the terminal.
  values = [
    yamlencode({
      grafana = {
        # Do NOT hardcode; pass via -var or terraform.tfvars (gitignored).
        # Sensitive propagation: this whole values string is redacted in plan output.
        adminPassword = var.grafana_admin_password

        # LoadBalancer for dev convenience; use Ingress with TLS in production.
        service = {
          type = "LoadBalancer"
        }
        # Keep dashboards and data PVC across Helm upgrades.
        persistence = {
          enabled = true
          size    = "1Gi"
        }
      }

      prometheus = {
        prometheusSpec = {
          # How often to scrape targets — balance between granularity and storage cost
          scrapeInterval = "30s"
          # Retain 15 days of metrics in the default PVC
          retention = "15d"
          # Scrape any ServiceMonitor in any namespace (not just kube-prometheus-stack)
          serviceMonitorSelectorNilUsesHelmValues = false
        }
      }

      alertmanager = {
        enabled = true
      }

      # Node exporter scrapes CPU/memory/disk from every node
      nodeExporter = {
        enabled = true
      }

      # Kube-state-metrics produces k8s object-level metrics
      # (replica counts, pod phase, deployment rollout status, etc.)
      kubeStateMetrics = {
        enabled = true
      }
    })
  ]

  depends_on = [kubernetes_namespace_v1.monitoring]
}
