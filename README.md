# Final Project — Voting App on AWS (Terraform + GitHub Actions)

The final project of the Terraform course. There is no solution and no check script. You build the infrastructure **and** the delivery pipeline so that every **contract** below is true. How you get there is up to you.

Time: plan for one long day or two sessions. Cost: about 3 USD if you destroy everything the same day (RDS, ElastiCache and the load balancer are billed per hour).

## The story

You joined **VoteCo**, a small company. The developers finished a voting website: people choose between two options (ביבי or אייזנקוט) and watch the result live. It is built as three microservices and runs well on their laptops with docker compose.

The CTO gave you the assignment:

> "Run it on AWS, in two environments, **dev** and **prod**. Nobody deploys by hand. A developer opens a Pull Request, the team reviews the plan, and when it is merged the new version goes to dev by itself. Prod gets it only after a human approves. If a bad version is shipped, the site must stay up."

You do not change the application (almost). You build everything around it.

## The application

```
  browser --vote--> [ vote ] --push--> [ Redis ] --pop--> [ worker ] --insert--> [ Postgres ]
                    Python               queue              .NET                   the votes
                                                                                      |
  browser <--live-- [ result ] <------------------ select count(*) -----------------+
                    Node.js
```

Details, ports, environment variables and what was changed from the original: [services/README.md](services/README.md). **Read it first.**

## The target architecture

```
 VPC <name>-vpc (10.10.0.0/16 in dev, 10.20.0.0/16 in prod), 2 availability zones, built by YOUR Terraform
 +--------------------------------------------------------------------------------------------+
 |                          Internet Gateway                                                  |
 |  PUBLIC subnets (route 0.0.0.0/0 -> IGW)                                                   |
 |                     :80 |          | :8080                                                 |
 |                 +-------v----------v----+                                                  |
 |                 |   ALB (alb-sg)        |   one load balancer, two listeners               |
 |                 +-----+----------+------+                                                  |
 |                       | :80      | :80      (target type = ip, health check /healthz)      |
 |              +--------v---+  +---v--------+  +-----------------+                           |
 |              | vote  x N  |  | result x N |  | worker x N      |   ECS Fargate (ecs-sg)    |
 |              +--------+---+  +---+--------+  +----+-------+----+   public IP, no NAT       |
 |                       |          |                |       |                                |
 |  PRIVATE subnets (no route to the internet)        |       |                                |
 |                  :6379|          |:5432      :6379|       |:5432                           |
 |                 +-----v----+   +-v------------+   |       |                                |
 |                 | Redis    |<--+--------------+---+       |      ElastiCache (redis-sg)    |
 |                 +----------+                  |           |                                |
 |                                          +----v-----------v--+                             |
 |                                          | RDS Postgres        |  RDS (rds-sg)             |
 |                                          +---------------------+                           |
 +--------------------------------------------------------------------------------------------+
   ECR: vapp-vote, vapp-result, vapp-worker    Secrets Manager: db password
   CloudWatch: logs per service, alarm on 5xx  S3: Terraform state
```

Two environments, **same code**, different settings and different state:

```
   envs/dev.tfvars   ->  state key voting-app/dev/terraform.tfstate    ->  <prefix>-dev-*
   envs/prod.tfvars  ->  state key voting-app/prod/terraform.tfstate   ->  <prefix>-prod-*
```

The delivery pipeline:

```
  Pull Request                         push to main
  ------------                         -------------------------------------------------------------
  checks (fmt, validate)               checks --> build --> deploy dev --> smoke --> [approval] --> deploy prod --> smoke
  build (no push)                                 |            |                                        |
  plan dev + plan prod                   3 images tagged       apply with       the SAME image tag (no rebuild)
  (no apply, ever)                       with the git commit   that tag
```

## What is given and what you write

