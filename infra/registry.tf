# Data sources that read the three ECR repositories
# The repositories were created by the bootstrap. Here we only read them.
data "aws_ecr_repository" "service" {
  for_each = toset(["vote", "result", "worker"])

  name = "${var.name_prefix}-${each.key}"
}

