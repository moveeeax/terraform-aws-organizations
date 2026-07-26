# Test-only requirement: `mock_provider` needs Terraform >= 1.7.
# The module itself still supports >= 1.5 (see versions.tf) — do not bump it.
#
# Run with:  terraform init -backend=false && terraform test

mock_provider "aws" {
  mock_resource "aws_organizations_organization" {
    defaults = {
      id                = "o-mock000000"
      arn               = "arn:aws:organizations::123456789012:organization/o-mock000000"
      master_account_id = "123456789012"
      roots = [
        {
          id           = "r-mock"
          name         = "Root"
          arn          = "arn:aws:organizations::123456789012:root/o-mock000000/r-mock"
          policy_types = []
        }
      ]
    }
  }
}

run "defaults_enable_all_features_and_create_nothing_else" {
  assert {
    condition     = aws_organizations_organization.this.feature_set == "ALL"
    error_message = "Default feature_set must be ALL; CONSOLIDATED_BILLING makes service control policies impossible."
  }

  assert {
    condition     = length(aws_organizations_organization.this.enabled_policy_types) == 0
    error_message = "No policy types should be enabled unless the caller asks for them."
  }

  assert {
    condition     = length(aws_organizations_organizational_unit.this) == 0
    error_message = "No organizational units should be created by default."
  }
}

run "creates_each_requested_organizational_unit_under_the_root" {
  variables {
    organizational_units = ["workloads", "sandbox"]
    tags                 = { ManagedBy = "terraform" }
  }

  assert {
    condition     = length(aws_organizations_organizational_unit.this) == 2
    error_message = "One organizational unit must be created per requested name."
  }

  assert {
    condition     = aws_organizations_organizational_unit.this["workloads"].name == "workloads"
    error_message = "Organizational unit name must match the requested name."
  }

  assert {
    condition = alltrue([
      for ou in aws_organizations_organizational_unit.this :
      ou.parent_id == aws_organizations_organization.this.roots[0].id
    ])
    error_message = "Organizational units must be attached to the organization root."
  }

  assert {
    condition = alltrue([
      for ou in aws_organizations_organizational_unit.this : ou.tags["ManagedBy"] == "terraform"
    ])
    error_message = "Tags must be applied to every organizational unit."
  }
}

run "enables_requested_policy_types_when_all_features_are_on" {
  variables {
    feature_set                   = "ALL"
    enabled_policy_types          = ["SERVICE_CONTROL_POLICY", "TAG_POLICY"]
    aws_service_access_principals = ["cloudtrail.amazonaws.com"]
  }

  assert {
    condition     = contains(aws_organizations_organization.this.enabled_policy_types, "SERVICE_CONTROL_POLICY")
    error_message = "Requested policy types must be passed through to the organization root."
  }
}

# CONSOLIDATED_BILLING silently rules out every organization policy type, so the
# module must refuse the combination at plan time rather than let AWS fail the
# apply with an opaque ConstraintViolationException.
run "rejects_policy_types_without_all_features" {
  command = plan

  variables {
    feature_set          = "CONSOLIDATED_BILLING"
    enabled_policy_types = ["SERVICE_CONTROL_POLICY"]
  }

  expect_failures = [aws_organizations_organization.this]
}

run "rejects_service_access_principals_without_all_features" {
  command = plan

  variables {
    feature_set                   = "CONSOLIDATED_BILLING"
    aws_service_access_principals = ["cloudtrail.amazonaws.com"]
  }

  expect_failures = [aws_organizations_organization.this]
}

run "allows_consolidated_billing_when_nothing_requires_all_features" {
  variables {
    feature_set = "CONSOLIDATED_BILLING"
  }

  assert {
    condition     = aws_organizations_organization.this.feature_set == "CONSOLIDATED_BILLING"
    error_message = "CONSOLIDATED_BILLING must remain usable on its own."
  }
}

run "rejects_invalid_feature_set" {
  command = plan

  variables {
    feature_set = "PARTIAL_BILLING"
  }

  expect_failures = [var.feature_set]
}

# toset() would silently collapse a duplicated name, creating fewer OUs than the
# caller asked for with nothing in the plan to show for it.
run "rejects_duplicate_organizational_units" {
  command = plan

  variables {
    organizational_units = ["workloads", "workloads"]
  }

  expect_failures = [var.organizational_units]
}