| Path | Who | What |
|---|---|---|
| `services/` | **given** | The three microservices, with their Dockerfiles |
| `bootstrap/*.tf` | **given** | Run **once, by hand**. Creates the state bucket, three ECR repositories, the GitHub OIDC trust and the IAM role of the pipeline. It is already split by concern: **read it as an example of contract C1** |
| `infra/` | **you write** | All the Terraform. The files already exist (one comment line each, see contract C1), and you fill them: the root files, the local module `infra/modules/service`, and `infra/envs/dev.tfvars`, `infra/envs/prod.tfvars` |
| `.github/workflows/deploy.yml` | **you write** | The pipeline. The file exists with a comment only. You may add more workflow files |

## Setup (once)

**1. A separate GitHub repo.** GitHub Actions only reads `.github/workflows/` from the **root of a repo**. Create a new empty **private** repo and make the content of this folder its root:

```bash
mkdir ~/final-project && cp -r bootstrap services infra .github .gitignore README.md Steps.md ~/final-project/
cd ~/final-project
git init -b main
git remote add origin https://github.com/<your-user>/<your-repo>.git
```

**2. Bootstrap** (from your machine, with your AWS CLI credentials):

```bash
cd bootstrap
terraform init
terraform apply -var="github_org=<your-user>" -var="github_repo=<your-repo>" -var="name_prefix=<name>"
```

If it fails with `EntityAlreadyExists` for the OIDC provider, add `-var="create_oidc_provider=false"`.

**3. Three GitHub repository variables** (repo → Settings → Secrets and variables → Actions → **Variables**):

| Variable | Value |
|---|---|
| `AWS_ROLE_ARN` | output `role_arn` |
| `TF_STATE_BUCKET` | output `state_bucket` |
| `NAME_PREFIX` | the same `<name>` |

**4. Two GitHub Environments** (repo → Settings → Environments): create `dev` (nothing special) and `prod` with **Required reviewers** = you. This is what makes the pipeline wait for a human before prod.

> Environments with required reviewers on a **private** repo need a paid GitHub plan. On a free plan, make the repo public (there are no secrets in it), or skip contract P7 and do it as a discussion.

**Keep the `bootstrap/` folder and its `terraform.tfstate`.** You need them for the cleanup.

## Ground rules

- Region `eu-north-1`. Terraform `>= 1.10`. AWS provider `~> 5.0`, plus the `random` provider.
- **You build the network.** Do not use the default VPC, not even to read it. **No NAT Gateway** (it costs money per hour).
- **No AWS access keys anywhere.** Only the OIDC role.
- **No secret in the code, in the task definition's plain `environment`, in outputs, or in the logs.**
- The state is in the S3 bucket from the bootstrap, one key per environment. `backend "s3" {}` stays **empty**, the settings come from `-backend-config`.
- `name_prefix` (from the bootstrap, lowercase letters, digits and hyphens, up to 12 characters) and the environment name build every name: `local.name = "<name_prefix>-<env>"`.

Names (`<name>` = `<name_prefix>-<env>`, for example `acme-dev`):

| Resource | Name |
|---|---|
| Security groups | `<name>-alb-sg`, `<name>-ecs-sg`, `<name>-redis-sg`, `<name>-rds-sg` |
| ALB / target groups | `<name>-alb` / `<name>-vote`, `<name>-result` |
| ECS cluster | `<name>-cluster` |
| ECS services / log groups | `<name>-vote`, `<name>-result`, `<name>-worker` / `/ecs/<name>-vote` and so on |
| ElastiCache cluster / RDS identifier | `<name>-redis` / `<name>-db` |
| Secret | `<name>-db-password` |
| Task execution role | `<name>-exec` |
| SNS topic / alarm | `<name>-alerts` / `<name>-alb-5xx` |
| ECR repositories (from the bootstrap) | `<name_prefix>-vote`, `<name_prefix>-result`, `<name_prefix>-worker` |

> The pipeline role may create IAM roles **only if their name starts with `<name_prefix>-`**.

## Contracts — code organization (separation of concerns)

Code that is split by concern is easier to read, to review in a Pull Request and to change without breaking something else. A file answers one question: *"where do I find X?"*

