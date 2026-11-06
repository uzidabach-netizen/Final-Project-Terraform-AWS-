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