run "rejects_empty_organizational_unit_name" {
  command = plan

  variables {
    organizational_units = ["workloads", ""]
  }

  expect_failures = [var.organizational_units]
}

# The length validation is only exercised from below (the empty-string case
# above) elsewhere in this file. Exercise it from above too, since an off-by-one
# in `<= 128` vs `< 128` would otherwise slip through untested.
run "rejects_organizational_unit_name_over_128_characters" {
  command = plan

  variables {
    organizational_units = [join("", [for i in range(129) : "a"])]
  }

  expect_failures = [var.organizational_units]
}

# Both CONSOLIDATED_BILLING preconditions can be violated by the same plan.
# The individual tests above only ever break one at a time; make sure the
# module still fails when both optional arguments are set simultaneously.
run "rejects_policy_types_and_service_access_principals_together" {
  command = plan

  variables {
    feature_set                   = "CONSOLIDATED_BILLING"
    enabled_policy_types          = ["SERVICE_CONTROL_POLICY"]
    aws_service_access_principals = ["cloudtrail.amazonaws.com"]
  }

  expect_failures = [aws_organizations_organization.this]
}

# Every optional argument set together in a single apply. Each argument is
# already covered in isolation elsewhere in this file, but nothing so far
# proves they compose correctly in one plan: OU creation, policy-type
# enablement and service-access all firing from the same root at once.
run "applies_every_optional_argument_together" {
  variables {
    feature_set                   = "ALL"
    enabled_policy_types          = ["SERVICE_CONTROL_POLICY"]
    aws_service_access_principals = ["cloudtrail.amazonaws.com"]
    organizational_units          = ["network", "security", "sandbox"]
    tags                          = { Team = "platform" }
  }

  assert {
    condition     = length(aws_organizations_organizational_unit.this) == 3
    error_message = "All three organizational units must be created alongside the policy and service-access settings."
  }

  assert {
    condition     = contains(aws_organizations_organization.this.enabled_policy_types, "SERVICE_CONTROL_POLICY")
    error_message = "Policy types must still be enabled when organizational units are created in the same apply."
  }

  assert {
    condition = alltrue([
      for ou in aws_organizations_organizational_unit.this : ou.tags["Team"] == "platform"
    ])
    error_message = "Tags must reach every organizational unit even when other optional arguments are also set."
  }
}

# Update-in-place: add one organizational unit and drop another in the same
# apply, building on state from the run above. The resource is keyed by name
# (for_each = toset(...)), so survivors must keep their identity — only
# "security" should be destroyed and only "compliance" created. A regression
# that re-keyed by index or position would recreate everything here instead.
run "adds_and_removes_organizational_units_in_the_same_apply" {
  variables {
    feature_set                   = "ALL"
    enabled_policy_types          = ["SERVICE_CONTROL_POLICY"]
    aws_service_access_principals = ["cloudtrail.amazonaws.com"]
    organizational_units          = ["network", "sandbox", "compliance"]
    tags                          = { Team = "platform" }
  }

  assert {
    condition     = length(aws_organizations_organizational_unit.this) == 3
    error_message = "Adding one unit and removing another in the same apply must still leave three units total."
  }

  assert {
    condition     = contains(keys(aws_organizations_organizational_unit.this), "compliance")
    error_message = "The newly added organizational unit must be present after the update."
  }

  assert {
    condition     = !contains(keys(aws_organizations_organizational_unit.this), "security")
    error_message = "The dropped organizational unit must no longer be present after the update."
  }

  assert {
    condition = (
      contains(keys(aws_organizations_organizational_unit.this), "network") &&
      contains(keys(aws_organizations_organizational_unit.this), "sandbox")
    )
    error_message = "Organizational units untouched by the update must survive it without being recreated."
  }
}

# Shrinking the list back to zero must cleanly destroy every organizational
# unit rather than error or leave anything orphaned in state.
run "removing_all_organizational_units_leaves_none_behind" {
  variables {
    feature_set          = "ALL"
    organizational_units = []
  }

  assert {
    condition     = length(aws_organizations_organizational_unit.this) == 0
    error_message = "Clearing organizational_units must destroy every previously created unit."
  }
}