| # | Contract |
|---|---|
| C1 | `infra/` is split into files by concern, with **these exact names**: see the table below. There is **no `main.tf`** in `infra/` |
| C2 | One home for each kind of block: **every** `variable` is in `variables.tf`, **every** `output` is in `outputs.tf`, the `terraform {}` block with the backend and the `provider` block are in `providers.tf`. No such block appears in any other file |
| C3 | Every resource lives in the file of its concern. A resource that belongs to the network is never in `ecs.tf`, and the other way around. A `locals` block lives next to the resources it serves. Only locals that **several files** use go to `locals.tf` |
| C4 | The module `infra/modules/service` has the same structure: `main.tf` (resources), `variables.tf` (inputs), `outputs.tf` (outputs) |
| C5 | Moving code between files changes nothing in AWS: `terraform plan` before and after the split shows the same resources and **no changes** |

The files of `infra/`:

| File | What it contains |
|---|---|
| `providers.tf` | `terraform {}` (version, `required_providers`, the empty `backend "s3" {}`) and `provider "aws"` with `default_tags` |
| `variables.tf` | All the input variables, with their `validation` blocks |
| `locals.tf` | Locals shared by several files (the `<name_prefix>-<env>` name) |
| `outputs.tf` | All the outputs |
| `network.tf` | The availability zones data source, VPC, Internet Gateway, subnets, route tables and associations, **security groups**, **load balancer**, target groups and listeners |
| `cache.tf` | ElastiCache: subnet group and cluster |
| `database.tf` | RDS: subnet group and instance, the generated password and its Secrets Manager secret |
| `registry.tf` | The data sources that read the three ECR repositories |
| `iam.tf` | The task execution role, its policy attachment and the permission to read the secret |
| `ecs.tf` | The ECS cluster, the environment variables and secrets of the services, and the three calls to the `service` module |
| `monitoring.tf` | The SNS topic and the CloudWatch alarm |

## Contracts — network and security

| # | Contract |
|---|---|
| N1 | A VPC `<name>-vpc` with DNS support and DNS hostnames enabled. Its range comes from a variable `vpc_cidr` with **no default**: `10.10.0.0/16` in `envs/dev.tfvars` and `10.20.0.0/16` in `envs/prod.tfvars`. The default VPC is not used anywhere in the code |
| N2 | **Four /24 subnets in two availability zones**: two public (`<name>-public-<az>`) and two private (`<name>-private-<az>`). The zones come from `data "aws_availability_zones"` (the first two), and the ranges are computed with `cidrsubnet` from `vpc_cidr`, not typed by hand. The subnets are created with `for_each` |
| N3 | An Internet Gateway, and a **public route table** with `0.0.0.0/0` to the gateway, associated with both public subnets. A **private route table** with **no** route to the internet (no NAT), associated with both private subnets |
| N4 | Placement: the ALB and the ECS tasks run in the **public** subnets. The RDS subnet group and the ElastiCache subnet group use the **private** subnets only |
| N5 | `alb-sg`: 80 and 8080 from the internet. `ecs-sg`: 80 **only from `alb-sg`** (a reference to the SG, not a CIDR) and all outbound. `redis-sg`: 6379 **only from `ecs-sg`**. `rds-sg`: 5432 **only from `ecs-sg`** |

## Contracts — data

| # | Contract |
|---|---|
| D1 | ElastiCache for Redis: engine `redis` 7.1, `cache.t3.micro`, one node, a subnet group over the **private** subnets, attached only to `redis-sg` |
| D2 | RDS Postgres 16: `db.t3.micro`, 20 GB, database name `votes`, user `voteadmin`, `publicly_accessible = false`, attached only to `rds-sg`, no final snapshot |
| D3 | The database password is generated by Terraform (`random_password`, **no special characters**) and stored in a Secrets Manager secret `<name>-db-password`. The secret is deleted immediately on `destroy` (no recovery window) |
| D4 | The services receive the password through the task definition's `secrets` block (`valueFrom` = the secret ARN), never through `environment`. The execution role may read **only that secret** |

## Contracts — load balancer

