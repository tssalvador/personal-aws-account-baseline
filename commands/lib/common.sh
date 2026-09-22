#!/usr/bin/env bash
# Shared helpers for the baseline scripts. Sourced, not executed.

set -euo pipefail

# --- Modes (set by the entrypoint) ---
APPLY="${APPLY:-false}"       # false = dry-run (default). true = execute.
FREE_ONLY="${FREE_ONLY:-false}"

# --- Colours -----------------------------------------------------------------
# Precedence (highest first):
#   1. COLOR_MODE=never  (set by --no-color) or NO_COLOR env set  -> OFF
#   2. COLOR_MODE=always (set by --color) or FORCE_COLOR/CLICOLOR_FORCE -> ON
#   3. Auto: on only for a real, colour-capable terminal.
# The entrypoint detects terminal capability BEFORE it redirects stdout through a
# tee (for logging) and exports the result as BASELINE_TTY_COLOR, so colour is not
# lost just because output is being logged. When common.sh is sourced without that
# (e.g. audit.sh run directly), auto falls back to a live check of stdout.
# Customise the palette by exporting COLOR_INFO / COLOR_OK / COLOR_WARN / COLOR_ERR
# as raw ANSI SGR codes (e.g. COLOR_OK="1;32").
_term_is_color_capable() {
  [ -t 1 ] || return 1
  [ "${TERM:-dumb}" != "dumb" ] || return 1
  command -v tput >/dev/null 2>&1 || return 0   # no tput: assume ok for a real tty
  [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]
}

_color_enabled() {
  case "${COLOR_MODE:-auto}" in
    always) return 0 ;;
    never)  return 1 ;;
  esac
  [ -n "${NO_COLOR:-}" ] && return 1
  { [ -n "${FORCE_COLOR:-}" ] || [ -n "${CLICOLOR_FORCE:-}" ]; } && return 0
  # Auto: prefer the entrypoint's pre-tee capture; else a live check.
  case "${BASELINE_TTY_COLOR:-}" in
    1) return 0 ;;
    0) return 1 ;;
    *) _term_is_color_capable ;;
  esac
}

if _color_enabled; then
  C_INFO=$'\033['"${COLOR_INFO:-0;36}"'m'; C_OK=$'\033['"${COLOR_OK:-0;32}"'m'
  C_WARN=$'\033['"${COLOR_WARN:-0;33}"'m'; C_ERR=$'\033['"${COLOR_ERR:-0;31}"'m'
  C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_INFO=""; C_OK=""; C_WARN=""; C_ERR=""; C_DIM=""; C_OFF=""
fi

log()  { printf '%s[*]%s %s\n'  "$C_INFO" "$C_OFF" "$*"; }
ok()   { printf '%s[+]%s %s\n'  "$C_OK"   "$C_OFF" "$*"; }
warn() { printf '%s[!]%s %s\n'  "$C_WARN" "$C_OFF" "$*" >&2; }
err()  { printf '%s[x]%s %s\n'  "$C_ERR"  "$C_OFF" "$*" >&2; }
step() { printf '\n%s=== %s ===%s\n' "$C_INFO" "$*" "$C_OFF"; }

# run_aws: the dry-run gate. In dry-run it PRINTS the command (as a PREVIEW of the
# arguments, with shell quoting already parsed away, so it is not copy-paste-ready)
# and returns 0 without executing. With --apply it runs the command.
run_aws() {
  if [ "$APPLY" = "true" ]; then
    log "run: aws $*"
    aws "$@"
  else
    printf '%s[dry-run] would run (preview):%s aws %s\n' "$C_DIM" "$C_OFF" "$*"
    return 0
  fi
}

# read_aws: a READ-ONLY call that ALWAYS runs, even in dry-run, so state checks
# work. Use only for describe/list/get. Never for mutations.
read_aws() { aws "$@"; }

# require: fail fast if a config var is empty.
require() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    err "config.env is missing required value: $name"
    exit 1
  fi
}

