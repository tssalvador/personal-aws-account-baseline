#!/usr/bin/env bash
# Read-only drift audit. Compares the LIVE state of each step against what your
# config.env intends, and prints a table showing what is in sync and what is not.
# Runs ONLY describe/list/get calls — never mutates, never incurs cost. Safe to run
# anytime, including as a non-admin. To act on the differences, run baseline.sh
# (--apply to create what's missing, --update to change updatable values).

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$HERE/lib/common.sh"

# Load config for the "intended" side of the comparison. Not required — without it
# every row just reports the live AWS state against an unset intent.
if [ -f "$HERE/config.env" ]; then
  # shellcheck disable=SC1091
  . "$HERE/config.env"
fi

resolve_account
resolve_region
guard_not_root warn

# --- Build the comparison rows --------------------------------------------------
# Helper: on/off intent from an ENABLE_* style flag (default true).
_intent() { [ "${1:-true}" = "true" ] && echo Enabled || echo Disabled; }

# S3 account public-access block (present/absent/no-access vs enabled intent).
_s3_live="$(drift_state_s3_block)"
_s3_intent="${ENABLE_S3_BLOCK:-true}"
if [ "$_s3_live" = no-access ]; then
  drift_row "S3 public-access block" "no access" "$(_intent "$_s3_intent")" no-access
elif [ "$_s3_intent" != "true" ]; then
  drift_row "S3 public-access block" \
    "$([ "$_s3_live" = present ] && echo Enabled || echo Disabled)" "Disabled" disabled
else
  [ "$_s3_live" = present ] && _s3_status=in-sync || _s3_status=out-of-sync
  drift_row "S3 public-access block" \
    "$([ "$_s3_live" = present ] && echo Enabled || echo Disabled)" "Enabled" "$_s3_status"
fi

# Monthly cost budget (amount drift).
_bud_live="$(drift_state_budget_amount)"
if [ "${ENABLE_BUDGETS:-true}" != "true" ]; then
  drift_row "Budget (Monthly-Cost)" \
    "$([ "$_bud_live" = absent ] && echo "not set" || echo "\$$_bud_live")" "disabled" disabled
elif [ "$_bud_live" = absent ]; then
  drift_row "Budget (Monthly-Cost)" "not set" "\$${MONTHLY_BUDGET_AMOUNT:-?}" out-of-sync
elif _nums_equal "$_bud_live" "${MONTHLY_BUDGET_AMOUNT:-}"; then
  drift_row "Budget (Monthly-Cost)" "\$$_bud_live" "\$${MONTHLY_BUDGET_AMOUNT}" in-sync
else
  drift_row "Budget (Monthly-Cost)" "\$$_bud_live" "\$${MONTHLY_BUDGET_AMOUNT}" out-of-sync
fi

# Cost Anomaly Detection subscription (threshold drift).
_an_live="$(drift_state_anomaly_threshold)"
if [ "${ENABLE_ANOMALY:-true}" != "true" ]; then
  drift_row "Anomaly threshold" \
    "$([ "$_an_live" = absent ] && echo "not set" || echo "\$$_an_live")" "disabled" disabled
elif [ "$_an_live" = absent ]; then
  drift_row "Anomaly threshold" "not set" "\$${ANOMALY_THRESHOLD:-?}" out-of-sync
elif _nums_equal "$_an_live" "${ANOMALY_THRESHOLD:-}"; then
  drift_row "Anomaly threshold" "\$$_an_live" "\$${ANOMALY_THRESHOLD}" in-sync
else
  drift_row "Anomaly threshold" "\$$_an_live" "\$${ANOMALY_THRESHOLD}" out-of-sync
fi

# Alternate contacts (SECURITY + BILLING; present/absent vs enabled intent).
if [ "${ENABLE_CONTACTS:-true}" != "true" ]; then
  drift_row "Alternate contacts" "-" "disabled" disabled
else
  for t in SECURITY BILLING; do
    _c_live="$(drift_state_contact "$t")"
    case "$_c_live" in
      present)   drift_row "Contact ($t)" "set" "set" in-sync ;;
      no-access) drift_row "Contact ($t)" "no access" "set" no-access ;;
      *)         drift_row "Contact ($t)" "not set" "set" out-of-sync ;;
    esac
  done
