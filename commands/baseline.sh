#!/usr/bin/env bash
# baseline.sh — apply the personal-AWS security/cost baseline via the AWS CLI.
#
# SAFE BY DEFAULT: with no flags this is a DRY RUN — it prints every mutating
# command it would run and changes nothing. Pass --apply to execute.
#
# Usage:
#   ./baseline.sh                 # dry-run; behaviour depends on WHO you are (below)
#   ./baseline.sh --apply         # execute: create missing resources only
#   ./baseline.sh --update        # execute: create missing AND update changed values
#                                 #   on the settings marked updatable in
#                                 #   docs/configuration.md (and the ManagedBy tag).
#                                 #   Never changes a create-only resource's identity
#                                 #   or permissions, and never deletes anything.
#   ./baseline.sh --free-only     # skip any step with ongoing cost
#   ./baseline.sh --only contacts,budgets   # run only listed steps (by name)
#   ./baseline.sh --audit         # read-only posture check (delegates to audit.sh)
#   ./baseline.sh --no-log        # don't write a run log (logging is ON by default)
#   ./baseline.sh --force-root    # as root, run EVERY step (not just the bootstrap)
#   ./baseline.sh --force-identity # run as a non-root user that isn't the daily driver
#   ./baseline.sh --no-color      # disable coloured output (also honours NO_COLOR)
#   ./baseline.sh --color         # force colour even when output is piped/logged
#
# Identity-based routing (when you do NOT pass --only, the tool self-directs):
#   * as ROOT           -> runs the identity bootstrap ONLY: create the
#                          daily-driver user + admin role, then stop. If the daily
#                          driver already exists it says so and stops, asking you to
#                          switch. --force-root overrides to run everything.
#   * as the DAILY DRIVER -> skips the bootstrap and runs the everyday steps.
#   * as another non-root user -> refuses (failsafe: proceed only as the named daily
#                          driver). Override with --force-identity.
# An explicit --only always wins over this routing and stays subject to the root
# guard (root refuses non-bootstrap steps unless --force-root). `audit.sh` only
# warns as root, since reading is harmless.
#
# A timestamped run log is written to commands/logs/ by default (git-ignored),
# capturing the full command trace + the end-of-run step-state summary — paste
# it into your private CHANGELOG. Disable with --no-log.
#
# Scope: automates the safe, idempotent, mostly-free steps. It deliberately does
# NOT automate IAM identity restructuring or AWS Organization creation, which are
# consequential; those are left as documented manual steps.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

APPLY=false
UPDATE=false
FREE_ONLY=false
ONLY=""
ONLY_EXPLICIT=false
DO_AUDIT=false
NO_LOG=false
FORCE_ROOT=false
FORCE_IDENTITY=false

while [ $# -gt 0 ]; do
  case "$1" in
    --apply)     APPLY=true ;;
    --update)    APPLY=true; UPDATE=true ;;
    --free-only) FREE_ONLY=true ;;
    --only)      ONLY="$2"; ONLY_EXPLICIT=true; shift ;;
    --audit)     DO_AUDIT=true ;;
    --no-log)    NO_LOG=true ;;
    --force-root) FORCE_ROOT=true ;;
    --force-identity) FORCE_IDENTITY=true ;;
    --color)     export COLOR_MODE=always ;;
    --no-color)  export COLOR_MODE=never ;;
    -h|--help)   sed -n '2,42p' "$0"; exit 0 ;;
    *)           echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done
export APPLY UPDATE FREE_ONLY FORCE_ROOT FORCE_IDENTITY

