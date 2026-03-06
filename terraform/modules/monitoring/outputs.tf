output "grafana_namespace" {
  description = "Namespace where Grafana is deployed"
  value       = var.namespace
}

output "grafana_service_name" {
  description = "Kubernetes Service name for Grafana (use kubectl get svc to find the LoadBalancer hostname)"
  value       = "kube-prometheus-stack-grafana"
}
