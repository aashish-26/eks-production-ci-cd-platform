terraform {
  backend "s3" {
    bucket         = "terraform-backend-proj1"
    key            = "dev/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-backend-proj1-locks"
  }
}