# load_config: source config.env from the commands/ dir (sibling of lib/).
load_config() {
  local cfg="$1"
  if [ ! -f "$cfg" ]; then
    err "No config found at $cfg — copy config.env.example to config.env and edit it."
    exit 1
  fi
  # shellcheck disable=SC1090
  . "$cfg"
}

# resolve_account: set ACCOUNT_ID from the live identity. Never hard-coded.
resolve_account() {
  ACCOUNT_ID="$(read_aws sts get-caller-identity --query Account --output text)"
  local arn
  arn="$(read_aws sts get-caller-identity --query Arn --output text)"
  CALLER_ARN="$arn"
  log "account: $ACCOUNT_ID  identity: $arn"
  export ACCOUNT_ID CALLER_ARN
}

# resolve_region: pick the default region for general API calls.
# Precedence: existing AWS env/config region  ->  PREFERRED_REGION from config.env.
# Never overrides a region the user already set; only fills the gap. Billing/global
# steps still pin us-east-1 themselves regardless of this. Also defaults REGIONS
# (the region-scoped-step list) to the resolved region when config.env leaves it empty.
resolve_region() {
  local cfg_region=""
  cfg_region="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
  [ -z "$cfg_region" ] && cfg_region="$(aws configure get region 2>/dev/null || true)"

  if [ -n "$cfg_region" ]; then
    log "region: using AWS-configured region '$cfg_region'"
  elif [ -n "${PREFERRED_REGION:-}" ]; then
    export AWS_DEFAULT_REGION="$PREFERRED_REGION"
    log "region: no AWS default set; using PREFERRED_REGION '$PREFERRED_REGION'"
  else
    err "No region set: your AWS config has none and PREFERRED_REGION is empty in config.env."
    exit 1
  fi

  # Default the region-scoped-step list to the resolved region if unset.
  REGIONS="${REGIONS:-${cfg_region:-$PREFERRED_REGION}}"
  export REGIONS
}

# guard_paid: refuse a paid step under --free-only.
guard_paid() {
  local label="$1"
  if [ "$FREE_ONLY" = "true" ]; then
    warn "$label is a PAID service and --free-only is set; skipping."
    return 1
  fi
  return 0
}

# is_root: true if the resolved caller identity is the account root user.
# Root's ARN is arn:aws:iam::<account-id>:root (IAM users are :user/, roles :assumed-role/).
is_root() {
  case "${CALLER_ARN:-}" in
    *:root) return 0 ;;
    *)      return 1 ;;
  esac
}

# guard_not_root: enforce "don't operate as root" for the mutating baseline.
# Modes: "warn" (audit — root is harmless for reads, so just warn) or "enforce"
# (baseline — refuse unless FORCE_ROOT=true, since running mutations as root
# defeats the point of a scoped daily driver). The daily-driver bootstrap legitimately runs as
# root and is exempted by the caller (it doesn't call this in enforce mode).
guard_not_root() {
  local mode="${1:-enforce}"
  is_root || return 0   # not root: nothing to do
  if [ "$mode" = "warn" ]; then
    warn "You are running as the ROOT user. This is read-only so it's harmless,"
    warn "but for day-to-day work use your scoped daily-driver identity instead."
    return 0
  fi
  if [ "${FORCE_ROOT:-false}" = "true" ]; then
    warn "Running as ROOT (--force-root given). Prefer the daily-driver identity;"
    warn "root should be reserved for the bootstrap and the few root-only tasks."
    return 0
  fi
  err "You are running as the ROOT user. This baseline is meant to run as a scoped"
  err "daily-driver identity, not root (see the README's Quick start and iam-scoping)."
  err "Create/switch to your daily driver, or pass --force-root to proceed anyway."
  exit 1
}

# --- Outcome collector (end-of-run step-state summary) ---
# Each step calls: record <step> <outcome> [detail]
# Outcomes: applied | already-present | would-apply | partial | skipped |
#           disabled-in-config | failed
# Bash 3.2 safe: parallel indexed arrays, not associative.
_REC_NAME=(); _REC_OUTCOME=(); _REC_DETAIL=()

