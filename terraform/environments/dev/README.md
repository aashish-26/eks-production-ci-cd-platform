# Dev environment — bootstrap and deploy

Prereqs
- AWS CLI configured with credentials that can create S3 buckets and DynamoDB tables.
- `terraform` installed (>= 1.0)

1) Bootstrap remote state (create S3 bucket + DynamoDB lock table)

```bash
cd terraform/environments/dev
chmod +x bootstrap-state.sh
./bootstrap-state.sh ap-south-1 my-terraform-state-bucket my-terraform-locks
```

2) Prepare variables

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars and set `state_bucket` and `lock_table` to the values you used above
```

3) Run Terraform

```bash
chmod +x deploy.sh
./deploy.sh
```

Notes
- The bootstrap script is idempotent — it will not fail if resources already exist.
- For production, use a centralized account for state and follow your org's security policies.
