# Roadmap

Planned work, split into new **controls** (baseline steps not yet written up) and
**tooling** (improvements to the scripts themselves). Once the repo is public this
may move to GitHub Issues.

## Controls

- [ ] **Region enable/disable.** Restrict the account to the Regions you use and
  disable the rest, shrinking both the attack surface (fewer Regions where a
  compromised credential can spin up resources) and the cost-surprise surface
  (fewer places unexpected spend can appear). CLI: `aws account list-regions`,
  then `aws account disable-region --region-name <REGION>` (or `enable-region`).
  Some Regions are enabled by default and cannot be disabled; disabling is
  reversible but re-enabling can take time. [free]

- [ ] **Regional STS endpoints.** Set the account's Security Token Service to issue
  session tokens from regional endpoints rather than the single global endpoint
  (`aws iam set-security-token-service-preferences --global-endpoint-token-version
  v2Token`, and prefer `sts` regional endpoints in the CLI/SDK config). More
  resilient (no dependency on one global endpoint), and it pairs with the region
  enable/disable control so tokens still resolve when regions are restricted.
  Confirm token compatibility before switching. [free]

- [ ] **Sandbox / separate accounts (advanced, maybe).** For riskier experiments,
  a throwaway account kept separate from your main one, so a mistake or a
  compromise is contained. This means creating an AWS Organization and adding
  member accounts, with the main account's root secured and rarely used. Likely
  beyond a single personal-account baseline, and it shifts the whole model to
  multi-account, but noted for when experimentation warrants isolation. [free]

- [ ] **Scoped daily-driver permissions (toggleable service sets).** Today the
  daily driver gets the broad `PowerUserAccess` managed policy (everything except
  IAM/Organizations). It is a convenient starting point, not least privilege.
  Offer a way to tighten it to only the services a given owner actually uses:
  config toggles (e.g. `ALLOW_REDSHIFT=false`, `ALLOW_SAGEMAKER=false`) that
  compose the daily-driver group's permissions from opt-in per-service or
  per-category grants instead of blanket PowerUser, so someone who will never use,
  say, Redshift, EMR, or SageMaker simply never grants them. Reduces blast radius
  and cost-surprise surface. Options to weigh: start from `PowerUserAccess` and
  attach explicit deny policies for the opted-out services (simple, still broad by
  default), or start from a deny-all base and build up an allow-list of chosen
  services (true least privilege, more to maintain). Keep the current PowerUser
  default; this is an opt-in tightening. [free]

