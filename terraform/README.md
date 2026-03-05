# Terraform infrastructure (Phase 3)

This folder contains Terraform module scaffolding to provision production-grade AWS infrastructure for the project.

Structure
- `modules/vpc` - VPC with public and private subnets across AZs
- `modules/eks` - EKS cluster using the upstream `terraform-aws-modules/eks/aws` module
- `modules/ecr` - ECR repository
- `environments/dev` - example environment using S3 backend + DynamoDB locking

Getting started (dev)
1. Create an S3 bucket and DynamoDB table for Terraform state locking.
2. Copy `environments/dev/terraform.tfvars.example` to `terraform.tfvars` and fill values.
3. Init and apply:

```bash
cd terraform/environments/dev
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

Notes
- This is scaffolding — review IAM least-privilege and region settings before applying to production.
- The EKS module uses the community `terraform-aws-modules/eks/aws` module for simplicity.
