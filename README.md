# terraform-aws-organizations

Terraform module that manages an [AWS
Organizations](https://aws.amazon.com/organizations/) organization. It creates
the organization for the calling management account and provisions a flat list
of organizational units directly under the root.

## Usage

```hcl
module "organizations" {
  source = "github.com/moveeeax/terraform-aws-organizations"

  feature_set          = "ALL"
  organizational_units = ["workloads", "sandbox"]

  tags = {
    ManagedBy = "terraform"
  }
}
```

A runnable example lives in [`examples/basic`](examples/basic).

## Feature set matters

`feature_set` defaults to `ALL`, and it should stay that way for almost every
organization. With `CONSOLIDATED_BILLING`:

- **no organization policy type can be enabled** — service control policies, tag
  policies, backup policies and resource control policies are all unavailable, so
  `enabled_policy_types` cannot be used at all;
- **trusted access for AWS services is unavailable**, so
  `aws_service_access_principals` cannot be used either.

AWS reports both of these as an opaque `ConstraintViolationException` at apply
time. This module instead fails at **plan** time with an explanation, so the
combination cannot reach an apply. Moving from `CONSOLIDATED_BILLING` to `ALL`
later requires every member account to accept the change, so pick `ALL` up front
unless you are certain you only ever want billing consolidation.

## Destroying an organization

`terraform destroy` on this module calls `DeleteOrganization`. That is
irreversible — the organization ID is never reissued — and it removes every
organizational unit and policy underneath it. AWS refuses the call while member
accounts remain, but a management-account-only organization *will* be deleted
without further confirmation.

`prevent_destroy` cannot be driven by a variable and Terraform cannot attach
`lifecycle` rules to a module's resources from the outside, so this module does
not hardcode it. For a production organization, keep this module in a dedicated
state where `terraform destroy` is never run, and require a plan review before
any change that shows `aws_organizations_organization.this` being replaced or
destroyed.

## Requirements

| Name      | Version  |
|-----------|----------|
| terraform | >= 1.5   |
| aws       | >= 5.0   |

## Inputs

| Name                            | Description                                             | Type           | Default   | Required |
|---------------------------------|---------------------------------------------------------|----------------|-----------|:--------:|
| `feature_set`                   | Feature set. ALL or CONSOLIDATED_BILLING.               | `string`       | `"ALL"`   |    no    |
| `aws_service_access_principals` | Service principals granted org-wide access. Requires `feature_set = "ALL"`. | `list(string)` | `[]`      |    no    |
| `enabled_policy_types`          | Organization policy types to enable in the root. Requires `feature_set = "ALL"`. | `list(string)` | `[]`      |    no    |
| `organizational_units`          | Organizational unit names to create under the root. Must be unique. | `list(string)` | `[]`      |    no    |
| `tags`                          | Tags applied to the organizational units.               | `map(string)`  | `{}`      |    no    |

## Outputs

| Name                      | Description                                        |
|---------------------------|----------------------------------------------------|
| `id`                      | ID of the organization.                            |
| `arn`                     | ARN of the organization.                           |
| `master_account_id`       | Account ID of the management account.              |
| `root_id`                 | ID of the organization root.                       |
| `organizational_unit_ids` | Map of organizational unit names to their IDs.     |

## Tests

The module ships a `terraform test` suite that runs against a mocked AWS
provider — no credentials and no network access required:

```sh
terraform init -backend=false
terraform test
```

`mock_provider` needs Terraform >= 1.7. That is a test-only requirement; the
module itself still supports >= 1.5.

## License

[MIT](LICENSE)
