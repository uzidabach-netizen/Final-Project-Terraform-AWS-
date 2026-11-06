# Steps — Final Project

The steps of the final project. The contracts are in [README.md](README.md).

Work in order. Do not move on before the current step works. Debugging Terraform through a pipeline is slow, so **run each infrastructure step on your machine first**.

### Step 1 — Look at the application and run it locally

Follow "Run it on your machine" in [services/README.md](services/README.md). Vote a few times and see the result change. Then remove the containers. You now know what each service needs.

### Step 2 — The network and the data (N1–N5, D1–D4)

Start with `infra/` for **dev only**, on your machine. The files of contract C1 already exist and are empty (one comment line says what belongs in each). **Put each block in the right file as you write it.** It is much easier than writing one big file and splitting it later. First the network (N1–N4), then the security groups and the data stores:

```bash
cd infra
terraform init \
  -backend-config="bucket=<state_bucket>" \
  -backend-config="key=voting-app/dev/terraform.tfstate" \
  -backend-config="region=eu-north-1" \
  -backend-config="use_lockfile=true"
terraform apply -var-file=envs/dev.tfvars -var="name_prefix=<name>" -var="image_tag=none"
```

RDS and ElastiCache take about 5 to 10 minutes. Apply this step early and keep coding while they are created.

Pitfalls:
- **A subnet is public only because of its route table.** A subnet with a route to the Internet Gateway is public, one without it is private. Forgetting the `aws_route_table_association` leaves the subnet on the VPC's main route table (no internet), and the ALB or the tasks cannot be reached.
- **Check the network before you build on it.** `terraform plan` should show 1 VPC, 1 gateway, 4 subnets, 2 route tables and 4 associations. In the console (VPC → Subnets) each subnet shows the zone and the route table you expect.
- **Two availability zones are mandatory** for the ALB, the RDS subnet group and the ElastiCache subnet group.
- **`cidrsubnet(var.vpc_cidr, 8, n)`** cuts a /24 out of a /16. Use different numbers for public and private (for example 0 and 1, and 10 and 11), or two subnets get the same range.
- **Every security group needs the `vpc_id` of your VPC.** Without it, it is created in the default VPC and cannot be attached to your resources.
- **The name of a VPC or a subnet is a tag** (`Name`), not an argument. Without the tag the console shows only ids.
- **Security group names must not start with `sg-`**, and a `description` is required.
- **A security group with no `egress` block** loses the default "allow all outbound" rule. This is important for `ecs-sg` (step 4). Redis and RDS do not need outbound.
- **`aws_db_instance`: `db_name`, not `name`.** Use `skip_final_snapshot = true`, or `destroy` fails.
- **Set `vpc_security_group_ids` on RDS and `security_group_ids` on ElastiCache**, or they get the VPC default security group.
- **`random_password` with special characters** breaks the .NET connection string, because `;` and `=` are separators. Use `special = false`.
- **Secrets Manager keeps a deleted secret for 7 to 30 days** and blocks the same name. With `recovery_window_in_days = 0` it disappears at once, and you can destroy and re-apply on the same day.
- **ElastiCache engine and parameter group must match**: Redis 7.1 goes with `default.redis7`.
- **Read the ElastiCache address** from `cache_nodes[0].address`, not from a different attribute. Check it with `terraform console` or an output.

### Step 3 — The `service` module (S2, S3, S5, S6)

Write `infra/modules/service` so that it receives the name, the image, the cluster, the network, the environment variables and the secrets as variables. Optional parts (a container port and a target group) are `null` by default.

