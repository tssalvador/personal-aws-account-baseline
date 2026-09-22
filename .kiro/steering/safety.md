# Safety model

These are hard rules for the baseline. A change that breaks one is wrong regardless
of what it enables.

- **Dry-run by default.** With no flags, `baseline.sh` prints the `aws` commands it
  would run and changes nothing. A new step must honour this via `run_aws`.
- **`--apply` creates, `--update` reconciles.** `--apply` creates only what is
  missing and leaves existing values untouched. `--update` may bring an *updatable*
  setting into line with config, diff-first (update only when the live value
  differs). Updatable settings are marked in `docs/configuration.md`.
- **Never delete, never disable.** The baseline only creates, enables, or (on
  `--update`) updates to match config. Turning a step off in `config.env` stops the
  baseline managing it; it does not tear down what already exists.
- **Never modify a create-only resource's identity or permissions** (IAM users,
  roles) — those are created once and never changed by a re-run. The `ManagedBy`
  tag is the one benign exception: it is metadata, not identity or permissions, so
  it may be reconciled under `--update` (diff-first, write only when it differs).
- **No secrets.** The scripts never set passwords or enrol MFA; those are documented
  as console steps for the user to do.
- **Only network calls are the visible `aws` commands.** No telemetry, no fetching
  and running remote scripts, no hidden endpoints.
- **The only write outside AWS** is the documented, opt-in `~/.aws/config` profile.
