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

  environment = {
    REDIS_HOST = local.redis_host
    OPTION_A   = var.option_a
    OPTION_B   = var.option_b
  }

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

  environment = local.db_env
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

