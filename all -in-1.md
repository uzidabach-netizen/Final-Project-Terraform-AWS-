Claude








Project overview · MD
Voting App — מבנה הפרויקט וקוד כל הקבצים
קובץ קריאה אחד: איך נקבעות אפשרויות ההצבעה, מבנה התיקיות, ותוכן כל הקבצים בצורה מסודרת.

קבצים שמסומנים ב-✏️ מוצגים כאן בגרסה המעודכנת (מקור אמת יחיד בקבצי הסביבה). העדכון נעשה בעותק מקומי בלבד ועדיין לא נדחף למאגר ב-GitHub.

1. מקור האמת של אפשרויות ההצבעה
text
infra/envs/dev.tfvars , infra/envs/prod.tfvars     option_a / option_b   <-- המקום היחיד שבו מגדירים
          │
          ▼
infra/variables.tf         ללא ברירת מחדל + בדיקה שהערך אינו ריק
          │
          ▼
infra/ecs.tf               local.option_env  -->  מודול vote  +  מודול result
          │
          ▼
task definition            OPTION_A / OPTION_B (משתני סביבה של הקונטיינר)
          ├──► services/vote/app.py                 --> דף ההצבעה
          └──► services/result/server.js (/config)
                    └──► views/app.js --> views/index.html  --> דף התוצאות
כדי לשנות שם של אפשרות בסביבה מסוימת, משנים שורה אחת בקובץ infra/envs/<env>.tfvars בלבד.


3. מבנה הקבצים והתיקיות
text
Final-Project-Terraform-AWS-/
├── .github/
│   └── workflows/
│       ├── deploy-env.yml
│       └── deploy.yml
├── bootstrap/
│   ├── .terraform.lock.hcl
│   ├── data.tf
│   ├── ecr.tf
│   ├── github-oidc.tf
│   ├── outputs.tf
│   ├── providers.tf
│   ├── state.tf
│   └── variables.tf
├── infra/
│   ├── envs/
│   │   ├── dev.tfvars  ✏️
│   │   └── prod.tfvars  ✏️
│   ├── modules/
│   │   └── service/
│   │       ├── main.tf
│   │       ├── outputs.tf
│   │       └── variables.tf
│   ├── .terraform.lock.hcl
│   ├── cache.tf
│   ├── database.tf
│   ├── ecs.tf  ✏️
│   ├── iam.tf
│   ├── locals.tf
│   ├── monitoring.tf
│   ├── network.tf
│   ├── outputs.tf
│   ├── providers.tf
│   ├── registry.tf
│   └── variables.tf  ✏️
├── services/
│   ├── result/
│   │   ├── views/
│   │   │   ├── stylesheets/
│   │   │   │   └── style.css
│   │   │   ├── angular.min.js
│   │   │   ├── app.js  ✏️
│   │   │   ├── index.html  ✏️
│   │   │   └── socket.io.js
│   │   ├── .dockerignore
│   │   ├── Dockerfile
│   │   ├── package-lock.json
│   │   ├── package.json
│   │   └── server.js  ✏️
│   ├── vote/
│   │   ├── static/
│   │   │   └── stylesheets/
│   │   │       └── style.css
│   │   ├── templates/
│   │   │   └── index.html
│   │   ├── .dockerignore
│   │   ├── app.py  ✏️
│   │   ├── Dockerfile
│   │   └── requirements.txt
│   ├── worker/
│   │   ├── .dockerignore
│   │   ├── Dockerfile
│   │   ├── Program.cs
│   │   └── Worker.csproj
│   ├── .gitignore
│   ├── LICENSE
│   └── README.md
├── .gitignore
├── README.md
└── Steps.md
4. תוכן הקבצים
📄 קבצי השורש
.gitignore
text
.terraform/
*.tfstate*
*.zip
__pycache__/
node_modules/
bin/
obj/
.env
*.tfvars
📁 .github/
.github/workflows/deploy-env.yml
yaml
name: deploy-env

# Reusable workflow: deploys one environment, runs the smoke test
# and the version check. Called twice by deploy.yml (dev, then prod).

on:
  workflow_call:
    inputs:
      env:
        description: "dev or prod"
        type: string
        required: true
      image_tag:
        description: "Image tag in ECR (the git commit SHA)"
        type: string
        required: true

permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest

    # Pauses here for approval when the Environment has required reviewers (prod).
    environment: ${{ inputs.env }}

    # P11: one run at a time per environment. Never cancel a running apply.
    concurrency:
      group: terraform-${{ inputs.env }}
      cancel-in-progress: false

    env:
      TF_IN_AUTOMATION: "true"
      # Optional repository variable AWS_REGION. Falls back to eu-north-1.
      AWS_REGION: ${{ vars.AWS_REGION || 'eu-north-1' }}
      TF_VAR_region: ${{ vars.AWS_REGION || 'eu-north-1' }}
      TF_VAR_name_prefix: ${{ vars.NAME_PREFIX }}
      TF_VAR_image_tag: ${{ inputs.image_tag }}

    defaults:
      run:
        working-directory: infra

    steps:
      - uses: actions/checkout@v4

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.AWS_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "~> 1.10"
          terraform_wrapper: false

      - name: init
        run: |
          terraform init -reconfigure -input=false -no-color \
            -backend-config="bucket=${{ vars.TF_STATE_BUCKET }}" \
            -backend-config="key=voting-app/${{ inputs.env }}/terraform.tfstate" \
            -backend-config="region=${{ env.AWS_REGION }}" \
            -backend-config="use_lockfile=true"

      - name: apply
        run: |
          terraform apply -auto-approve -input=false -no-color \
            -var-file=envs/${{ inputs.env }}.tfvars

      # P9: a green apply is not enough (a rolled-back service is "steady" too),
      # but the smoke test still proves the site answers.
      - name: smoke test
        run: |
          vote_url=$(terraform output -raw vote_url)
          result_url=$(terraform output -raw result_url)
          for url in "$vote_url" "$result_url"; do
            echo "Checking $url/healthz"
            curl --fail --silent --show-error \
              --retry 10 --retry-delay 6 --retry-all-errors \
              -o /dev/null -w "HTTP %{http_code}\n" "$url/healthz"
          done

      # P10: if ECS rolled back, Terraform still wants to move the service
      # to the new task definition, so the plan is not empty (exit code 2).
      - name: version check (plan must be empty)
        run: |
          set +e
          terraform plan -detailed-exitcode -input=false -no-color \
            -var-file=envs/${{ inputs.env }}.tfvars
          code=$?
          if [ "$code" -eq 0 ]; then
            echo "OK: the deployed version matches the code."
          elif [ "$code" -eq 2 ]; then
            echo "::error::The plan is not empty after apply. ECS probably rolled back the deployment. Check the stopped tasks of the service."
            exit 1
          else
            exit "$code"
          fi
