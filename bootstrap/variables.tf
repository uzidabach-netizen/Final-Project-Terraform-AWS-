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
