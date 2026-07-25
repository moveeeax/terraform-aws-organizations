resource "aws_organizations_organization" "this" {
  feature_set                   = var.feature_set
  aws_service_access_principals = var.aws_service_access_principals
  enabled_policy_types          = var.enabled_policy_types

  # WARNING: destroying this resource calls DeleteOrganization, which tears down
  # the entire AWS Organization of the management account. That is irreversible
  # (the organization ID is never reissued) and it removes every OU and policy
  # underneath it. `prevent_destroy` cannot be driven by a variable and is not
  # hardcoded here so that consumers keep control of their own lifecycle; see the
  # README section "Destroying an organization" for how to guard this.

  lifecycle {
    # Organization policies (SCPs, tag policies, backup policies, RCPs, ...) only
    # exist when all features are enabled. With CONSOLIDATED_BILLING the API
    # rejects the call at apply time with an opaque ConstraintViolationException,
    # so fail at plan time with an explanation instead.
    precondition {
      condition     = var.feature_set == "ALL" || length(var.enabled_policy_types) == 0
      error_message = "enabled_policy_types requires feature_set = \"ALL\". With CONSOLIDATED_BILLING, AWS Organizations cannot enable any policy type, so service control policies are impossible."
    }

    # Trusted access for AWS services likewise requires all features enabled.
    precondition {
      condition     = var.feature_set == "ALL" || length(var.aws_service_access_principals) == 0
      error_message = "aws_service_access_principals requires feature_set = \"ALL\". Trusted access for AWS services cannot be enabled with CONSOLIDATED_BILLING."
    }
  }
}

resource "aws_organizations_organizational_unit" "this" {
  for_each = toset(var.organizational_units)

  name      = each.value
  parent_id = aws_organizations_organization.this.roots[0].id

  tags = var.tags
}