.github/workflows/deploy.yml
yaml
name: deploy

on:
  pull_request:
    branches: [main]
    paths:
      - "services/**"
      - "infra/**"
      - ".github/workflows/**"
  push:
    branches: [main]
    paths:
      - "services/**"
      - "infra/**"
      - ".github/workflows/**"

# Needed for OIDC (id-token) and for checkout (contents).
# A called workflow cannot get more permissions than its caller.
permissions:
  id-token: write
  contents: read

env:
  # Optional repository variable AWS_REGION. Falls back to eu-north-1.
  AWS_REGION: ${{ vars.AWS_REGION || 'eu-north-1' }}

jobs:
  # ------------------------------------------------------------ P3
  checks:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: infra
    steps:
      - uses: actions/checkout@v4

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "~> 1.10"
          terraform_wrapper: false

      - name: fmt
        run: terraform fmt -check -recursive -no-color

      - name: init (no backend)
        run: terraform init -backend=false -input=false -no-color

      - name: validate
        run: terraform validate -no-color

  # ------------------------------------------------------------ P4
  build:
    needs: checks
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        service: [vote, result, worker]
    steps:
      - uses: actions/checkout@v4

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.AWS_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Login to ECR
        id: ecr
        uses: aws-actions/amazon-ecr-login@v2

      - uses: docker/setup-buildx-action@v3

      # Tags are immutable: if this commit was already pushed, skip the push.
      - name: Does the image already exist?
        id: exists
        run: |
          set +e
          out=$(aws ecr describe-images \
            --repository-name "${{ vars.NAME_PREFIX }}-${{ matrix.service }}" \
            --image-ids imageTag=${{ github.sha }} 2>&1)
          rc=$?
          if [ $rc -eq 0 ]; then
            echo "exists=true" >> "$GITHUB_OUTPUT"
          elif echo "$out" | grep -q ImageNotFoundException; then
            echo "exists=false" >> "$GITHUB_OUTPUT"
          else
            echo "$out"
            exit 1
          fi

      # Always build (a Pull Request checks that the image builds).
      # Push only on main, and only if the tag is new.
      - name: Build (and push on main)
        uses: docker/build-push-action@v6
        with:
          context: services/${{ matrix.service }}
          platforms: linux/amd64
          push: ${{ github.event_name == 'push' && steps.exists.outputs.exists != 'true' }}
          tags: ${{ steps.ecr.outputs.registry }}/${{ vars.NAME_PREFIX }}-${{ matrix.service }}:${{ github.sha }}

  # ------------------------------------------------------------ P5
  plan:
    if: github.event_name == 'pull_request'
    needs: checks
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        env: [dev, prod]
    env:
      TF_VAR_name_prefix: ${{ vars.NAME_PREFIX }}
      TF_VAR_image_tag: ${{ github.sha }}
      TF_VAR_region: ${{ vars.AWS_REGION || 'eu-north-1' }}
    defaults:
      run:
        working-directory: infra
    steps:
      - uses: actions/checkout@v4

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.AWS_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "~> 1.10"
          terraform_wrapper: false

      - name: init
        run: |
          terraform init -reconfigure -input=false -no-color \
            -backend-config="bucket=${{ vars.TF_STATE_BUCKET }}" \
            -backend-config="key=voting-app/${{ matrix.env }}/terraform.tfstate" \
            -backend-config="region=${{ env.AWS_REGION }}" \
            -backend-config="use_lockfile=true"

      # Read-only: -lock=false so that two PRs can plan at the same time.
      - name: plan (never apply on a Pull Request)
        run: |
          terraform plan -input=false -no-color -lock=false \
            -var-file=envs/${{ matrix.env }}.tfvars \
            -out=plan.tfplan

      - name: Show the plan in the job summary
        run: |
          {
            echo "### terraform plan: ${{ matrix.env }}"
            echo '```'
            terraform show -no-color plan.tfplan
            echo '```'
          } >> "$GITHUB_STEP_SUMMARY"

  # ------------------------------------------------------------ P6
  deploy-dev:
    if: github.event_name == 'push'
    needs: build
    uses: ./.github/workflows/deploy-env.yml
    with:
      env: dev
      image_tag: ${{ github.sha }}
    secrets: inherit

  # ------------------------------------------------------------ P7, P8
  # Same image tag as dev (github.sha): nothing is rebuilt.
  # The Environment "prod" (required reviewers) is used inside deploy-env.yml.
  deploy-prod:
    if: github.event_name == 'push'
    needs: deploy-dev
    uses: ./.github/workflows/deploy-env.yml
    with:
      env: prod
      image_tag: ${{ github.sha }}
    secrets: inherit
📁 bootstrap/
bootstrap/data.tf
hcl
data "aws_caller_identity" "current" {}
bootstrap/ecr.tf
hcl
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
bootstrap/github-oidc.tf
hcl
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
bootstrap/outputs.tf
hcl
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
bootstrap/providers.tf
hcl
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
bootstrap/state.tf
hcl
resource "aws_s3_bucket" "state" {
  bucket        = "${var.name_prefix}-tfstate-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
bootstrap/variables.tf
hcl
variable "github_org" {
  description = "GitHub user or organization that owns the repo"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (without the org)"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for every name. Lowercase letters, digits and hyphens, up to 12 characters"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{1,12}$", var.name_prefix))
    error_message = "name_prefix: lowercase letters, digits and hyphens, up to 12 characters."
  }
}

variable "create_oidc_provider" {
  description = "Set to false if the account already has the GitHub OIDC provider (only one is allowed per account)"
  type        = bool
  default     = true
}
📁 infra/
infra/cache.tf
hcl
# ElastiCache: subnet group and cluster
resource "aws_elasticache_subnet_group" "main" {
  name       = "${local.name}-redis-subnets"
  subnet_ids = [for s in aws_subnet.private : s.id]
}