fi

# Daily-driver IAM user (present/absent/no-access).
if [ -n "${DAILY_DRIVER_USER:-}" ]; then
  _dd_live="$(drift_state_iam_user "$DAILY_DRIVER_USER")"
  case "$_dd_live" in
    present)   drift_row "Daily-driver user" "exists" "$DAILY_DRIVER_USER" in-sync ;;
    no-access) drift_row "Daily-driver user" "no access" "$DAILY_DRIVER_USER" no-access ;;
    *)         drift_row "Daily-driver user" "missing" "$DAILY_DRIVER_USER" out-of-sync ;;
  esac
fi

# Admin role (present/absent/no-access).
if [ "${CREATE_ADMIN_ROLE:-true}" != "true" ]; then
  drift_row "Admin role" "-" "disabled" disabled
elif [ -n "${ADMIN_ROLE:-}" ]; then
  _ar_live="$(drift_state_iam_role "$ADMIN_ROLE")"
  case "$_ar_live" in
    present)   drift_row "Admin role" "exists" "$ADMIN_ROLE" in-sync ;;
    no-access) drift_row "Admin role" "no access" "$ADMIN_ROLE" no-access ;;
    *)         drift_row "Admin role" "missing" "$ADMIN_ROLE" out-of-sync ;;
  esac
fi

# ManagedBy tag drift on taggable resources (only when tagging is enabled and the
# resource exists). Compares the live ManagedBy value to MANAGED_BY_TAG.
if _tags_enabled; then
  _tag_row() {  # <label> <live_value>
    local label="$1" live="$2" status
    if [ "$live" = "$MANAGED_BY_TAG" ]; then status=in-sync
    else status=out-of-sync; fi
    drift_row "$label" "${live:-<none>}" "$MANAGED_BY_TAG" "$status"
  }
  [ -n "${DAILY_DRIVER_USER:-}" ] && [ "$(drift_state_iam_user "$DAILY_DRIVER_USER")" = present ] && \
    _tag_row "Tag: user" "$(_tag_live_iam_user "$DAILY_DRIVER_USER")"
  [ "${CREATE_ADMIN_ROLE:-true}" = "true" ] && [ -n "${ADMIN_ROLE:-}" ] && [ "$(drift_state_iam_role "$ADMIN_ROLE")" = present ] && \
    _tag_row "Tag: admin role" "$(_tag_live_iam_role "$ADMIN_ROLE")"
  if [ "${ENABLE_BUDGETS:-true}" = "true" ] && [ "$(drift_state_budget_amount)" != absent ]; then
    _tag_row "Tag: budget" "$(_tag_live_budgets "arn:aws:budgets::${ACCOUNT_ID}:budget/Monthly-Cost")"
  fi
  if [ "${ENABLE_ANOMALY:-true}" = "true" ]; then
    _mon_name="${ANOMALY_MONITOR_NAME:-account-services-monitor}"
    _sub_name="${ANOMALY_SUBSCRIPTION_NAME:-account-anomaly-alerts}"
    _mon_arn="$(read_aws ce get-anomaly-monitors --region us-east-1 \
      --query "AnomalyMonitors[?MonitorName=='$_mon_name'].MonitorArn | [0]" --output text 2>/dev/null || true)"
    [ -n "$_mon_arn" ] && [ "$_mon_arn" != "None" ] && \
      _tag_row "Tag: monitor" "$(_tag_live_ce "$_mon_arn")"
    _sub_arn="$(read_aws ce get-anomaly-subscriptions --region us-east-1 \
      --query "AnomalySubscriptions[?SubscriptionName=='$_sub_name'].SubscriptionArn | [0]" --output text 2>/dev/null || true)"
    [ -n "$_sub_arn" ] && [ "$_sub_arn" != "None" ] && \
      _tag_row "Tag: subscription" "$(_tag_live_ce "$_sub_arn")"
  fi
fi

print_drift_table

printf '\n'
ok "Audit complete — read-only, nothing changed. Run baseline.sh to reconcile."
