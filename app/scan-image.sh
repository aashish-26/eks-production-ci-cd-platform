#!/usr/bin/env sh
# Simple image scan helper using Trivy if available
IMAGE=${1:-eks-app:local}
if ! command -v trivy >/dev/null 2>&1; then
  echo "Trivy not found. Install Trivy to scan images: https://aquasecurity.github.io/trivy/"
  exit 2
fi
echo "Scanning image: $IMAGE"
trivy image --quiet --severity HIGH,CRITICAL $IMAGE
