resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["ab9d0263244dd0326eb67015705a667e79cfe998"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

resource "aws_iam_role" "github_actions" {
  name = "${var.name_prefix}-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        # only workflows of THIS repo can assume the role.
        # two patterns: the old subject format (repo:org/repo) and the new one (repo:org@ID/repo@ID)
        # that GitHub sends for repos with an immutable subject (the default for new repos)
        StringLike = {
          "token.actions.githubusercontent.com:sub" = [
            "repo:${var.github_org}/${var.github_repo}:*",
            "repo:${var.github_org}@*/${var.github_repo}@*:*",
          ]
        }
      }
    }]
  })
}

# Lab permissions: PowerUser covers ECS, ECR, ELB, RDS, ElastiCache, Secrets Manager, CloudWatch and S3.
# PowerUser has no IAM, so IAM is granted separately and ONLY for roles that start with the prefix.
resource "aws_iam_role_policy_attachment" "power_user" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

resource "aws_iam_role_policy" "iam_for_app_roles" {
  name = "manage-app-roles"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "iam:*"
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.name_prefix}-*"
      },
      {
        # the first ElastiCache / ECS / RDS / ELB in an account creates a "service-linked role"
        Effect   = "Allow"
        Action   = "iam:CreateServiceLinkedRole"
        Resource = "*"
        Condition = {
          StringLike = {
            "iam:AWSServiceName" = [
              "elasticache.amazonaws.com",
              "ecs.amazonaws.com",
              "rds.amazonaws.com",
              "elasticloadbalancing.amazonaws.com",
            ]
          }
        }
      },
    ]
  })
}
