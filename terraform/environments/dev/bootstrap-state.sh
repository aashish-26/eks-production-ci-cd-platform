#!/usr/bin/env bash
# ============================================================
# Bootstrap Remote State
#
# Run this ONCE before your first `terraform init` to create:
#   1. An S3 bucket for storing the .tfstate file
#   2. A DynamoDB table for state locking
#
# Usage:
#   bash bootstrap-state.sh [REGION] [BUCKET_NAME] [TABLE_NAME]
#
# Defaults match the values in backend.tf.
# ============================================================
set -euo pipefail

# Use `aws` from PATH — works on Linux, macOS, Windows (WSL/Git Bash)
AWS=${AWS_CLI:-aws}

AWS_REGION=${1:-ap-south-1}
STATE_BUCKET=${2:-terraform-backend-proj1}
LOCK_TABLE=${3:-terraform-backend-proj1-locks}

echo "Region      : $AWS_REGION"
echo "State bucket: $STATE_BUCKET"
echo "Lock table  : $LOCK_TABLE"
echo ""

echo "Creating S3 bucket for Terraform state..."
if [ "$AWS_REGION" = "us-east-1" ]; then
  # us-east-1 does not accept a LocationConstraint
  $AWS s3api create-bucket \
    --bucket "$STATE_BUCKET" \
    --region "$AWS_REGION" 2>/dev/null || echo "  (bucket already exists)"
else
  $AWS s3api create-bucket \
    --bucket "$STATE_BUCKET" \
    --region "$AWS_REGION" \
    --create-bucket-configuration LocationConstraint="$AWS_REGION" 2>/dev/null || echo "  (bucket already exists)"
fi

echo "Enabling versioning on the bucket..."
$AWS s3api put-bucket-versioning \
  --bucket "$STATE_BUCKET" \
  --versioning-configuration Status=Enabled

echo "Enabling S3 server-side encryption..."
$AWS s3api put-bucket-encryption \
  --bucket "$STATE_BUCKET" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}
    }]
  }'

echo "Blocking public access on the bucket..."
$AWS s3api put-public-access-block \
  --bucket "$STATE_BUCKET" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

echo ""
echo "Creating DynamoDB lock table (if not already present)..."
$AWS dynamodb describe-table \
  --table-name "$LOCK_TABLE" \
  --region "$AWS_REGION" >/dev/null 2>&1 && echo "  (table already exists)" || \
$AWS dynamodb create-table \
  --table-name "$LOCK_TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$AWS_REGION"

echo ""
echo "Bootstrap complete. You can now run: terraform init"
