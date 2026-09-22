# Shell and step-script standards

Applies to every script under `commands/` (`baseline.sh`, `audit.sh`, and
`commands/lib/steps/<concern>/<step>.sh`).

- **Target Bash 3.2** (the macOS default). No associative arrays, no `mapfile`, no
  `${var^^}`. Use parallel indexed arrays where you would reach for an associative
  one.
- **`set -euo pipefail`** at the top of every entrypoint.
- **State changes go through `run_aws`**, never a bare `aws`. `run_aws` prints the
  command in dry-run and executes it under `--apply`. Read-only calls
  (`describe`/`list`/`get`) go through `read_aws`, which always runs so state checks
  work in both modes.
- **Every step starts with a config guard**:
  `[ "${ENABLE_X:-false}" = "true" ] || { record <step> disabled-in-config; return 0; }`
- **Call `record <step> <outcome> [detail]`** at each exit so the end-of-run summary
  is accurate. Outcomes: `applied`, `already-present`, `would-apply`, `partial`,
  `skipped`, `disabled-in-config`, `failed`.
- **Check that a mutating `run_aws` actually succeeded before recording `applied`.**
  Do not record success unconditionally after a `run_aws` call: capture the result
  (`if run_aws ...; then`, or `run_aws ... && ok=true || ok=false`) and record
  `failed` / `partial` when it did not. A denied or errored call must never show as
  `applied` in the summary. Also guard cascades: do not attempt a dependent call
  (e.g. a subscription) when a prior resource's ARN is unresolved or `None`.
- **Read live state before comparing.** Drift and update logic reads the live value
  first via the shared `drift_state_*` / `read_aws` helpers, then compares, then acts
  only on a real difference.
- **Run `bash -n` on every script you touch** before opening a pull request; all
  scripts must pass.
