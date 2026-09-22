# Steering

These files are project standards for anyone (human or agent) working on this
repository. A Kiro agent loads every `*.md` here automatically as context, so the
rules apply without being pasted into each session. They restate, in machine-facing
form, the conventions written for humans in [`CONTRIBUTING.md`](../../CONTRIBUTING.md);
CONTRIBUTING is the source of truth, these are the enforceable summary.

- `shell.md` — how the step scripts are written (the `run_aws`/`read_aws` split,
  config guards, the `record` call, Bash 3.2 target).
- `safety.md` — the safety model: dry-run default, `--apply` vs `--update`,
  never delete, no secrets.
- `docs.md` — documentation standards (step-doc structure, clear-English rule).

A file named `*.local.md` here is git-ignored: use it for personal steering you do
not want to publish.