Pitfalls:
- **`container_definitions` is JSON.** Use `jsonencode(...)`.
- **Environment as a map in the module, as a list of `{name, value}` in the JSON.** A `for` expression converts it.
- **`secrets` is a list of `{name, valueFrom}`**, a different block from `environment`.
- **A port mapping only when there is a port**: `var.container_port == null ? [] : [...]`.
- **A `load_balancer` block only when there is a target group**: a `dynamic` block with `for_each` over an empty or one-item list (module 05).
- **`container_name` and `container_port` in the service's `load_balancer` block must match the container definition.**
- **The service is created before the listener**: the error says the target group "does not have an associated load balancer". Add `depends_on` to the module call.
- **Valid CPU and memory pairs**: with 256 CPU, memory is 512, 1024 or 2048.
- **`assign_public_ip = true`.** Without NAT, a task needs a public IP to pull its image, otherwise `CannotPullContainerError`. A public IP works only in a public subnet (a route to the gateway).
- **Create the log group in Terraform** and use `awslogs-region` from a data source, not typed by hand.

### Step 4 — Images, the load balancer and the three services (S1, S4, S7, L1–L3)

The services need images in ECR before they can start. For this step push the first version by hand, once (the pipeline will do it from now on):

```bash
REG=<account>.dkr.ecr.eu-north-1.amazonaws.com
aws ecr get-login-password --region eu-north-1 | docker login --username AWS --password-stdin $REG
for s in vote result worker; do
  docker buildx build --platform linux/amd64 --push -t $REG/<name_prefix>-$s:v1 services/$s
done
```

Then `terraform apply -var="image_tag=v1" ...`.

Pitfalls:
- **Fargate runs `linux/amd64` by default.** An image built on an Apple Silicon Mac without `--platform linux/amd64` fails with `exec format error` in the task logs.
- **ECR tags are immutable** (set by the bootstrap). Pushing `v1` a second time fails. Use a new tag.
- **The ALB needs at least 2 subnets in different AZs.** Give it the two public subnets.
- **`target_type = "ip"`** for Fargate. The default (`instance`) fails only when the service is created.
- **Target group and ALB names are up to 32 characters**, letters, digits and hyphens. A long `name_prefix` breaks this.
- **`DB_SSL = "true"`** for `result` and `worker`. Without it the logs say `no pg_hba.conf entry ... no encryption` (RDS Postgres 15 and newer requires TLS) and the page stays at zero.
- **The task execution role needs the secret read permission** (D4), or the task stops with `ResourceInitializationError ... unable to retrieve secret`.
- **Wait 2 to 3 minutes after `apply`** for the targets to become `healthy`.
- **The `worker` has no health check and no port.** To know it works, vote and see the number change on the result page.

When it works: open `vote_url`, vote, open `result_url`.

### Step 5 — Operations and the second environment (O1, O2, E1–E5)

Add the alarm, the outputs, the validations and `default_tags`. Then create `envs/prod.tfvars`.

First check the code organization (C1–C4). From `infra/`:

```bash
ls main.tf                              # must fail: there is no main.tf
grep -l '^variable' *.tf                # must print only variables.tf
grep -l '^output' *.tf                  # must print only outputs.tf
grep -l '^provider\|^terraform' *.tf    # must print only providers.tf
ls modules/service                      # main.tf  outputs.tf  variables.tf
```

If you split an existing file (C5), run `terraform plan` before and after. It must show the same thing, with no changes.

Do **not** apply prod from your machine now. The pipeline will do it. But do run `terraform plan -var-file=envs/prod.tfvars` with the prod state key, to see that it wants to create everything new and touches nothing of dev.

Pitfalls:
- **The state key is what separates the environments.** If you `init` dev, and then `plan` prod without `init -reconfigure` with the prod key, Terraform plans against the dev state.
- **Every name must contain the environment** (`local.name`), or dev and prod collide on the first apply.
- **`default_tags` can use a variable** (`var.env`), because the provider block may reference variables.

### Step 6 — The pipeline (P1–P11)

Write `.github/workflows/`. Build it in this order and push after each part:

1. `checks` (P1, P2, P3)
2. `build` (P4)
3. `plan` on Pull Requests (P5)
4. `deploy dev`, the smoke test and the version check (P6, P9, P10, P11)
5. `deploy prod` with the approval (P7, P8)

