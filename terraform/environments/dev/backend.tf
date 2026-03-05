# ============================================================
# Remote State Backend
#
# State is stored in S3 with DynamoDB locking. This means:
#   - The .tfstate file never lives on a developer's laptop.
#   - Multiple engineers cannot apply simultaneously (DynamoDB lock).
#   - State is versioned — roll back with s3api list-object-versions.
#
# Run bootstrap-state.sh ONCE before the first terraform init
# to create the S3 bucket and DynamoDB table.
# ============================================================

terraform {
  backend "s3" {
    # Update these values to match what bootstrap-state.sh created.
    bucket         = "terraform-backend-proj1"
    key            = "dev/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-backend-proj1-locks"
    encrypt        = true   # server-side encryption for the state file
  }
}
