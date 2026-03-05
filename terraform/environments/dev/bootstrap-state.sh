#!/usr/bin/env bash
set -euo pipefail

AWS=/c/Program\ Files/Amazon/AWSCLIV2/aws.exe

AWS_REGION=${1:-ap-south-1}
STATE_BUCKET=${2:-my-terraform-state-bucket}
LOCK_TABLE=${3:-my-terraform-locks}

echo "Region: $AWS_REGION"
echo "State bucket: $STATE_BUCKET"
echo "DynamoDB lock table: $LOCK_TABLE"

if [ "$AWS_REGION" = "us-east-1" ]; then
  $AWS s3api create-bucket --bucket "$STATE_BUCKET" --region "$AWS_REGION" || true
else
  $AWS s3api create-bucket \
    --bucket "$STATE_BUCKET" \
    --region "$AWS_REGION" \
    --create-bucket-configuration LocationConstraint=$AWS_REGION || true
fi

$AWS s3api put-bucket-versioning \
  --bucket "$STATE_BUCKET" \
  --versioning-configuration Status=Enabled || true

echo "Creating DynamoDB table (if not exists)..."

$AWS dynamodb describe-table \
  --table-name "$LOCK_TABLE" \
  --region "$AWS_REGION" >/dev/null 2>&1 || \
$AWS dynamodb create-table \
  --table-name "$LOCK_TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
  --region "$AWS_REGION"

echo "Bootstrap complete."