- [ ] **Enforce a safety-net guardrail with an SCP (needs an Organization).** If the
  audit controls are re-added (CloudTrail, GuardDuty, Config, an audit log bucket),
  they want a guardrail that stops them being disabled or deleted. A deny policy on
  the daily driver is only a speed bump on a standalone account: an identity with
  `AdministratorAccess` (and root) can remove its own deny, so it stops accidents,
  not a determined admin. The only control that binds every identity, including the
  admin role, is a Service Control Policy applied via AWS Organizations (only the
  Organization management account's root sits above it). That means creating a
  one-account Organization and attaching an SCP that denies those safety-net-
  disabling actions account-wide. Deferred because it pulls in the whole
  Organizations model for a single personal account, and because it only has
  something to protect once those audit controls exist. Pairs with the
  sandbox/separate-accounts item. [free]

- [ ] **Provision a scoped agent / CLI identity.** When you point an AI agent or a
  CLI/SDK integration (e.g. Kiro) at the account, it should get the tightest scope:
  read-only plus only the specific services its task needs, never the admin role,
  and ideally short-lived credentials (IAM Identity Center / `aws sso login`) rather
  than static keys. The baseline does not yet create such an identity; provisioning
  it (a scoped IAM role, or an Identity Center permission set if you adopt SSO)
  would turn that guidance into a real control. The baseline does not set up
  Identity Center at all today, so this would introduce it. [free]

- [ ] **IAM Access Analyzer (re-add).** Create an account external-access analyzer
  that continuously flags resources (S3 buckets, IAM roles, KMS keys, etc.) shared
  publicly or cross-account. Stashed from the first release because its findings are
  console-only by default (no push notification), so on a quiet personal account
  they go unseen. Re-add it together with an EventBridge to SNS to email rule so
  findings actually reach the owner, reusing the alerts email. [free]

- [ ] **Privacy: AI-services opt-out (re-add).** Attach an Organizations
  `AISERVICES_OPT_OUT_POLICY` so AWS AI services don't store/train on content sent
  to them. Stashed from the first release because it requires creating an AWS
  Organization (the account becomes its management account), which is a consequential
  account-shaping change. Moot until you actually use those services, and Amazon
  Bedrock doesn't train on prompts by default. Re-add when the Organizations model is
  adopted (pairs with the SCP and sandbox items). [free]

- [ ] **Periodic account-review reminder (re-add).** An EventBridge Scheduler job
  that emails a quarterly "review your account" nudge via an SNS topic (verify
  contacts, MFA, budgets are still current). Stashed from the first release to keep
  the baseline lean and because it was the only step pulling in SNS + a scheduler
  role; a plain calendar reminder does the same job with no infrastructure. Re-add
  if an in-account reminder is wanted. [free]

## Tooling

- [ ] **`--format json` summary.** Machine-readable version of the end-of-run
  step-state summary, for piping into the private changelog or CI.
- [ ] **Richer `audit.sh` checks.** Per-row `mfa_active` (root + each IAM user) via
  the credential report, not just the account-summary MFA count; per-bucket
  public-access-block state; password-policy check.
- [ ] **Guided / wizard mode.** An interactive `--wizard` (or `setup.sh`) that
  prompts for the config values (alert email, recovery email, region, budget
  amount, which steps to enable), writes `config.env`, then walks each step with a
  confirm-before-apply prompt and shows the dry-run first. Lowers the barrier for
  someone who doesn't want to hand-edit `config.env` or remember the flags.
- [ ] **Terminal interface (TUI).** A persistent, app-like terminal UI (distinct
  from the linear wizard above): a screen listing each control with its current
  status, keyboard navigation, toggle-and-apply, and live audit results in place.
  Bigger than the wizard and it forces a stack decision: bash with `whiptail`/
  `dialog` keeps the pure-bash footprint but is limited, while a richer TUI (Python
  Textual, Go Bubble Tea) means adding a runtime/dependency the tool doesn't
  currently have. Weigh against staying CLI-first before committing.
- [ ] **GUI.** A desktop or local-web front-end over the same steps: view each
  control's status, toggle and apply, read the audit results. Heavier than the TUI
  and further from the CLI-first design; only worth it if the audience extends
  beyond terminal-comfortable users. Same stack/dependency caveat as the TUI, more
  so.
- [ ] **MCP server.** Expose the baseline's steps and audit as tools an AI agent
  (e.g. Kiro) can call: report posture, dry-run a step, apply a step. Pairs with the
  scoped agent-identity control, since an agent driving this should run under a
  tightly-scoped identity, never the admin role. Keep the dry-run-default and
  confirm-before-apply safety model intact through the tool surface.
- [ ] **Audit / read-only mode across interfaces.** Every front-end (CLI already has
  `--audit` / `audit.sh`, plus the TUI, GUI, and MCP above) should offer a read-only
  audit view that reports posture and changes nothing, distinct from the apply view.
  The CLI has this today; the others should match it so "just show me the state" is
  always safe.
- [ ] **CloudFormation edition (explore).** Offer the resource-creating controls as
  a reviewable CloudFormation template (or a few: `iam.yaml`, `cost.yaml`) as an
  ALTERNATIVE to the CLI scripts, for users who prefer infrastructure-as-code.
  Declarative desired state gives idempotency, drift detection
  (`describe-stack-drift`), and clean teardown for free, which is exactly what a
  baseline wants. Strong candidates: **Budgets** (`AWS::Budgets::Budget`), **Cost
  Anomaly Detection** (`AWS::CE::AnomalyMonitor` + `AnomalySubscription`), and the
  **admin role / admins group / assume policy** (`AWS::IAM::Role`/`Group`/`Policy`).
  Poor or non-candidates stay CLI: account settings with no CFN resource (S3 account
  public-access block, alternate contacts), the daily-driver user (CFN can't set its
  password/MFA and a stack delete would remove the login), the local `~/.aws/config`
  profile write, and the console-only root actions. Tradeoff to weigh: CFN cuts
  against the tool's CLI-first reviewability (a template is harder to eyeball than a
  30-line step, and its change-set dry-run is a different model from `--apply`), and
  mixing paradigms is messy, so this is likely a PARALLEL IaC edition rather than a
  piecemeal swap. A deliberate architecture decision, not a quick win.
