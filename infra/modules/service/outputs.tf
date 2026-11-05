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