record() {
  _REC_NAME+=("$1")
  _REC_OUTCOME+=("$2")
  _REC_DETAIL+=("${3:-}")
}

# print_summary: aligned step-state table + a one-line tally.
print_summary() {
  local mode="DRY RUN"; [ "$APPLY" = "true" ] && mode="APPLIED"
  local applied=0 present=0 would=0 partial=0 skipped=0 disabled=0 failed=0
  printf '\n%s===================== Summary (%s) =====================%s\n' "$C_INFO" "$mode" "$C_OFF"
  printf '  %-18s %-20s %s\n' "STEP" "OUTCOME" "DETAIL"
  local i
  for i in "${!_REC_NAME[@]}"; do
    printf '  %-18s %-20s %s\n' "${_REC_NAME[$i]}" "${_REC_OUTCOME[$i]}" "${_REC_DETAIL[$i]}"
    case "${_REC_OUTCOME[$i]}" in
      applied) applied=$((applied+1));;
      already-present) present=$((present+1));;
      would-apply) would=$((would+1));;
      partial) partial=$((partial+1));;
      skipped*) skipped=$((skipped+1));;
      disabled-in-config) disabled=$((disabled+1));;
      failed) failed=$((failed+1));;
    esac
  done
  printf '%s=============================================================%s\n' "$C_INFO" "$C_OFF"
  local tally=""
  [ "$applied"  -gt 0 ] && tally="$tally$applied applied · "
  [ "$would"    -gt 0 ] && tally="$tally$would would-apply · "
  [ "$partial"  -gt 0 ] && tally="$tally$partial partial · "
  [ "$present"  -gt 0 ] && tally="$tally$present already-present · "
  [ "$skipped"  -gt 0 ] && tally="$tally$skipped skipped · "
  [ "$disabled" -gt 0 ] && tally="$tally$disabled disabled · "
  [ "$failed"   -gt 0 ] && tally="$tally$failed FAILED · "
  tally="${tally% · }"
  if [ "$APPLY" = "true" ]; then
    printf '  %s\n' "$tally"
  else
    printf '  %s   (dry run — nothing changed)\n' "$tally"
  fi
}

# --- Drift audit (live AWS state vs config intent) ---------------------------
# Shared read+compare helpers used by audit.sh to produce the comparison table.
# Each _state_* helper does READ-ONLY calls and echoes a simple token the compare
# logic understands. These are the single source of truth for "what is set"; the
# step scripts and the audit agree because they read the same way.
#
# A read can fail two ways that mean different things: the resource is genuinely
# ABSENT, or the caller is not ALLOWED to read it (e.g. the daily driver cannot read
# account:/iam: state). Reporting a denied read as "absent" is a false negative, so
# _classify_read separates them: it echoes present / absent / no-access.

# _classify_read <aws args...> : echo present | absent | no-access.
# Runs the read, capturing stderr; a permission error -> no-access, any other
# failure -> absent, success -> present.
_classify_read() {
  local err rc
  err="$(aws "$@" 2>&1 >/dev/null)"; rc=$?
  if [ "$rc" -eq 0 ]; then echo present; return; fi
  case "$err" in
    *AccessDenied*|*UnauthorizedOperation*|*not\ authorized\ to\ perform*) echo no-access ;;
    *) echo absent ;;
  esac
}

# Echo present / absent / no-access for the account S3 public-access block.
drift_state_s3_block() {
  _classify_read s3control get-public-access-block --account-id "$ACCOUNT_ID"
}

# Echo the live Monthly-Cost budget amount, or "absent".
drift_state_budget_amount() {
  local a
  a="$(read_aws budgets describe-budget --account-id "$ACCOUNT_ID" --budget-name Monthly-Cost \
    --region us-east-1 --query 'Budget.BudgetLimit.Amount' --output text 2>/dev/null || true)"
  { [ -z "$a" ] || [ "$a" = "None" ]; } && { echo absent; return; }
  echo "$a"
}

