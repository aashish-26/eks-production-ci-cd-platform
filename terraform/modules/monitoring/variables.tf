variable "namespace" {
  description = "Kubernetes namespace for monitoring stack"
  type        = string
  default     = "monitoring"
}

variable "grafana_admin_password" {
  description = "Grafana admin password. Pass via -var='grafana_admin_password=...' or terraform.tfvars (gitignored)."
  type        = string
  sensitive   = true
}
