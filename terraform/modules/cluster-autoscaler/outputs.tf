output "role_arn" {
  description = "ARN of the IAM role used by the Cluster Autoscaler service account"
  value       = aws_iam_role.cluster_autoscaler.arn
}