# Echo the live anomaly subscription threshold, or "absent".
drift_state_anomaly_threshold() {
  local sub_name="${ANOMALY_SUBSCRIPTION_NAME:-account-anomaly-alerts}" t
  t="$(read_aws ce get-anomaly-subscriptions --region us-east-1 \
    --query "AnomalySubscriptions[?SubscriptionName=='$sub_name'].ThresholdExpression.Dimensions.Values[0] | [0]" \
    --output text 2>/dev/null || true)"
  { [ -z "$t" ] || [ "$t" = "None" ]; } && { echo absent; return; }
  echo "$t"
}

# Echo present / absent / no-access for an alternate contact of the given type.
drift_state_contact() {
  _classify_read account get-alternate-contact --alternate-contact-type "$1"
}

# Echo present / absent / no-access for an IAM user.
drift_state_iam_user() {
  _classify_read iam get-user --user-name "$1"
}

# Echo present / absent / no-access for an IAM role.
drift_state_iam_role() {
  _classify_read iam get-role --role-name "$1"
}

# _nums_equal a b : true if a and b are numerically equal (handles "10" vs "10.0").
_nums_equal() {
  [ "$1" = "$2" ] && return 0
  case "$1$2" in *[!0-9.]*) return 1;; esac
  awk "BEGIN{exit !($1==$2)}" 2>/dev/null
}

# Drift rows: parallel arrays. Status is one of:
#   in-sync | out-of-sync | disabled (intent off)
_DR_SETTING=(); _DR_AWS=(); _DR_CFG=(); _DR_STATUS=()
drift_row() { _DR_SETTING+=("$1"); _DR_AWS+=("$2"); _DR_CFG+=("$3"); _DR_STATUS+=("$4"); }

# print_drift_table: aligned Setting | AWS Status | Baseline Setting | Status.
print_drift_table() {
  local synced=0 out=0 dis=0 noacc=0
  printf '\n%s================== Drift audit (live vs config) ==================%s\n' "$C_INFO" "$C_OFF"
  printf '  %-22s %-16s %-18s %s\n' "SETTING" "AWS STATUS" "BASELINE SETTING" "STATUS"
  local i c
  for i in "${!_DR_SETTING[@]}"; do
    case "${_DR_STATUS[$i]}" in
      in-sync)     c="$C_OK";   synced=$((synced+1));;
      out-of-sync) c="$C_ERR";  out=$((out+1));;
      no-access)   c="$C_DIM";  noacc=$((noacc+1));;
      disabled)    c="$C_DIM";  dis=$((dis+1));;
      *)           c="$C_DIM";;
    esac
    printf '  %-22s %-16s %-18s %s%s%s\n' \
      "${_DR_SETTING[$i]}" "${_DR_AWS[$i]}" "${_DR_CFG[$i]}" "$c" "${_DR_STATUS[$i]}" "$C_OFF"
  done
  printf '%s==================================================================%s\n' "$C_INFO" "$C_OFF"
  local tally="$synced in sync"
  [ "$out" -gt 0 ]   && tally="$tally · $out out of sync"
  [ "$noacc" -gt 0 ] && tally="$tally · $noacc not readable (no access)"
  [ "$dis" -gt 0 ]   && tally="$tally · $dis disabled in config"
  printf '  %s\n' "$tally"
  [ "$noacc" -gt 0 ] && printf '  %s(rows marked no-access need a more privileged identity to read, e.g. the admin role or root.)%s\n' "$C_DIM" "$C_OFF"
  return 0
}

# --- Resource tags (provenance) ----------------------------------------------
# One opt-in provenance tag, ManagedBy=<MANAGED_BY_TAG>, applied to taggable
# resources. Turned off entirely by RESOURCE_TAGS=false. The tag key is fixed at
# "ManagedBy"; only its value is configurable. Applied at create time by the
# emitters below, and reconciled on an existing resource by _reconcile_tag (see the
# Tag reconcile section). Services take tags in different shapes, so there are two
# emitters:
#   _tag_iam_args -> shorthand for IAM create-user / create-role (--tags)
#   _tag_json     -> JSON array for budgets / CE --resource-tags
# Both echo nothing when tagging is disabled, so a step can splice them in
# unconditionally.
RESOURCE_TAGS="${RESOURCE_TAGS:-true}"
MANAGED_BY_TAG="${MANAGED_BY_TAG:-personal-aws-account-baseline}"