resource "aws_elasticache_cluster" "main" {
  cluster_id           = "${local.name}-redis"
  engine               = "redis"
  engine_version       = "7.1"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.main.name
  security_group_ids   = [aws_security_group.redis.id]
}
infra/database.tf
hcl
# RDS: subnet group and instance, the generated password and its Secrets Manager secret
resource "random_password" "db" {
  length  = 24
  special = false # ';' and '=' would break the .NET connection string
}

resource "aws_secretsmanager_secret" "db_password" {
  name                    = "${local.name}-db-password"
  recovery_window_in_days = 0 # deleted immediately on destroy
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db.result
}

resource "aws_db_subnet_group" "main" {
  name       = "${local.name}-db-subnets"
  subnet_ids = [for s in aws_subnet.private : s.id]
}

resource "aws_db_instance" "main" {
  identifier             = "${local.name}-db"
  engine                 = "postgres"
  engine_version         = "16"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  db_name                = "votes"
  username               = "voteadmin"
  password               = random_password.db.result
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  skip_final_snapshot    = true
}
infra/ecs.tf ✏️
hcl
# ECS cluster, environment variables and secrets of the services, the three calls to the service module
resource "aws_ecs_cluster" "main" {
  name = "${local.name}-cluster"
}

locals {
  redis_host = aws_elasticache_cluster.main.cache_nodes[0].address

  db_env = {
    DB_HOST = aws_db_instance.main.address
    DB_PORT = tostring(aws_db_instance.main.port)
    DB_USER = aws_db_instance.main.username
    DB_NAME = aws_db_instance.main.db_name
    DB_SSL  = "true"
  }

  # The value is the secret ARN; ECS reads it with the execution role.
  db_secrets = {
    DB_PASSWORD = aws_secretsmanager_secret.db_password.arn
  }

  public_subnet_ids = [for s in aws_subnet.public : s.id]

  # The voting options come only from envs/<env>.tfvars. Shared by vote and result.
  option_env = {
    OPTION_A = var.option_a
    OPTION_B = var.option_b
  }
}

module "vote" {
  source = "./modules/service"

  name               = "${local.name}-vote"
  cluster_id         = aws_ecs_cluster.main.id
  image              = "${data.aws_ecr_repository.service["vote"].repository_url}:${var.image_tag}"
  desired_count      = var.desired_count
  subnet_ids         = local.public_subnet_ids
  security_group_ids = [aws_security_group.ecs.id]
  execution_role_arn = aws_iam_role.exec.arn

  environment = merge({ REDIS_HOST = local.redis_host }, local.option_env)

  container_port   = 80
  target_group_arn = aws_lb_target_group.vote.arn

  depends_on = [
    aws_lb_listener.vote,
    aws_iam_role_policy_attachment.exec_managed,
  ]
}

module "result" {
  source = "./modules/service"

  name               = "${local.name}-result"
  cluster_id         = aws_ecs_cluster.main.id
  image              = "${data.aws_ecr_repository.service["result"].repository_url}:${var.image_tag}"
  desired_count      = var.desired_count
  subnet_ids         = local.public_subnet_ids
  security_group_ids = [aws_security_group.ecs.id]
  execution_role_arn = aws_iam_role.exec.arn

  environment = merge(local.db_env, local.option_env)
  secrets     = local.db_secrets

  container_port   = 80
  target_group_arn = aws_lb_target_group.result.arn

  depends_on = [
    aws_lb_listener.result,
    aws_iam_role_policy.exec_read_db_secret,
    aws_iam_role_policy_attachment.exec_managed,
    aws_secretsmanager_secret_version.db_password,
  ]
}

# No port and no target group: the worker is not behind the load balancer.
module "worker" {
  source = "./modules/service"

  name               = "${local.name}-worker"
  cluster_id         = aws_ecs_cluster.main.id
  image              = "${data.aws_ecr_repository.service["worker"].repository_url}:${var.image_tag}"
  desired_count      = var.desired_count
  subnet_ids         = local.public_subnet_ids
  security_group_ids = [aws_security_group.ecs.id]
  execution_role_arn = aws_iam_role.exec.arn

  environment = merge(local.db_env, { REDIS_HOST = local.redis_host })
  secrets     = local.db_secrets

  depends_on = [
    aws_iam_role_policy.exec_read_db_secret,
    aws_iam_role_policy_attachment.exec_managed,
    aws_secretsmanager_secret_version.db_password,
  ]
}
infra/iam.tf
hcl
# Task execution role, policy attachment, permission to read the secret
data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "exec" {
  name               = "${local.name}-exec"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "exec_managed" {
  role       = aws_iam_role.exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Read access to the database password secret, and nothing else.
data "aws_iam_policy_document" "read_db_secret" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.db_password.arn]
  }
}

resource "aws_iam_role_policy" "exec_read_db_secret" {
  name   = "${local.name}-read-db-secret"
  role   = aws_iam_role.exec.id
  policy = data.aws_iam_policy_document.read_db_secret.json
}
infra/locals.tf
hcl
# Locals shared by several files (the <name_prefix>-<env> name)
locals {
  # Used in the name of almost every resource: <name_prefix>-<env>
  name = "${var.name_prefix}-${var.env}"
}
infra/monitoring.tf
hcl
# SNS topic and CloudWatch alarm
resource "aws_sns_topic" "alerts" {
  name = "${local.name}-alerts"
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${local.name}-alb-5xx"
  alarm_description   = "The targets behind the load balancer returned 5xx errors"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}
infra/network.tf
hcl
# VPC, subnets, gateway, route tables, security groups, load balancer, target groups, listeners
data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  public_subnets  = { for i, az in local.azs : az => cidrsubnet(var.vpc_cidr, 8, i) }
  private_subnets = { for i, az in local.azs : az => cidrsubnet(var.vpc_cidr, 8, i + 10) }
}

# ---------------------------------------------------------------- VPC

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name}-igw"
  }
}

resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name}-public-${each.key}"
  }
}

resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value
  availability_zone = each.key

  tags = {
    Name = "${local.name}-private-${each.key}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${local.name}-public-rt"
  }
}

# No route to the internet (no NAT Gateway).
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name}-private-rt"
  }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

# ---------------------------------------------------------------- Security groups

