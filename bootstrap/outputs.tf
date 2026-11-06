output "role_arn" {
  description = "GitHub repository variable AWS_ROLE_ARN"
  value       = aws_iam_role.github_actions.arn
}

output "state_bucket" {
  description = "GitHub repository variable TF_STATE_BUCKET"
  value       = aws_s3_bucket.state.bucket
}

output "ecr_repositories" {
  value = { for k, v in aws_ecr_repository.service : k => v.repository_url }
}
