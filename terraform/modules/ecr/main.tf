# ============================================================
# ECR Repository Module
#
# Creates a private Amazon ECR repository with:
#   - Image scanning on every push (catches known CVEs on top of Trivy in CI)
#   - A lifecycle policy to cap untagged images at 10 and keep only
#     the last 30 tagged images (prevents storage cost creep)
# ============================================================

resource "aws_ecr_repository" "this" {
  name                 = var.name
  image_tag_mutability = "MUTABLE"   # allows overwriting "latest" tag; switch to IMMUTABLE for strict prod

  # Scan for CVEs against the ECR-managed threat intelligence DB
  # after every docker push. Acts as a second gate in addition to
  # Trivy scanning in the CI pipeline.
  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.tags
}

# ============================================================
# Lifecycle Policy
#
# Prevents the repository from growing unboundedly.
# Rule 1: delete untagged images after 1 day.
# Rule 2: keep only the 30 most recently pushed tagged images.
# ============================================================

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        # Untagged layers accumulate from multi-stage builds; clean up daily.
        rulePriority = 1
        description  = "Remove untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        # Keep the last 30 tagged versions (sha-tagged images from CI).
        rulePriority = 2
        description  = "Keep only the 30 most recent tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["sha-", "latest"]
          countType     = "imageCountMoreThan"
          countNumber   = 30
        }
        action = { type = "expire" }
      }
    ]
  })
}