resource "aws_security_group" "alb" {
  name        = "${local.name}-alb-sg"
  description = "Load balancer: 80 and 8080 from the internet"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "vote"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "result"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-alb-sg"
  }
}

resource "aws_security_group" "ecs" {
  name        = "${local.name}-ecs-sg"
  description = "ECS tasks: 80 only from the load balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "from the load balancer"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Needed to pull images, read the secret and send logs (no NAT).
  egress {
    description = "all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-ecs-sg"
  }
}

resource "aws_security_group" "redis" {
  name        = "${local.name}-redis-sg"
  description = "Redis: 6379 only from ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "from ECS tasks"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  tags = {
    Name = "${local.name}-redis-sg"
  }
}

resource "aws_security_group" "rds" {
  name        = "${local.name}-rds-sg"
  description = "Postgres: 5432 only from ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "from ECS tasks"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  tags = {
    Name = "${local.name}-rds-sg"
  }
}

# ---------------------------------------------------------------- Load balancer

resource "aws_lb" "main" {
  name               = "${local.name}-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for s in aws_subnet.public : s.id]

  tags = {
    Name = "${local.name}-alb"
  }
}

resource "aws_lb_target_group" "vote" {
  name                 = "${local.name}-vote"
  port                 = 80
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = aws_vpc.main.id
  deregistration_delay = 30

  health_check {
    path                = "/healthz"
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_target_group" "result" {
  name                 = "${local.name}-result"
  port                 = 80
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = aws_vpc.main.id
  deregistration_delay = 30

  health_check {
    path                = "/healthz"
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  # NEW: socket.io (long polling) needs every request of one browser
  # to reach the same task. Without this, the result page stays blank
  # when there are 2 tasks (prod).
  stickiness {
    type            = "lb_cookie"
    enabled         = true
    cookie_duration = 86400
  }
}

resource "aws_lb_listener" "vote" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.vote.arn
  }
}

resource "aws_lb_listener" "result" {
  load_balancer_arn = aws_lb.main.arn
  port              = 8080
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.result.arn
  }
}
infra/outputs.tf
hcl
# All the outputs
output "vote_url" {
  description = "Address of the vote page."
  value       = "http://${aws_lb.main.dns_name}"
}

output "result_url" {
  description = "Address of the result page."
  value       = "http://${aws_lb.main.dns_name}:8080"
}

output "redis_endpoint" {
  description = "Address of the Redis node."
  value       = aws_elasticache_cluster.main.cache_nodes[0].address
}

output "db_endpoint" {
  description = "Address of the Postgres instance."
  value       = aws_db_instance.main.address
}
infra/providers.tf
hcl
# terraform {} (version, required_providers, empty backend "s3" {}) and provider "aws" with default_tags
terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "voting-app"
      Environment = var.env
      Owner       = var.name_prefix
    }
  }
}

#9הרצה חדשה
infra/registry.tf
hcl
# Data sources that read the three ECR repositories
# The repositories were created by the bootstrap. Here we only read them.
data "aws_ecr_repository" "service" {
  for_each = toset(["vote", "result", "worker"])

  name = "${var.name_prefix}-${each.key}"
}
infra/variables.tf ✏️
hcl
# All the input variables, with validation blocks
variable "name_prefix" {
  description = "Prefix of every resource name (same value as in the bootstrap)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{1,12}$", var.name_prefix))
    error_message = "name_prefix must be 1-12 characters: lowercase letters, digits and hyphens only."
  }
}

variable "region" {
  description = "AWS region to deploy to. Must be the same region as the bootstrap (ECR repositories)."
  type        = string
  default     = "eu-north-1"
}

variable "env" {
  description = "Environment name: dev or prod."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be either \"dev\" or \"prod\"."
  }
}

variable "vpc_cidr" {
  description = "CIDR range of the VPC, for example 10.10.0.0/16."
  type        = string
}

variable "image_tag" {
  description = "Tag of the container images in ECR (the git commit SHA in the pipeline)."
  type        = string
}

variable "desired_count" {
  description = "Number of tasks per service."
  type        = number
  default     = 1
}

variable "option_a" {
  description = "First voting option. Set in envs/<env>.tfvars (no default: the env files are the single source of truth)."
  type        = string

  validation {
    condition     = length(trimspace(var.option_a)) > 0
    error_message = "option_a must not be empty."
  }
}

variable "option_b" {
  description = "Second voting option. Set in envs/<env>.tfvars (no default: the env files are the single source of truth)."
  type        = string

  validation {
    condition     = length(trimspace(var.option_b)) > 0
    error_message = "option_b must not be empty."
  }
}
infra/envs/dev.tfvars ✏️
hcl
# Values for the dev environment
env           = "dev"
vpc_cidr      = "10.10.0.0/16"
desired_count = 1

# Voting options: the single source of truth (no defaults anywhere else)
option_a = "ביבי"
option_b = "אייזנקוט"
infra/envs/prod.tfvars ✏️
hcl
# Values for the prod environment
env           = "prod"
vpc_cidr      = "10.20.0.0/16"
desired_count = 2

# Voting options: the single source of truth (no defaults anywhere else)
option_a = "ביבי"
option_b = "אייזנקוט"
infra/modules/service/main.tf
hcl
# Resources of one service: log group, task definition, ECS service
data "aws_region" "current" {}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.name}"
  retention_in_days = 7
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = var.name
      image     = var.image
      essential = true

      portMappings = var.container_port == null ? [] : [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      environment = [for k, v in var.environment : { name = k, value = v }]
      secrets     = [for k, v in var.secrets : { name = k, valueFrom = v }]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "this" {
  name            = var.name
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  # Keep the old tasks until the new ones are healthy: no downtime.
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  # A bad version is rolled back by ECS. apply waits until the deployment ends
  # (new version up, or rolled back).
  wait_for_steady_state = true

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # Only valid together with a load balancer.
  health_check_grace_period_seconds = var.target_group_arn == null ? null : 60

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = true # no NAT: the task needs a public IP to pull its image
  }

  dynamic "load_balancer" {
    for_each = var.target_group_arn == null ? [] : [1]

    content {
      target_group_arn = var.target_group_arn
      container_name   = var.name
      container_port   = var.container_port
    }
  }
}
infra/modules/service/outputs.tf
hcl
# Outputs of the service module
output "service_name" {
  description = "Name of the ECS service."
  value       = aws_ecs_service.this.name
}