Building blocks to look up: `actions/checkout`, `aws-actions/configure-aws-credentials`, `aws-actions/amazon-ecr-login`, `docker/setup-buildx-action`, `docker/build-push-action`, `hashicorp/setup-terraform` (with `terraform_wrapper: false`), `environment:` on a job, `concurrency:`, `needs:`, a matrix over the three services, and (to avoid repeating dev and prod) a reusable workflow with `workflow_call`.

Pitfalls:
- **`permissions: id-token: write`** is mandatory, or the credentials step fails with "Could not load credentials". Add `contents: read` too.
- **`Not authorized to perform sts:AssumeRoleWithWebIdentity`**: the org or repo name in the bootstrap does not match the real repo, or `AWS_ROLE_ARN` is wrong. To see what GitHub really sent: CloudTrail, event `AssumeRoleWithWebIdentity`, field `userName`.
- **`vars.X` is empty**: you created it as a Secret, or in another repo.
- **The image tag is `github.sha`**: the same value must reach the `build` job and the `deploy` job. They run in different jobs, so use `github.sha` in both, not a value computed in one job.
- **`push: false` on a Pull Request.** The runner has credentials, but a PR must never change ECR.
- **Tag already exists**: with immutable tags, a re-run of the same commit fails at the push. Check with `aws ecr describe-images --image-ids imageTag=...` and skip the push.
- **A rolled-back deployment is a green `terraform apply`.** With `wait_for_steady_state`, Terraform waits until the service is steady again, and a service that went back to the old version is steady. So `apply` exits 0 and the smoke test is green (the old version answers!). Only the version check (P10) notices: Terraform wants to move the service to the new task definition, so `plan -detailed-exitcode` returns 2.
- **Smoke test without `--fail`** exits 0 on a 500. Add `--fail`, and `--retry 10 --retry-delay 6 --retry-all-errors` because the targets need a moment.
- **Do not cancel a running apply** (`cancel-in-progress: false`). Cancelling in the middle can leave the state locked.
- **A job in a reusable workflow that uses an Environment** pauses at the approval. Check that the `prod` job really waits, before you trust it.
- **Add `-input=false`** to every Terraform command in CI, and `-no-color` for readable logs.

### Step 7 — Prove everything (F1–F4)

Go through F1, F2, F3 and F4 in order, and write down for each: what you did, what the pipeline showed, and how you checked the result.

For F4, an easy way to crash `vote`: add `raise SystemExit(1)` at the top of `services/vote/app.py`. Watch the `deploy dev` job. It stays on `aws_ecs_service` for 10 to 20 minutes (ECS retries the crashing task with a growing delay, and only then gives up), then the `apply` finishes **successfully** and the version check turns the job red. In the ECS console (service → Deployments) you see the failed deployment and the rollback. Keep a terminal with `while true; do curl -s -o /dev/null -w "%{http_code}\n" <vote_url>/healthz; sleep 2; done` running: it must print 200 the whole time.

### Step 8 — Cleanup (F5)

Delete in this order. The bootstrap goes last, because it holds the state bucket and the role.

```bash
cd infra
for env in prod dev; do
  terraform init -reconfigure \
    -backend-config="bucket=<state_bucket>" -backend-config="key=voting-app/$env/terraform.tfstate" \
    -backend-config="region=eu-north-1" -backend-config="use_lockfile=true"
  terraform destroy -var-file=envs/$env.tfvars -var="name_prefix=<name>" -var="image_tag=none"
done

cd ../bootstrap
terraform destroy -var="github_org=<your-user>" -var="github_repo=<your-repo>" -var="name_prefix=<name>"
```

Each environment takes 5 to 10 minutes to destroy. Then check in the console (ECS, RDS, ElastiCache, EC2 → Load Balancers, ECR, Secrets Manager) that nothing is left.
