locals {
  services = ["vote", "result", "worker"]
}

# One repository per service, shared by dev and prod: the image is built ONCE and the same image is promoted.
# Tags are immutable, so a tag (the git commit) always means the same image.
resource "aws_ecr_repository" "service" {
  for_each = toset(local.services)

  name                 = "${var.name_prefix}-${each.key}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "service" {
  for_each = aws_ecr_repository.service

  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "keep the last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