output "task_definition_arn" {
  description = "ARN of the task definition in use."
  value       = aws_ecs_task_definition.this.arn
}

output "log_group_name" {
  description = "CloudWatch log group of the service."
  value       = aws_cloudwatch_log_group.this.name
}
infra/modules/service/variables.tf
hcl
# Inputs of the service module
variable "name" {
  description = "Name of the service. Used for the ECS service, the task family, the container and the log group."
  type        = string
}

variable "cluster_id" {
  description = "ID (ARN) of the ECS cluster."
  type        = string
}

variable "image" {
  description = "Full image reference, for example <repository url>:<tag>."
  type        = string
}

variable "desired_count" {
  description = "Number of tasks."
  type        = number
  default     = 1
}

variable "cpu" {
  description = "Fargate CPU units."
  type        = number
  default     = 256
}

variable "memory" {
  description = "Fargate memory in MB (valid with 256 CPU: 512, 1024, 2048)."
  type        = number
  default     = 512
}

variable "subnet_ids" {
  description = "Subnets of the tasks."
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security groups of the tasks."
  type        = list(string)
}

variable "execution_role_arn" {
  description = "Task execution role."
  type        = string
}

variable "environment" {
  description = "Plain environment variables of the container (never put secrets here)."
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Secrets of the container: variable name => secret ARN."
  type        = map(string)
  default     = {}
}

variable "container_port" {
  description = "Container port. null = no port mapping (for example the worker)."
  type        = number
  default     = null
}

variable "target_group_arn" {
  description = "Target group to register in. null = not behind a load balancer."
  type        = string
  default     = null
}
📁 services/
services/.gitignore
text
__pycache__/
bin/
obj/
node_modules/
services/result/.dockerignore
text
node_modules/
services/result/Dockerfile
dockerfile
FROM node:18-slim

# add curl for healthcheck
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl tini && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /usr/local/app

# have nodemon available for local dev use (file watching)
RUN npm install -g nodemon

COPY package*.json ./

RUN npm ci && \
 npm cache clean --force && \
 mv /usr/local/app/node_modules /node_modules

COPY . .

ENV PORT=80
EXPOSE 80

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["node", "server.js"]
services/result/package.json
json
{
  "name": "result",
  "version": "1.0.0",
  "description": "",
  "main": "server.js",
  "scripts": {
    "test": "echo \"Error: no test specified\" && exit 1"
  },
  "author": "",
  "license": "MIT",
  "dependencies": {
    "async": "^3.1.0",
    "cookie-parser": "^1.4.6",
    "express": "^4.18.2",
    "method-override": "^3.0.0",
    "pg": "^8.8.0",
    "socket.io": "^4.7.2",
    "stoppable": "^1.1.0"
  }
}
services/result/server.js ✏️
javascript
var express = require('express'),
    path = require('path'),
    async = require('async'),
    { Pool } = require('pg'),
    cookieParser = require('cookie-parser'),
    app = express(),
    server = require('http').Server(app),
    io = require('socket.io')(server);

var port = process.env.PORT || 4000;

// The voting options have no default: they come only from the environment
// (envs/<env>.tfvars -> Terraform -> task definition). A missing value fails at startup.
var optionA = process.env.OPTION_A;
var optionB = process.env.OPTION_B;
if (!optionA || !optionB) {
  console.error('OPTION_A and OPTION_B must be set');
  process.exit(1);
}

io.on('connection', function (socket) {

  socket.emit('message', { text : 'Welcome!' });

  socket.on('subscribe', function (data) {
    socket.join(data.channel);
  });
});

// course change: the database settings come from the environment (RDS on AWS)
// DB_SSL=true turns on TLS (RDS Postgres 15+ refuses connections without it)
var pool = new Pool({
  host: process.env.DB_HOST || 'db',
  port: parseInt(process.env.DB_PORT || '5432'),
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD || 'postgres',
  database: process.env.DB_NAME || 'postgres',
  ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false
});

async.retry(
  {times: 1000, interval: 1000},
  function(callback) {
    pool.connect(function(err, client, done) {
      if (err) {
        console.error("Waiting for db: " + err.message);
      }
      callback(err, client);
    });
  },
  function(err, client) {
    if (err) {
      return console.error("Giving up");
    }
    console.log("Connected to db");
    getVotes(client);
  }
);

function getVotes(client) {
  client.query('SELECT vote, COUNT(id) AS count FROM votes GROUP BY vote', [], function(err, result) {
    if (err) {
      console.error("Error performing query: " + err);
    } else {
      var votes = collectVotesFromResult(result);
      io.sockets.emit("scores", JSON.stringify(votes));
    }

    setTimeout(function() {getVotes(client) }, 1000);
  });
}

function collectVotesFromResult(result) {
  var votes = {a: 0, b: 0};

  result.rows.forEach(function (row) {
    votes[row.vote] = parseInt(row.count);
  });

  return votes;
}

app.use(cookieParser());
app.use(express.urlencoded());
app.use(express.static(__dirname + '/views'));

app.get('/healthz', function (req, res) {
  // course change: a health check that does not depend on the database, for the load balancer
  res.status(200).send('ok');
});

app.get('/config', function (req, res) {
  res.json({ optionA: optionA, optionB: optionB });
});

app.get('/', function (req, res) {
  res.sendFile(path.resolve(__dirname + '/views/index.html'));
});

server.listen(port, function () {
  var port = server.address().port;
  console.log('App running on port ' + port);
});
services/result/views/app.js ✏️
javascript
var app = angular.module('catsvsdogs', []);
var socket = io.connect();

var bg1 = document.getElementById('background-stats-1');
var bg2 = document.getElementById('background-stats-2');

