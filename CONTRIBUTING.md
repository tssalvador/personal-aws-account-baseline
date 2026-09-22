# Contributing

Thanks for your interest in improving this baseline. It aims to provide a set of
scripts an individual can read, understand and run agains their own AWS account,
and as such, should be CLI-first, with any neecssary exceptions clearly documented.


## Principles

- **CLI-first, and reviewable.** Every action is a plain `aws` CLI command in a
  small shell step you can read top to bottom. Prefer that over abstractions,
  frameworks, or generated code.
- **Safe by default.** `baseline.sh` is a dry run unless `--apply` is passed. Every
  new step must honour this: use `run_aws` (which prints in dry-run and executes
  under `--apply`) for anything that changes state, and `read_aws` for read-only
  checks that must run in both modes.
- **Report honestly.** Check that a mutating `run_aws` actually succeeded before you
  `record` the step as `applied`. Capture the result (`if run_aws ...; then`, or
  `run_aws ... && ok=true || ok=false`) and record `failed` or `partial` when it did
  not, so a denied or errored call never shows as `applied` in the summary. Guard
  cascades too: do not attempt a dependent call (e.g. a subscription) when a prior
  resource's ARN is unresolved or `None`.
- **Idempotent and safe to re-run.** A step must check current state first. On
  `--apply` it creates only what is missing and leaves existing values untouched; on
  `--update` it may bring an *updatable* setting into line with config (diff-first,
  updating only when the live value differs). It must never delete, and never modify
  a create-only resource's identity or permissions (users, roles) — the `ManagedBy`
  tag is the one benign exception (metadata, reconciled diff-first under `--update`).
  Re-running must always be safe.
- **No surprises.** No destructive actions (the scripts only create, enable, or, on
  opt-in `--update`, bring an updatable value into line with config), the only
  network calls are the `aws` commands you can see in each step, no handling of
  secrets (passwords and MFA enrolment are left to the user), and no writing outside
  the account except the documented, opt-in `~/.aws/config` profile.
- **Honest scope.** Document only what the tool actually does. If a control is not
  implemented, it belongs in `docs/ROADMAP.md`, not described as if it ships.

## Repository layout

```
README.md                       front page: intro, quick start, what it does
CHANGELOG.md                    release notes (Keep a Changelog + semver)
CONTRIBUTING.md                 how to add/change a step, conventions
LICENSE                         MIT
commands/
  baseline.sh                   entrypoint (dry-run default; identity routing)
  audit.sh                      read-only drift audit (live state vs config)
  config.env.example            tracked template (config.env is git-ignored)
  lib/common.sh                 shared helpers (run_aws/read_aws, record, drift, colours, guards)
  lib/steps/<concern>/<step>.sh one script per step, grouped security/cost
docs/
  ROADMAP.md                    planned steps and tooling
  configuration.md              every config setting (defaults, required, updatable)
  steps/<concern>/<step>.md     one doc per step (Why / What / Verify)
  *.md                          topic guides (identity model, manual console steps)
```

## Adding or changing a step

Each step is a paired **script + doc + config**:

1. **Script** at `commands/lib/steps/<concern>/<name>.sh`. Start with a config
   guard (`[ "${ENABLE_X:-false}" = "true" ] || { ...; return 0; }`), do read-only
   checks with `read_aws`, make changes with `run_aws`, and call `record` at each
   outcome so the end-of-run summary is accurate.
2. **Doc** at `docs/steps/<concern>/<name>.md` with `## Why`, `## What the script
   does`, and `## Verify` sections. Keep it factual and brief.
3. **Config** keys added to `config.env.example` (tracked) with a short comment.
   Do not commit `config.env` (it holds real values and is git-ignored).
4. **Wire it in** to `baseline.sh`: add the step to the ordered step list and, if it
   is an everyday step, to the identity routing list.

## Documentation and notes

Documentation and notes are for people. Write in clear English and keep it tight,
concise, and factual, not long-winded "AI prose". It is fine to use AI to tighten or
adjust text for grammar or tone, but do not dump raw AI output. If you use AI to
draft something, the expectation is that you have read it and rewritten it as needed
so it stays clear and to the point.

A few practical conventions:

- Document a console step only when the action genuinely has no CLI (root MFA, the
  IAM billing-access toggle) or when it handles a secret the baseline deliberately
  won't touch (a console password, MFA enrolment). Anything else scriptable is
  documented as its CLI command.
- Keep step docs to `## Why`, `## What the script does`, and `## Verify`, factual and
  brief.
- Write links as `[text](url)`.

## Before you open a pull request

- Run `bash -n` on every script you touched (all scripts must pass).
- Run `./baseline.sh` (dry run) and, where you can, `./baseline.sh --apply` against a
  test account, and confirm the step is idempotent by running it twice.
- Keep changes atomic: one control or one concern per pull request.
- Do not include real account data (account ids, emails, bucket names) in tracked
  files. Run a quick scan before pushing.

## Reporting issues

Open an issue describing the AWS behaviour, what you expected, what happened, and
the step involved. For anything security-sensitive, avoid pasting real account
identifiers or credentials.

## License

By contributing you agree that your contributions are licensed under the repository's
[MIT License](LICENSE).
