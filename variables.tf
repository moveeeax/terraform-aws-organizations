variable "feature_set" {
  description = "Feature set to enable for the organization. Either ALL or CONSOLIDATED_BILLING."
  type        = string
  default     = "ALL"

  validation {
    condition     = contains(["ALL", "CONSOLIDATED_BILLING"], var.feature_set)
    error_message = "feature_set must be either ALL or CONSOLIDATED_BILLING."
  }
}

variable "aws_service_access_principals" {
  description = "List of AWS service principals granted access across the organization."
  type        = list(string)
  default     = []
}

variable "enabled_policy_types" {
  description = "List of organization policy types to enable in the root."
  type        = list(string)
  default     = []
}

variable "organizational_units" {
  description = "List of organizational unit names to create directly under the organization root. Names must be unique; duplicates are rejected rather than silently collapsed."
  type        = list(string)
  default     = []

  validation {
    # The resource is keyed by `toset(var.organizational_units)`, which silently
    # collapses duplicates, so a typo'd repeat would create fewer OUs than asked
    # for with no diff to show for it.
    condition     = length(var.organizational_units) == length(distinct(var.organizational_units))
    error_message = "organizational_units must not contain duplicate names."
  }

  validation {
    condition = alltrue([
      for name in var.organizational_units : length(name) > 0 && length(name) <= 128
    ])
    error_message = "Each organizational unit name must be between 1 and 128 characters."
  }
}

variable "tags" {
  description = "Tags applied to the organizational units."
  type        = map(string)
  default     = {}
}
