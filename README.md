# A Baseline for Personal AWS Accounts

Amazon Web Services (AWS) is an excellent, wide-ranging platform, with features
and services that cater to everything from small hobbyist projects to full-blown
global enterprises. Perhaps because of the sheer scale of the enterprises running
on AWS, and the "building blocks" nature of many of its services, there's little
focus on guidance for **individuals** looking to confidently use AWS for personal
projects.

This provides that guidance as a set of small, CLI-first scripts you can review
and run, backed by a short explanation for each. It covers **security** and **cost
monitoring**. It does not factor in the
[AWS Free Tier](https://aws.amazon.com/free/), and comes with no warranties or
guarantees, so treat it as a starting point and adapt it to your needs.

One of the first actions this baseline implements is setting up a "[daily-driver](docs/steps/security/daily-driver.md)" user, letting you operate your account day to day while reserving the root user for the few tasks that genuinely require it, as per [AWS recommendations](https://docs.aws.amazon.com/IAM/latest/UserGuide/root-user-best-practices.html).

> **No real account data.** The scripts read your account id at runtime and take
> your values from a local `config.env` (git-ignored). Nothing in this repo
> contains a real account id, email, or bucket name.


### Out of scope

This guide sets up **MFA on your AWS account** (Quick start step 1). What it does
*not* cover is the broader personal-credential best practices, which matter far
beyond AWS: use of **password managers** with long, random, unique passwords (or
passphrases), use of **second-factor authentication**, and keeping it **off-band**
(a hardware key or authenticator app, with backup codes stored separately from the
password and/or password manager). If any of that is unfamiliar, good starting
points are:

- **OWASP** — vendor-neutral international reference:
  [Authentication Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html).
- **ACSC (cyber.gov.au)** — Australia's national cyber-security authority,
  plain-language guidance for individuals:
  [Passphrases](https://www.cyber.gov.au/protect-yourself/securing-your-accounts/passphrases)
  and [Multi-factor authentication](https://www.cyber.gov.au/protect-yourself/securing-your-accounts/multi-factor-authentication).
- **EFF Surveillance Self-Defense** — non-government, privacy-focused guidance:
  [Creating Strong Passwords](https://ssd.eff.org/ps/module/creating-strong-passwords).


## Who this is for

- Individuals with a new or existing AWS account, comfortable running CLI commands,
who want to use AWS for personal projects with a good security baseline, timely
notifications, cost tracking, and no surprise data sharing, without "enterprise
overhead".


## Requirements

- **AWS CLI v2**, installed and configured
  ([install](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html),
  [configure](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-quickstart.html)).
- **Bash 3.2+** (the macOS default works).
- **AWS root credentials.** A few actions require the root user, such as adding
  root MFA and letting IAM users access billing data. Limiting root usage and
  creating a scoped daily-driver user are the first steps of this baseline; see
  [docs/iam-scoping.md](docs/iam-scoping.md).


## Quick start

Work through these in order. Step 1 is one-time console actions; steps 2 to 6 set
up a scoped daily-driver identity (plus an admin role it can assume) and switch
to it; step 7 is the scripted baseline you run and re-run as that daily driver.


### 1. Root-only console actions

A couple of important actions have no CLI and must be done in the console, signed
in as root. Full detail in [docs/manual-steps.md](docs/manual-steps.md):

- **Root user MFA** — assign an MFA device to the root user.
- **IAM billing-access toggle** — Activate *IAM user and role access to billing
  information*, so your daily-driver IAM user can see costs without using root.


### 2. Configure

Clone the repo and create your config from the template:

```
git clone https://github.com/tssalvador/personal-aws-account-baseline.git
cd personal-aws-account-baseline/commands
cp config.env.example config.env
```

Then edit `config.env`. Fill out the **required settings** (the script won't run
without them), and review the rest (budget amount, region, admin session duration,
which steps are enabled) against their defaults, changing what doesn't fit. Every
setting is documented in [docs/configuration.md](docs/configuration.md).

> The daily-driver step is the first one and runs by default: it creates a scoped
> user for everyday work. If you already have one, set `CREATE_DAILY_DRIVER=false`
> and name it in `DAILY_DRIVER_USER`; the baseline then verifies that IAM user
> exists instead of creating one.


### 3. Create the daily driver and admin role (root CLI session)

Signed in as root, the baseline limits itself to the bootstrap: creating the
daily-driver user and admin role, and setting the alternate contacts (which need
account-management permissions the daily driver does not have). The role only
becomes assumable once the daily driver's MFA is enrolled (step 4), since assuming
it requires an MFA token.

```
aws login
./baseline.sh --apply
```

### 4. Finish the daily driver in the console (root console session)

The script deliberately doesn't handle secrets, so as root in the console: set the
new user a **console password** and **enrol its MFA**. See
[daily-driver.md](docs/steps/security/daily-driver.md).

### 5. Finish the admin role CLI profile (final root CLI session)

At bootstrap the admin role's `~/.aws/config` profile was written with a placeholder
`mfa_serial` (the daily driver had no MFA yet). Now that you've enrolled it, re-run
the admin-role step once to fill in the real device:

```
./baseline.sh --only admin-role --apply
aws logout
```

The role already exists so it isn't recreated; this only updates the profile's MFA
serial. Skip this if you set `WRITE_ADMIN_PROFILE=false`. The `aws logout` ends the
root session before you switch to the daily driver.

### 6. Switch to the daily driver

Sign in as the daily-driver user:

```
aws login
```

### 7. Run the rest of the baseline (as the daily driver)

Now signed in as the daily driver, the baseline detects your identity, skips the
bootstrap, and runs the everyday steps automatically. No flags needed to select
them:

```
./audit.sh
./baseline.sh
./baseline.sh --apply
```

- `./audit.sh` — read-only, reports current posture and changes nothing.
- `./baseline.sh` — dry run by default, prints the `aws` commands it would run.
- `./baseline.sh --apply` — executes, after you've reviewed the dry run.

Useful flags:

- `--apply` — execute: create missing resources only (default is dry-run). Existing
  values are left as-is.
- `--update` — execute: create missing AND update changed values on the settings
  marked updatable in [docs/configuration.md](docs/configuration.md). Never changes a
  create-only resource's identity or permissions (users, roles), and never deletes
  anything; the only thing reconciled on those is the `ManagedBy` tag.
- `--only <steps>` — run just the named step(s), overriding identity routing. Takes
  one name or a comma-separated list, e.g. `--only budgets` or `--only contacts,budgets`.
- `--audit` — same as `audit.sh`: report what's currently set for each step
  (trail present? S3 block on? budget set? contacts filled?) and change nothing.
- `--no-log` — don't write a run log (logging is on by default, to `commands/logs/`).
- `--force-root` — as root, run every step instead of just the bootstrap.
- `--force-identity` — proceed as a non-root user that isn't the named daily driver.

## Safety model

- **Dry-run by default.** With no flags, `baseline.sh` prints every `aws` command
  it would run and changes nothing. `--apply` creates missing resources; `--update`
  also updates changed values on the steps that support it.
- **Safe to re-run.** Each step checks current state first. Identity steps
  (daily-driver, admin role) never touch a user or role that already exists. `--apply`
  only creates what's missing and leaves existing values alone; to change an existing
  value you use `--update`, which reads the live value and updates only if it differs.
- **No destructive actions.** The baseline itself only creates, enables, or updates
  to match your config; it never deletes or disables anything. (Turning a step off in
  `config.env` stops the baseline managing it; it does not tear down what was already
  created.)
- **Review the dry run, then apply.** Especially for any step with ongoing cost.

## What it does

Each step is a small script under `commands/lib/steps/`, with a short doc under
`docs/steps/` explaining the why, the exact commands, and how to verify. Execution
order is defined in `baseline.sh`, not by filenames.

| Area | Step | Run as | Doc | Cost |
|---|---|---|---|---|
| security | Daily-driver IAM user (runs first, on by default) | root (bootstrap) | [daily-driver.md](docs/steps/security/daily-driver.md) | free |
| security | Admin role (assumable with MFA; on by default) | root (bootstrap) | [admin-role.md](docs/steps/security/admin-role.md) | free |
| security | Contacts, notifications & recovery independence | root (bootstrap) | [contacts.md](docs/steps/security/contacts.md) | free |
| security | S3 account public-access block | daily driver | [s3-public-access-block.md](docs/steps/security/s3-public-access-block.md) | free |
| cost | Budgets | daily driver | [budgets.md](docs/steps/cost/budgets.md) | free |
| cost | Cost Anomaly Detection | daily driver | [anomaly.md](docs/steps/cost/anomaly.md) | free |

Two related things aren't scripted steps:

- **IAM permission scoping** is guidance on the identity model, not an automated
  step. See [docs/iam-scoping.md](docs/iam-scoping.md).
- **Root user MFA** and the **IAM billing-access toggle** are console-only, done as
  root before the scripted steps. See [docs/manual-steps.md](docs/manual-steps.md).

Using a scoped daily driver alongside a rarely-used admin role that it assumes on
demand with MFA, plus tight scoping for AI agents, is covered in
[docs/iam-scoping.md](docs/iam-scoping.md).

## Manual steps (not automated)

A few actions aren't scripted:

- **Root user MFA** and the **IAM billing-access toggle** genuinely have no CLI and
  must be done in the console as root (Quick start step 1). Full detail in
  [docs/manual-steps.md](docs/manual-steps.md).
- **Daily-driver console password and MFA enrolment** (step 4): the baseline doesn't
  handle secrets, so you set these in the console. See
  [daily-driver.md](docs/steps/security/daily-driver.md).

## Roadmap

Planned controls and tooling improvements are tracked in
[docs/ROADMAP.md](docs/ROADMAP.md).

## License

MIT — see [LICENSE](LICENSE). SPDX-License-Identifier: MIT.