app.controller('statsCtrl', function($scope, $http){
  $scope.aPercent = 50;
  $scope.bPercent = 50;
  $scope.optionA = '';
  $scope.optionB = '';

  // The option names come from the server (OPTION_A / OPTION_B), not from this file.
  $http.get('/config').then(function (res) {
    $scope.optionA = res.data.optionA;
    $scope.optionB = res.data.optionB;
    document.title = res.data.optionA + ' vs ' + res.data.optionB + ' -- Result';
  });

  var updateScores = function(){
    socket.on('scores', function (json) {
       data = JSON.parse(json);
       var a = parseInt(data.a || 0);
       var b = parseInt(data.b || 0);

       var percentages = getPercentages(a, b);

       bg1.style.width = percentages.a + "%";
       bg2.style.width = percentages.b + "%";

       $scope.$apply(function () {
         $scope.aPercent = percentages.a;
         $scope.bPercent = percentages.b;
         $scope.total = a + b;
       });
    });
  };

  var init = function(){
    document.body.style.opacity=1;
    updateScores();
  };
  socket.on('message',function(data){
    init();
  });
});

function getPercentages(a, b) {
  var result = {};

  if (a + b > 0) {
    result.a = Math.round(a / (a + b) * 100);
    result.b = 100 - result.a;
  } else {
    result.a = result.b = 50;
  }

  return result;
}
services/result/views/index.html ✏️
html
<!DOCTYPE html>
<html ng-app="catsvsdogs">
  <head>
    <meta charset="utf-8">
    <title>Result</title>
    <base href="/index.html">
    <meta name = "viewport" content = "width=device-width, initial-scale = 1.0">
    <meta name="keywords" content="docker-compose, docker, stack">
    <meta name="author" content="Docker">
    <link rel='stylesheet' href='/stylesheets/style.css' />
  </head>
  <body ng-controller="statsCtrl" >
     <div id="background-stats">
       <div id="background-stats-1">
       </div><!--
      --><div id="background-stats-2">
      </div>
    </div>
    <div id="content-container">
      <div id="content-container-center">
        <div id="choice">
          <div class="choice cats">
            <div class="label">{{optionA}}</div>
            <div class="stat">{{aPercent | number:1}}%</div>
          </div>
          <div class="divider"></div>
          <div class="choice dogs">
            <div class="label">{{optionB}}</div>
            <div class="stat">{{bPercent | number:1}}%</div>
          </div>
        </div>
      </div>
    </div>
    <div id="result">
      <span ng-if="total == 0">No votes yet</span>
      <span ng-if="total == 1">{{total}} vote</span>
      <span ng-if="total >= 2">{{total}} votes</span>
    </div>
    <script src="socket.io.js"></script>
    <script src="angular.min.js"></script>
    <script src="app.js"></script>
  </body>
</html>
services/result/views/stylesheets/style.css
css
@import url(//fonts.googleapis.com/css?family=Open+Sans:400,700,600);

*{
  box-sizing:border-box;
}
html,body{
  margin:0;
  padding:0;
  height:100%;
  font-family: 'Open Sans';
}
body{
  opacity:0;
  transition: all 1s linear;
}

.divider{
  height: 150px;
  width:2px;
  background-color: #C0C9CE;
  position: relative;
  top: 50%;
  float: left;
  transform: translateY(-50%);
}

#background-stats-1{
  background-color: #2196f3;
}

#background-stats-2{
  background-color: #00cbca;
}

#content-container{
  z-index:2;
  position:relative;
  margin:0 auto;
  display:table;
  padding:10px;
  max-width:940px;
  height:100%;
}
#content-container-center{
  display:table-cell;
  text-align:center;
  vertical-align:middle;
}
#result{
  z-index: 3;
  position: absolute;
  bottom: 40px;
  right: 20px;
  color: #fff;
  opacity: 0.5;
  font-size: 45px;
  font-weight: 600;
}
#choice{
  transition: all 300ms linear;
  line-height:1.3em;
  background:#fff;
  box-shadow: 10px 0 0 #fff, -10px 0 0 #fff;
  vertical-align:middle;
  font-size:40px;
  font-weight: 600;
  width: 450px;
  height: 200px;
}
#choice a{
  text-decoration:none;
}
#choice a:hover, #choice a:focus{
  outline:0;
  text-decoration:underline;
}

#choice .choice{
  width: 49%;
  position: relative;
  top: 50%;
  transform: translateY(-50%);
  text-align: left;
  padding-left: 50px;
}

#choice .choice .label{
  text-transform: uppercase;
}

#choice .choice.dogs{
  color: #00cbca;
  float: right;
}

#choice .choice.cats{
  color: #2196f3;
  float: left;
}
#background-stats{
  z-index:1;
  height:100%;
  width:100%;
  position:absolute;
}
#background-stats div{
  transition: width 400ms ease-in-out;
  display:inline-block;
  margin-bottom:-4px;
  width:50%;
  height:100%;
}
services/vote/.dockerignore
text
__pycache__/
*.pyc
services/vote/Dockerfile
dockerfile
# base defines a base stage that uses the official python runtime base image
FROM python:3.11-slim AS base

# Add curl for healthcheck
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*

# Set the application directory
WORKDIR /usr/local/app

# Install our requirements.txt
COPY requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# dev defines a stage for development, where it'll watch for filesystem changes
FROM base AS dev
RUN pip install watchdog
ENV FLASK_ENV=development
CMD ["python", "app.py"]

# final defines the stage that will bundle the application for production
FROM base AS final

# Copy our code from the current folder to the working directory inside the container
COPY . .

# Make port 80 available for links and/or publish
EXPOSE 80

# Define our command to be run when launching the container
CMD ["gunicorn", "app:app", "-b", "0.0.0.0:80", "--log-file", "-", "--access-logfile", "-", "--workers", "4", "--keep-alive", "0"]
services/vote/app.py ✏️
python
from flask import Flask, render_template, request, make_response, g
from redis import Redis
import os
import socket
import random
import json
import logging

# The voting options have no default: they come only from the environment
# (envs/<env>.tfvars -> Terraform -> task definition). A missing value fails at startup.
option_a = os.environ['OPTION_A']
option_b = os.environ['OPTION_B']
hostname = socket.gethostname()

# course change: the Redis address comes from the environment (ElastiCache endpoint on AWS)
redis_host = os.getenv('REDIS_HOST', 'redis')
redis_port = int(os.getenv('REDIS_PORT', '6379'))

app = Flask(__name__)

gunicorn_error_logger = logging.getLogger('gunicorn.error')
app.logger.handlers.extend(gunicorn_error_logger.handlers)
app.logger.setLevel(logging.INFO)

def get_redis():
    if not hasattr(g, 'redis'):
        g.redis = Redis(host=redis_host, port=redis_port, db=0, socket_timeout=5)
    return g.redis