# Detect terminal colour capability NOW, on the real stdout, before the logging
# tee turns stdout into a pipe (which would otherwise defeat auto-detection).
# common.sh reads BASELINE_TTY_COLOR for its 'auto' decision. Explicit --color /
# --no-color (COLOR_MODE) and NO_COLOR still override this in common.sh.
if [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ] &&
   { ! command -v tput >/dev/null 2>&1 || [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; }; then
  export BASELINE_TTY_COLOR=1
else
  export BASELINE_TTY_COLOR=0
fi

# Logging on by default (unless --no-log or --audit): tee everything to a
# timestamped file under commands/logs/.
if [ "$NO_LOG" != "true" ] && [ "$DO_AUDIT" != "true" ]; then
  mkdir -p "$HERE/logs"
  _mode="dryrun"; [ "$APPLY" = "true" ] && _mode="apply"
  LOG_FILE="$HERE/logs/run-$(date +%Y%m%d-%H%M%S)-${_mode}.log"
  exec > >(tee "$LOG_FILE") 2>&1
fi

# shellcheck source=lib/common.sh
. "$HERE/lib/common.sh"

if [ "$DO_AUDIT" = "true" ]; then exec "$HERE/audit.sh"; fi

load_config "$HERE/config.env"
resolve_account
resolve_region

# --- Identity-based routing -------------------------------------------------
# The baseline is self-directing based on WHO you are, so you don't have to
# remember the right --only incantation:
#   * root                     -> bootstrap ONLY (create daily-driver +
#                                 admin-role), then stop. (--force-root lets root
#                                 run everything, the escape hatch.)
#   * the named daily driver   -> skip bootstrap, run the everyday steps.
#   * another non-root user    -> refuse (this is a failsafe: proceed only as the
#                                 named daily driver), unless --force-identity.
# An explicit --only always wins and is NOT overridden by this routing; it stays
# subject to the root guard below.
BOOTSTRAP_STEPS="daily-driver,admin-role,contacts"
EVERYDAY_STEPS="s3-public-access-block,budgets,anomaly"
ROOT_BOOTSTRAP=false   # set true when a root run is scoped to bootstrap

_caller_is_daily_driver() {
  [ -n "${DAILY_DRIVER_USER:-}" ] || return 1
  case "${CALLER_ARN:-}" in
    *:user/"$DAILY_DRIVER_USER") return 0 ;;
    *) return 1 ;;
  esac
}

if [ "$ONLY_EXPLICIT" = "true" ]; then
  # Explicit selection: honour it, still root-guarded unless it's bootstrap-only.
  _only_bootstrap() {
    [ -z "$ONLY" ] && return 1
    local IFS=, n
    for n in $ONLY; do
      case "$n" in daily-driver|admin-role|contacts) ;; *) return 1 ;; esac
    done
    return 0
  }
  if _only_bootstrap; then
    is_root && log "root allowed for bootstrap step(s): $ONLY"
  else
    guard_not_root enforce
  fi
elif is_root; then
  if [ "$FORCE_ROOT" = "true" ]; then
    warn "Running as ROOT with --force-root: running ALL steps. Prefer the"
    warn "daily-driver identity; root should be reserved for the bootstrap."
  else
    ONLY="$BOOTSTRAP_STEPS"
    ROOT_BOOTSTRAP=true
    log "root detected: running the identity bootstrap only ($ONLY)."
    log "(pass --force-root to run every step as root, not recommended.)"
  fi
elif _caller_is_daily_driver; then
  ONLY="$EVERYDAY_STEPS"
  log "running as the daily driver '$DAILY_DRIVER_USER': bootstrap skipped, running the everyday steps."
else
  # A non-root identity that is NOT the configured daily driver.
  if [ "$FORCE_IDENTITY" = "true" ]; then
    warn "Caller is not the named daily driver '${DAILY_DRIVER_USER:-<unset>}', but"
    warn "--force-identity is set: proceeding with the everyday steps."
    ONLY="$EVERYDAY_STEPS"
  else
    err "You are not the configured daily driver '${DAILY_DRIVER_USER:-<unset>}'."
    err "Caller: ${CALLER_ARN:-unknown}"
    err "This baseline is meant to run as that named identity. Either:"
    err "  - switch to '$DAILY_DRIVER_USER' (e.g. re-authenticate as that user), or"
    err "  - set DAILY_DRIVER_USER in config.env to match your identity, or"
    err "  - re-run with --force-identity to proceed anyway."
    exit 1
  fi
