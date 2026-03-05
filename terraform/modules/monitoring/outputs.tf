output "grafana_namespace" {
  description = "Namespace where Grafana is deployed"
  value       = kubernetes_namespace_v1.monitoring.metadata[0].name
}

output "grafana_service_name" {
  description = "Kubernetes Service name for Grafana (use kubectl get svc to find the LoadBalancer hostname)"
  value       = "kube-prometheus-stack-grafana"
}
