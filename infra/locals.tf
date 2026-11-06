# Locals shared by several files (the <name_prefix>-<env> name)
locals {
  # Used in the name of almost every resource: <name_prefix>-<env>
  name = "${var.name_prefix}-${var.env}"
}