_tags_enabled() {
  [ "${RESOURCE_TAGS:-true}" = "true" ] && [ -n "${MANAGED_BY_TAG:-}" ]
}

# Echo IAM --tags shorthand, or nothing. Use unquoted so the args expand:
#   run_aws iam create-user --user-name "$u" $(_tag_iam_args)
_tag_iam_args() {
  _tags_enabled || return 0
  printf -- '--tags Key=ManagedBy,Value=%s' "$MANAGED_BY_TAG"
}

# Echo a JSON tag array for --resource-tags, or nothing.
_tag_json() {
  _tags_enabled || return 0
  printf '[{"Key":"ManagedBy","Value":"%s"}]' "$MANAGED_BY_TAG"
}

# --- Tag reconcile (the ManagedBy tag is UPDATABLE) --------------------------
# Tags are the one benign exception to "never modify a create-only resource": they
# are metadata, not identity or permissions, and are safe to reconcile. Each
# reconcile is diff-first (read the live ManagedBy value, compare to config) and
# writes ONLY under --update. Under plain --apply a difference is reported, not
# changed, exactly like the other updatable settings.
#
# Services read/write tags differently, so there is a reader + applier per service.
# The generic driver _reconcile_tag takes a resource label plus the two commands to
# run, so each step calls it with its own service verbs.

# _reconcile_tag <label> <live_value> <apply_cmd...>
#   live_value : current ManagedBy value ("" / "None" = untagged)
#   apply_cmd  : the tag-writing command (run only under --update)
# Records nothing; echoes a status word: matches | updated | would-update | drift |
# disabled. The caller folds this into its own record line.
_reconcile_tag() {
  _tags_enabled || { echo disabled; return 0; }
  local label="$1" live="$2"; shift 2
  if [ "$live" = "$MANAGED_BY_TAG" ]; then
    echo matches; return 0
  fi
  # Differs or missing.
  if [ "${UPDATE:-false}" = "true" ]; then
    log "reconciling ManagedBy tag on $label -> '$MANAGED_BY_TAG'"
    run_aws "$@"
    [ "$APPLY" = "true" ] && echo updated || echo would-update
  else
    warn "$label ManagedBy tag is '${live:-<none>}' but config says '$MANAGED_BY_TAG'."
    warn "Re-run with --update to reconcile (plain --apply does not modify existing tags)."
    echo drift
  fi
}

# Per-service live-value readers. Each echoes the current ManagedBy value, or "".
_tag_live_iam_user() {
  read_aws iam list-user-tags --user-name "$1" \
    --query "Tags[?Key=='ManagedBy'].Value | [0]" --output text 2>/dev/null | sed 's/^None$//'
}
_tag_live_iam_role() {
  read_aws iam list-role-tags --role-name "$1" \
    --query "Tags[?Key=='ManagedBy'].Value | [0]" --output text 2>/dev/null | sed 's/^None$//'
}
# Budgets and Cost Explorer both read tags via a resource ARN +
# list-tags-for-resource, returning ResourceTags[].{Key,Value}.
_tag_live_budgets() {
  read_aws budgets list-tags-for-resource --resource-arn "$1" --region us-east-1 \
    --query "ResourceTags[?Key=='ManagedBy'].Value | [0]" --output text 2>/dev/null | sed 's/^None$//'
}
_tag_live_ce() {
  read_aws ce list-tags-for-resource --resource-arn "$1" --region us-east-1 \
    --query "ResourceTags[?Key=='ManagedBy'].Value | [0]" --output text 2>/dev/null | sed 's/^None$//'
}