@app.route("/healthz")
def healthz():
    # course change: a health check that does not depend on Redis, for the load balancer
    return "ok", 200


@app.route("/", methods=['POST','GET'])
def hello():
    voter_id = request.cookies.get('voter_id')
    if not voter_id:
        voter_id = hex(random.getrandbits(64))[2:-1]

    vote = None

    if request.method == 'POST':
        redis = get_redis()
        vote = request.form['vote']
        app.logger.info('Received vote for %s', vote)
        data = json.dumps({'voter_id': voter_id, 'vote': vote})
        redis.rpush('votes', data)

    resp = make_response(render_template(
        'index.html',
        option_a=option_a,
        option_b=option_b,
        hostname=hostname,
        vote=vote,
    ))
    resp.set_cookie('voter_id', voter_id)
    return resp


if __name__ == "__main__":
    app.run(host='0.0.0.0', port=80, debug=True, threaded=True)
services/vote/requirements.txt
text
Flask
Redis
gunicorn
services/vote/static/stylesheets/style.css
css
@import url(//fonts.googleapis.com/css?family=Open+Sans:400,700,600);

*{
  box-sizing:border-box;
}
html,body{
  margin: 0;
  padding: 0;
  background-color: #F7F8F9;
  height: 100vh;
  font-family: 'Open Sans';
}

button{
  border-radius: 0;
  width: 100%;
  height: 50%;
}

button[type="submit"] {
  -webkit-appearance:none; -webkit-border-radius:0;
}

button i{
  float: right;
  padding-right: 30px;
  margin-top: 3px;
}

button.a{
  background-color: #1aaaf8;
}

button.b{
  background-color: #00cbca;
}

#tip{
  text-align: left;
  color: #c0c9ce;
  font-size: 14px;
}

#hostname{
  position: absolute;
  bottom: 100px;
  right: 0;
  left: 0;
  color: #8f9ea8;
  font-size: 24px;
}

#content-container{
  z-index: 2;
  position: relative;
  margin: 0 auto;
  display: table;
  padding: 10px;
  max-width: 940px;
  height: 100%;
}
#content-container-center{
  display: table-cell;
  text-align: center;
}

#content-container-center h3{
  color: #254356;
}

#choice{
  transition: all 300ms linear;
  line-height: 1.3em;
  display: inline;
  vertical-align: middle;
  font-size: 3em;
}
#choice a{
  text-decoration:none;
}
#choice a:hover, #choice a:focus{
  outline:0;
  text-decoration:underline;
}

#choice button{
  display: block;
  height: 80px;
  width: 330px;
  border: none;
  color: white;
  text-transform: uppercase;
  font-size:18px;
  font-weight: 700;
  margin-top: 10px;
  margin-bottom: 10px;
  text-align: left;
  padding-left: 50px;
}

#choice button.a:hover{
  background-color: #1488c6;
}

#choice button.b:hover{
  background-color: #00a2a1;
}

#choice button.a:focus{
  background-color: #1488c6;
}

#choice button.b:focus{
  background-color: #00a2a1;
}

#background-stats{
  z-index:1;
  height:100%;
  width:100%;
  position:absolute;
}
#background-stats div{
  transition: width 400ms ease-in-out;
  display:inline-block;
  margin-bottom:-4px;
  width:50%;
  height:100%;
}
services/vote/templates/index.html
html
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title>{{option_a}} vs {{option_b}}!</title>
    <base href="/index.html">
    <meta name = "viewport" content = "width=device-width, initial-scale = 1.0">
    <meta name="keywords" content="docker-compose, docker, stack">
    <meta name="author" content="Tutum dev team">
    <link rel='stylesheet' href="{{ url_for('static',filename='stylesheets/style.css') }}" />
    <link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/font-awesome/4.4.0/css/font-awesome.min.css">
  </head>
  <body>
    <div id="content-container">
      <div id="content-container-center">
        <h3>{{option_a}} vs {{option_b}}!</h3>
        <form id="choice" name='form' method="POST" action="/">
          <button id="a" type="submit" name="vote" class="a" value="a">{{option_a}}</button>
          <button id="b" type="submit" name="vote" class="b" value="b">{{option_b}}</button>
        </form>
        <div id="tip">
          (Tip: you can change your vote)
        </div>
        <div id="hostname">
          Processed by container ID {{hostname}}
        </div>
      </div>
    </div>
    <script src="http://code.jquery.com/jquery-latest.min.js" type="text/javascript"></script>
    <script src="//cdnjs.cloudflare.com/ajax/libs/jquery-cookie/1.4.1/jquery.cookie.js"></script>

    {% if vote %}
    <script>
      var vote = "{{vote}}";

      if(vote == "a"){
        $(".a").prop('disabled', true);
        $(".a").html('{{option_a}} <i class="fa fa-check-circle"></i>');
        $(".b").css('opacity','0.5');
      }
      if(vote == "b"){
        $(".b").prop('disabled', true);
        $(".b").html('{{option_b}} <i class="fa fa-check-circle"></i>');
        $(".a").css('opacity','0.5');
      }
    </script>
    {% endif %}
  </body>
</html>
services/worker/.dockerignore
text
bin/
obj/
services/worker/Dockerfile
dockerfile
# because of dotnet, we always build on amd64, and target platforms in cli
# dotnet doesn't support QEMU for building or running. 
# (errors common in arm/v7 32bit) https://github.com/dotnet/dotnet-docker/issues/1537
# https://hub.docker.com/_/microsoft-dotnet
# hadolint ignore=DL3029
# to build for a different platform than your host, use --platform=<platform>
# for example, if you were on Intel (amd64) and wanted to build for ARM, you would use:
# docker buildx build --platform "linux/arm64/v8" .

# build compiles the program for the builder's local platform
FROM --platform=${BUILDPLATFORM} mcr.microsoft.com/dotnet/sdk:7.0 AS build
ARG TARGETPLATFORM
ARG TARGETARCH
ARG BUILDPLATFORM
RUN echo "I am running on $BUILDPLATFORM, building for $TARGETPLATFORM"

WORKDIR /source
COPY *.csproj .
RUN dotnet restore -a $TARGETARCH

COPY . .
RUN dotnet publish -c release -o /app -a $TARGETARCH --self-contained false --no-restore