| # | Contract |
|---|---|
| L1 | One internet-facing Application Load Balancer. Listener **80** forwards to the `vote` target group. Listener **8080** forwards to the `result` target group |
| L2 | Both target groups: `target_type = ip`, port 80, health check on `/healthz` with matcher 200 |
| L3 | `worker` is **not** behind the load balancer and has no port |

## Contracts — services

| # | Contract |
|---|---|
| S1 | One ECS cluster per environment |
| S2 | A **local module** `infra/modules/service` creates, for one service: the log group, the task definition and the ECS service. It is called **three times**: `vote`, `result`, `worker`. Only `vote` and `result` get a container port and a target group (the module must work without them) |
| S3 | Every service: Fargate, `awsvpc`, 256 CPU / 512 MB, public IP, in the **public** subnets with `ecs-sg`. Logs go to `/ecs/<name>-<service>` with 7 days retention, created by Terraform |
| S4 | Environment variables of the containers, as in the table below |
| S5 | The image is `<ECR repository URL>:<image_tag>`. The repository is **read with a data source** (the bootstrap created it). `image_tag` is a variable with no default |
| S6 | A bad deployment rolls back by itself: `deployment_circuit_breaker` with rollback enabled, and `wait_for_steady_state = true` so that `terraform apply` waits until the deployment is finished (new version up, **or rolled back**) |
| S7 | One task execution role `<name>-exec`: trusts `ecs-tasks.amazonaws.com`, has `AmazonECSTaskExecutionRolePolicy`, plus the read access from D4 |

Container variables (S4):

| Service | Variable | Value |
|---|---|---|
| vote | `REDIS_HOST` | the ElastiCache endpoint address (from the resource, not typed) |
| vote | `OPTION_A`, `OPTION_B` | from variables `option_a`, `option_b` (defaults `ביבי`, `אייזנקוט`) |
| result | `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_NAME` | from the RDS resource |
| result | `DB_SSL` | `true` |
| result | `DB_PASSWORD` | from the secret (D4) |
| worker | `REDIS_HOST` | as in vote |
| worker | `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_NAME`, `DB_SSL` | as in result |
| worker | `DB_PASSWORD` | from the secret (D4) |

## Contracts — environments

| # | Contract |
|---|---|
| E1 | **One code base** in `infra/`. The environment is a variable `env` (only `dev` or `prod` are accepted, with a `validation` block). The differences live in `envs/dev.tfvars` and `envs/prod.tfvars` |
| E2 | `dev` runs 1 task per service. `prod` runs 2 |
| E3 | Separate state per environment (key `voting-app/<env>/terraform.tfstate`). Applying dev never touches prod |
| E4 | `default_tags` on every resource: `Project = "voting-app"`, `Environment = <env>`, `Owner = <name_prefix>` |
| E5 | `name_prefix` has a `validation` block: lowercase letters, digits and hyphens, up to 12 characters |

## Contracts — operations

| # | Contract |
|---|---|
| O1 | An SNS topic `<name>-alerts` and a CloudWatch alarm `<name>-alb-5xx` on the metric `HTTPCode_Target_5XX_Count` of the ALB (sum over 60 seconds, threshold 5, missing data = not breaching). The alarm's action is the topic |
| O2 | Outputs: `vote_url` (`http://<alb dns>`), `result_url` (`http://<alb dns>:8080`), `redis_endpoint`, `db_endpoint` |

## Contracts — pipeline

