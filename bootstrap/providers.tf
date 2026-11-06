# Run ONCE, by hand, from your own machine (never from CI).
# Creates everything the pipeline needs before it can run:
#   1. an S3 bucket for the Terraform state (CI runners are throw-away, they cannot keep a local state file)
#   2. three ECR repositories, one per service (the pipeline pushes images there, Terraform only reads them)
#   3. a trust relationship between GitHub Actions and AWS (OIDC)
#   4. an IAM role that GitHub Actions assumes, with temporary credentials

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-north-1"

  default_tags {
    tags = {
      Project = "voting-app"
      Owner   = var.name_prefix
    }
  }
}