# app image
FROM mcr.microsoft.com/dotnet/runtime:7.0
WORKDIR /app
COPY --from=build /app .
ENTRYPOINT ["dotnet", "Worker.dll"]
services/worker/Program.cs
csharp
using System;
using System.Data.Common;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Threading;
using Newtonsoft.Json;
using Npgsql;
using StackExchange.Redis;

namespace Worker
{
    public class Program
    {
        public static int Main(string[] args)
        {
            try
            {
                var pgsql = OpenDbConnection(DbConnectionString());
                var redisConn = OpenRedisConnection(RedisHost());
                var redis = redisConn.GetDatabase();

                // Keep alive is not implemented in Npgsql yet. This workaround was recommended:
                // https://github.com/npgsql/npgsql/issues/1214#issuecomment-235828359
                var keepAliveCommand = pgsql.CreateCommand();
                keepAliveCommand.CommandText = "SELECT 1";

                var definition = new { vote = "", voter_id = "" };
                while (true)
                {
                    // Slow down to prevent CPU spike, only query each 100ms
                    Thread.Sleep(100);

                    // Reconnect redis if down
                    if (redisConn == null || !redisConn.IsConnected) {
                        Console.WriteLine("Reconnecting Redis");
                        redisConn = OpenRedisConnection(RedisHost());
                        redis = redisConn.GetDatabase();
                    }
                    string json = redis.ListLeftPopAsync("votes").Result;
                    if (json != null)
                    {
                        var vote = JsonConvert.DeserializeAnonymousType(json, definition);
                        Console.WriteLine($"Processing vote for '{vote.vote}' by '{vote.voter_id}'");
                        // Reconnect DB if down
                        if (!pgsql.State.Equals(System.Data.ConnectionState.Open))
                        {
                            Console.WriteLine("Reconnecting DB");
                            pgsql = OpenDbConnection(DbConnectionString());
                        }
                        else
                        { // Normal +1 vote requested
                            UpdateVote(pgsql, vote.voter_id, vote.vote);
                        }
                    }
                    else
                    {
                        keepAliveCommand.ExecuteNonQuery();
                    }
                }
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine(ex.ToString());
                return 1;
            }
        }

        // course change: Redis and database settings come from the environment (ElastiCache and RDS on AWS)
        private static string Env(string name, string fallback)
            => Environment.GetEnvironmentVariable(name) ?? fallback;

        private static string RedisHost() => Env("REDIS_HOST", "redis");

        private static string DbConnectionString()
        {
            var cs = $"Server={Env("DB_HOST", "db")};Port={Env("DB_PORT", "5432")};" +
                     $"Username={Env("DB_USER", "postgres")};Password={Env("DB_PASSWORD", "postgres")};" +
                     $"Database={Env("DB_NAME", "postgres")};";
            // RDS Postgres 15+ refuses connections without TLS
            if (Env("DB_SSL", "false") == "true")
            {
                cs += "SSL Mode=Require;Trust Server Certificate=true;";
            }
            return cs;
        }

        private static NpgsqlConnection OpenDbConnection(string connectionString)
        {
            NpgsqlConnection connection;

            while (true)
            {
                try
                {
                    connection = new NpgsqlConnection(connectionString);
                    connection.Open();
                    break;
                }
                catch (SocketException)
                {
                    Console.Error.WriteLine("Waiting for db");
                    Thread.Sleep(1000);
                }
                catch (DbException)
                {
                    Console.Error.WriteLine("Waiting for db");
                    Thread.Sleep(1000);
                }
            }

            Console.Error.WriteLine("Connected to db");

            var command = connection.CreateCommand();
            command.CommandText = @"CREATE TABLE IF NOT EXISTS votes (
                                        id VARCHAR(255) NOT NULL UNIQUE,
                                        vote VARCHAR(255) NOT NULL
                                    )";
            command.ExecuteNonQuery();

            return connection;
        }

        private static ConnectionMultiplexer OpenRedisConnection(string hostname)
        {
            // Use IP address to workaround https://github.com/StackExchange/StackExchange.Redis/issues/410
            var ipAddress = GetIp(hostname);
            Console.WriteLine($"Found redis at {ipAddress}");

            while (true)
            {
                try
                {
                    Console.Error.WriteLine("Connecting to redis");
                    return ConnectionMultiplexer.Connect(ipAddress);
                }
                catch (RedisConnectionException)
                {
                    Console.Error.WriteLine("Waiting for redis");
                    Thread.Sleep(1000);
                }
            }
        }

        private static string GetIp(string hostname)
            => Dns.GetHostEntryAsync(hostname)
                .Result
                .AddressList
                .First(a => a.AddressFamily == AddressFamily.InterNetwork)
                .ToString();

        private static void UpdateVote(NpgsqlConnection connection, string voterId, string vote)
        {
            var command = connection.CreateCommand();
            try
            {
                command.CommandText = "INSERT INTO votes (id, vote) VALUES (@id, @vote)";
                command.Parameters.AddWithValue("@id", voterId);
                command.Parameters.AddWithValue("@vote", vote);
                command.ExecuteNonQuery();
            }
            catch (DbException)
            {
                command.CommandText = "UPDATE votes SET vote = @vote WHERE id = @id";
                command.ExecuteNonQuery();
            }
            finally
            {
                command.Dispose();
            }
        }
    }
}
services/worker/Worker.csproj
xml
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net7.0</TargetFramework>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="StackExchange.Redis" Version="2.2.4" />
    <PackageReference Include="Npgsql" Version="4.1.9" />
    <PackageReference Include="Newtonsoft.Json" Version="13.0.1" />
  </ItemGroup>

</Project>
קבצים שמופיעים במבנה אבל התוכן שלהם לא מודפס
קובץ	סיבה
README.md	לא נכלל לפי בקשה
Steps.md	לא נכלל לפי בקשה
bootstrap/.terraform.lock.hcl	קובץ נעילה שנוצר אוטומטית
infra/.terraform.lock.hcl	קובץ נעילה שנוצר אוטומטית
services/LICENSE	טקסט רישיון
services/README.md	לא נכלל לפי בקשה
services/result/package-lock.json	קובץ נעילה שנוצר אוטומטית
services/result/views/angular.min.js	ספרייה חיצונית (מוקטנת)
services/result/views/socket.io.js	ספרייה חיצונית (מוקטנת)

Claude finished the response