| # | Contract |
|---|---|
| P1 | Runs on a `pull_request` to `main` and on a `push` to `main`, only when `services/**`, `infra/**` or `.github/workflows/**` changed |
| P2 | OIDC only: `id-token: write` and `aws-actions/configure-aws-credentials` with `vars.AWS_ROLE_ARN`. Nothing account-specific is hard-coded: the bucket, the role and `name_prefix` come from `vars.*` |
| P3 | `checks`: `terraform fmt -check -recursive` and `terraform validate` (with `init -backend=false`) |
| P4 | `build`: one image per service, tagged with the **git commit SHA** (`github.sha`), built for `linux/amd64`. It is **pushed only on `main`**. On a Pull Request the image is built but not pushed. If the tag already exists in ECR, the step is skipped (re-running a green pipeline must not fail) |
| P5 | On a Pull Request: `terraform plan` for **dev and prod**, with `image_tag = <the commit>`. **Apply never runs on a Pull Request** |
| P6 | On a push to `main`: after `build`, **deploy dev** (`init`, `apply -auto-approve`) |
| P7 | **Deploy prod** runs after dev succeeded, and waits for a human approval (GitHub Environment `prod` with required reviewers) |
| P8 | Prod gets **exactly the image tag that dev ran**. Nothing is rebuilt between the two |
| P9 | After every deploy, a **smoke test** reads `vote_url` and `result_url` from `terraform output` and calls `/healthz` on both. The job fails if one of them is not 200 |
| P10 | After the smoke test, a **version check**: `terraform plan -detailed-exitcode` with the same variables must exit with 0 (no changes). Exit code 2 fails the job. This is what catches a deployment that ECS rolled back (see F4) |
| P11 | Two runs never apply to the same environment at the same time (a `concurrency` group per environment, without cancelling a running apply) |

## Contracts — the real test

| # | Contract |
|---|---|
| F1 | The first push to `main` creates dev and then prod, and both smoke tests are green. In dev, a vote cast on `vote_url` appears on `result_url` within seconds |
| F2 | A Pull Request that adds `option_a = "Pizza"` to `envs/dev.tfvars`. The dev plan shows `OPTION_A` changing in the `vote` task definition, and the prod plan does not mention `OPTION_A`. After the merge and the dev deployment, the dev vote page shows `Pizza`. Prod (after approval) still shows `ביבי` |
| F3 | A Pull Request that changes the text of the vote page in `services/vote/templates/index.html` builds a new image. After the merge, dev runs the new image without downtime (refresh the page during the deployment). Prod waits for approval. After approval, prod runs the same image tag |
| F4 | **Break it on purpose**: a Pull Request that makes the `vote` container crash at startup. After the merge, ECS tries the new version, gives up and rolls back (this takes **10 to 20 minutes**), and the site keeps answering with the previous version the whole time. The dev job turns **red** at the version check (P10), and prod is never touched |
| F5 | `terraform destroy` of both environments and then of the bootstrap leaves **nothing** in the account |

## Steps

The work plan, step by step, with the pitfalls of each step: [Steps.md](Steps.md).

## When something does not work

ECS Console → cluster → service → **Events**, then **Tasks** → Stopped → the reason. For the application: CloudWatch → Log groups → `/ecs/<name>-<service>`.

| What you see | Where to look |
|---|---|
| `CannotPullContainerError` | `assign_public_ip`, tasks in a public subnet, the route table of that subnet, egress of `ecs-sg`, the image name and tag, the architecture |
| `exec format error` in the logs | the image was built for arm64. Build with `--platform linux/amd64` |
| `ResourceInitializationError ... secret` | D4: the execution role cannot read the secret |
| Targets `unhealthy` | health check path `/healthz`, `ecs-sg` allows 80 from `alb-sg`, the container port |
| 503 from the ALB | no healthy targets yet, or a service with `desired_count = 0` |
| The result page stays at 0 and `worker` logs `Waiting for db` | `DB_SSL`, `rds-sg`, the password, the host |
| `result` logs `Waiting for db: no pg_hba.conf entry` | `DB_SSL = "true"` is missing |
| `Error acquiring the state lock` | another run is going, or a cancelled run left a lock |
| `AccessDenied` on `iam:` in the pipeline | the role name does not start with `<name_prefix>-` |
| Secret `already scheduled for deletion` | the secret was created before D3. Delete it with `aws secretsmanager delete-secret --force-delete-without-recovery` |
| Prod plan shows dev resources | `init` was not redone with the prod state key |
| The dev job is red at the version check, but `apply` was green | the deployment was rolled back by ECS. Read the stopped tasks of the service, the reason is there |
