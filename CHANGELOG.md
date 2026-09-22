# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/): new controls bump the minor version,
fixes and doc changes bump the patch version, and a breaking config change bumps the
major version.

This is the public changelog for the tool. It is separate from any private record of
what you have applied to your own account.

## [1.0.0] - 2026-09-22

Initial release. A small, CLI-first baseline an individual can read and run against
their own AWS account, covering security and cost monitoring.

### Added

- `baseline.sh` entrypoint: dry-run by default, `--apply` to execute, with
  identity-based routing (as root it runs only the identity bootstrap; as the daily
  driver it runs the everyday steps) and a root guard.
- `--apply` vs `--update`: `--apply` creates only what is missing and leaves existing
  values untouched; `--update` also reconciles the settings marked updatable in
  `docs/configuration.md`, diff-first (updating only when the live value differs).
  Neither deletes anything or changes a create-only resource's identity/permissions.
- `audit.sh`: read-only drift audit that compares live AWS state against your config
  and reports each item as in-sync, out-of-sync, or not-readable (no access).
- Security steps:
  - **Daily-driver IAM user** with a `daily-drivers` group (`PowerUserAccess` +
    `AWSBillingReadOnlyAccess`), created during the root bootstrap.
  - **Admin role**: an assumable `AdministratorAccess` role whose trust requires
    MFA, with the assume grant held by a dedicated `admins` group the daily driver
    joins; configurable session duration; optionally writes and self-heals a named
    `~/.aws/config` profile.
  - **Alternate contacts** (security and billing) pointed at an independent recovery
    mailbox.
  - **S3 account public-access block**.
- Cost steps:
  - **Monthly cost budget** with an email alert, whose amount is updated to match
    your config when you re-run with `--update`.
  - **Cost Anomaly Detection** monitor and email subscription, whose threshold is
    updated to match your config when you re-run with `--update`.
- Resource tagging: taggable resources (daily-driver user, admin role, budget,
  anomaly monitor and subscription) are tagged `ManagedBy` so baseline-managed
  resources are identifiable; the tag value is configurable and reconciled under
  `--update`. Turn it off with `RESOURCE_TAGS=false`.
- Docs: per-step docs under `docs/steps/`, `docs/configuration.md` (the source of
  truth for every setting: default, required, updatable), `docs/iam-scoping.md`,
  `docs/manual-steps.md`, `docs/ROADMAP.md`, `README.md`, and `CONTRIBUTING.md`.

### Notes

- Config lives in `config.env` (git-ignored); `config.env.example` is the template.
- Console-only actions the baseline does not automate: root user MFA and the IAM
  billing-access toggle, plus setting the daily driver's console password and MFA.
- On the roadmap (not in this release): CloudTrail, GuardDuty, IAM Access Analyzer,
  the AI-services opt-out, and the periodic account-review reminder.

[1.0.0]: https://github.com/tssalvador/personal-aws-account-baseline/releases/tag/v1.0.0