fi

if [ "$APPLY" != "true" ]; then
  warn "DRY RUN — no changes will be made. Re-run with --apply (create only) or"
  warn "--update (also update changed values) to execute."
  warn "The 'would run (preview)' lines show the arguments each step would pass to"
  warn "aws, with shell quoting already parsed away, so they are a preview and not"
  warn "meant for copy-paste."
elif [ "$UPDATE" = "true" ]; then
  log "UPDATE mode: creating missing resources and updating changed values on the"
  log "settings that support it. A create-only resource's identity and permissions are not modified."
else
  log "APPLY mode: creating missing resources only. Existing values are left as-is;"
  log "use --update to change them."
fi

_selected() { [ -z "$ONLY" ] && return 0; case ",$ONLY," in *",$1,"*) return 0;; *) return 1;; esac; }

# Steps grouped by concern. Execution order is defined here, not by filename.
# --only matches on the bare step name (e.g. --only contacts,budgets).
# Each step is isolated: if it fails (e.g. an AccessDenied on one action), it is
# recorded as failed and the run continues to the next step, rather than aborting
# the whole baseline. errexit is relaxed only around the source, then restored.
_run_step() {
  local file="$1" name="$2"
  # shellcheck disable=SC1090
  . "$HERE/lib/steps/$file.sh"
}

# Look up a step's recorded outcome (Bash 3.2 safe: linear scan). Defined here so
# the step loop can check whether a failing step already recorded its own outcome.
_outcome_of() {
  local target="$1" i
  for i in "${!_REC_NAME[@]}"; do
    if [ "${_REC_NAME[$i]}" = "$target" ]; then printf '%s' "${_REC_OUTCOME[$i]}"; return 0; fi
  done
  return 1
}

for s in \
  security/daily-driver \
  security/admin-role \
  security/contacts \
  security/s3-public-access-block \
  cost/budgets \
  cost/anomaly; do
  name="${s##*/}"
  _selected "$name" || continue
  set +e
  _run_step "$s" "$name"
  _step_rc=$?
  set -e
  if [ "$_step_rc" -ne 0 ]; then
    # The step aborted mid-way. If it didn't record its own outcome, record failed
    # so the summary reflects it, then continue to the next step.
    if ! _outcome_of "$name" >/dev/null 2>&1; then
      record "$name" failed "step exited with status $_step_rc (see output above)"
    fi
    err "step '$name' failed (status $_step_rc); continuing with the remaining steps."
  fi
done

print_summary

# Look up a step's recorded outcome (Bash 3.2 safe: linear scan).
# Root bootstrap run: if the daily driver already existed, don't leave the user on
# root. State it and stop with switch guidance (non-zero exit), unless --force-root.
if [ "$ROOT_BOOTSTRAP" = "true" ]; then
  dd_outcome="$(_outcome_of daily-driver || true)"
  if [ "$dd_outcome" = "already-present" ]; then
    printf '\n'
    warn "The daily driver '${DAILY_DRIVER_USER}' already exists, so the bootstrap is done"
    warn "(any missing admin role was created above). Do NOT keep running as root."
    warn "Switch to the daily driver, then re-run the baseline as that identity:"
    warn "  aws logout"
    warn "  aws login            # sign in as '${DAILY_DRIVER_USER}'"
    warn "  ./baseline.sh        # now runs the everyday steps automatically"
    exit 3
  fi
fi

printf '\n'
if [ "$APPLY" = "true" ]; then
  ok "Baseline apply complete. Log each change in your private CHANGELOG."
else
  ok "Dry run complete. Review the commands above, then re-run with --apply."
fi
[ -n "${LOG_FILE:-}" ] && ok "Run log written to ${LOG_FILE#"$HERE"/}"
exit 0
