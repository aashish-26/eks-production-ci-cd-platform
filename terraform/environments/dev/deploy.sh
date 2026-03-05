#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

if [ ! -f terraform.tfvars ]; then
  echo "No terraform.tfvars found — copying example to terraform.tfvars"
  cp terraform.tfvars.example terraform.tfvars
  echo "Please edit terraform.tfvars (state_bucket, lock_table) and re-run this script."
  exit 1
fi

terraform init -backend-config="bucket=$(grep -E '^state_bucket' terraform.tfvars | awk -F= '{print $2}' | tr -d ' \"')" \
  -backend-config="region=$(grep -E '^aws_region' terraform.tfvars | awk -F= '{print $2}' | tr -d ' \"')" \
  -backend-config="dynamodb_table=$(grep -E '^lock_table' terraform.tfvars | awk -F= '{print $2}' | tr -d ' \"')"

terraform plan -var-file=terraform.tfvars -out=tfplan
terraform apply tfplan
