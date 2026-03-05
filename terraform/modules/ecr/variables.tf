variable "name" {
  description = "ECR repo name"
  type        = string
}

variable "tags" {
  description = "Tags for the repository"
  type        = map(string)
  default     = {}
}
