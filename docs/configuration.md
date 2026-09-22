# Configuration reference

Every setting in `config.env` (copied from `config.env.example`). "Required" means
the scripts refuse to run without it when the step that uses it runs; "no" settings
have a working default. "Updatable" means re-running with `--update` changes an
existing resource to match a new value (plain `--apply` only creates what's missing
and leaves existing values alone). Defaults shown are the template values.

## Notifications

| Variable | Default | Required | Updatable | Used for |
|---|---|---|---|---|
| `ALERT_EMAIL` | (empty) | Yes | No | Email that receives budget and anomaly alerts, and the alternate-contact address if `RECOVERY_EMAIL` is unset. |
| `RECOVERY_EMAIL` | (empty) | Recommended | No | Independent recovery mailbox for the alternate contacts. Use a different provider from your primary so one lockout can't take out both. If unset, contacts fall back to `ALERT_EMAIL` with a no-redundancy warning. |

## [Daily-driver IAM user](steps/security/daily-driver.md)

| Variable | Default | Required | Updatable | Used for |
|---|---|---|---|---|
| `CREATE_DAILY_DRIVER` | `true` | No | No | `true` creates the scoped everyday user if absent. `false` means you already have one and the step only verifies it exists. |
| `DAILY_DRIVER_USER` | (empty) | Yes | No | The IAM user name for everyday work, and the user added to the admins group. |
| `DAILY_DRIVER_GROUP` | `daily-drivers` | No | No | Group that holds the daily driver's scoped policies (PowerUser + billing read). |

## [Admin role](steps/security/admin-role.md)

| Variable | Default | Required | Updatable | Used for |
|---|---|---|---|---|
| `CREATE_ADMIN_ROLE` | `true` | No | No | `true` creates the MFA-required assumable admin role. `false` skips the step. |
| `ADMIN_ROLE` | `admin-role` | Yes (when enabled) | No | Name of the `AdministratorAccess` role the daily driver assumes for rare IAM/Org tasks. |
| `ADMIN_GROUP` | `admins` | Yes (when enabled) | No | Group that holds the `sts:AssumeRole` grant; the daily driver joins it. Membership is what allows elevation. |
| `WRITE_ADMIN_PROFILE` | `true` | No | No | Write a named profile to `~/.aws/config` so `aws --profile <name>` auto-assumes the role. Skips if the profile exists; self-heals the MFA serial on re-run. |
| `ADMIN_PROFILE_NAME` | `admin` | No | No | Name of the written CLI profile. |
| `ADMIN_MAX_SESSION_DURATION` | `3600` | No | No | Role session ceiling in seconds (AWS range 3600 to 43200). Applied at role creation. |
| `ADMIN_SESSION_DURATION` | `1800` | No | No | Seconds each assumed session lasts, requested by the profile (900 to the cap). Effective length is `min(this, cap)`. |

## [Alternate contacts](steps/security/contacts.md)

| Variable | Default | Required | Updatable | Used for |
|---|---|---|---|---|
| `ENABLE_CONTACTS` | `true` | No | No | Whether to set the alternate contacts. |
| `CONTACT_NAME` | (empty) | Yes (when enabled) | No | Name recorded on the Security and Billing alternate contacts. |
| `CONTACT_PHONE` | (empty) | Yes (when enabled) | No | Phone recorded on the alternate contacts. |
| `CONTACT_TITLE` | `Owner` | No | No | Title recorded on the alternate contacts. |

## [S3 account public-access block](steps/security/s3-public-access-block.md)

| Variable | Default | Required | Updatable | Used for |
|---|---|---|---|---|
| `ENABLE_S3_BLOCK` | `true` | No | No | Whether to turn on the account-level S3 public-access block. |

## [Budgets](steps/cost/budgets.md)

| Variable | Default | Required | Updatable | Used for |
|---|---|---|---|---|
| `ENABLE_BUDGETS` | `true` | No | No | Whether to create the monthly cost budget (and update it under `--update`). |
| `MONTHLY_BUDGET_AMOUNT` | `10` | Yes (when enabled) | Yes | Monthly cost limit in USD. Editing it and re-running with `--update` changes the existing budget (plain `--apply` leaves it as-is). |

## [Cost Anomaly Detection](steps/cost/anomaly.md)

| Variable | Default | Required | Updatable | Used for |
|---|---|---|---|---|
| `ENABLE_ANOMALY` | `true` | No | No | Whether to create the anomaly monitor and subscription (and update the subscription under `--update`). |
| `ANOMALY_MONITOR_NAME` | `account-services-monitor` | No | No | Name of the service-dimension anomaly monitor. |
| `ANOMALY_SUBSCRIPTION_NAME` | `account-anomaly-alerts` | No | No | Name of the email subscription tied to the monitor. |
| `ANOMALY_THRESHOLD` | `10` | No | Yes | Alert when an anomaly's total impact (USD) meets or exceeds this. Editing it and re-running with `--update` changes the existing subscription (plain `--apply` leaves it as-is). |

## Regions

| Variable | Default | Required | Updatable | Used for |
|---|---|---|---|---|
| `PREFERRED_REGION` | `us-east-1` | No | No | Default region for API calls when the AWS CLI config has none set. Billing/global APIs always use `us-east-1` regardless. |
| `REGIONS` | (empty) | No | No | Space-separated regions any region-scoped step acts on. Defaults to `PREFERRED_REGION` if empty. |

## Resource tags

A single provenance tag, `ManagedBy=<value>`, applied to taggable resources (the
daily-driver user, the admin role, the budget, and the anomaly monitor and
subscription). Tags are the one benign exception to the never-modify-a-create-only
resource rule: they are metadata, not identity or permissions, so they are
reconciled diff-first under `--update` (read the live `ManagedBy` value, write only
if it is missing or differs). Under plain `--apply` a tag difference is reported,
not changed. The S3 public-access block and the alternate contacts are account-level
settings, not taggable resources. The tag key is fixed at `ManagedBy`; only its
value is configurable.

| Variable | Default | Required | Updatable | Used for |
|---|---|---|---|---|
| `RESOURCE_TAGS` | `true` | No | Yes | Whether to tag resources with `ManagedBy`. Set `false` to create untagged; existing tags are left in place. |
| `MANAGED_BY_TAG` | `personal-aws-account-baseline` | No | Yes | The value of the `ManagedBy` tag. Changing it and re-running with `--update` reconciles the tag on existing resources. The key is fixed. |
