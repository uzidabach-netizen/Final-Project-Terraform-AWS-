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
