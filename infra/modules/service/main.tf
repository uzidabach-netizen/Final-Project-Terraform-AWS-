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

