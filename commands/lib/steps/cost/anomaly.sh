#!/usr/bin/env bash
# Step — Cost Anomaly Detection. See docs/steps/cost/anomaly.md.
# Global service: its API lives in us-east-1 (see AN_REGION below).
[ "${ENABLE_ANOMALY:-false}" = "true" ] || { log "anomaly: disabled in config, skipping"; record anomaly disabled-in-config "ENABLE_ANOMALY=false"; return 0; }
require ALERT_EMAIL

step "Cost Anomaly Detection"

AN_REGION="us-east-1"   # global service; API is us-east-1
MON_NAME="${ANOMALY_MONITOR_NAME:-account-services-monitor}"
SUB_NAME="${ANOMALY_SUBSCRIPTION_NAME:-account-anomaly-alerts}"
# Alert when total anomaly impact for a period meets/exceeds this dollar amount.
THRESHOLD="${ANOMALY_THRESHOLD:-10}"

# 1. Monitor: a SERVICE-dimension monitor is effectively a singleton per account
#    (AWS caps dimensional monitors). Adopt an existing one rather than fight for a
#    second slot: prefer our named monitor, else ANY SERVICE-dimension monitor
#    (this catches AWS's auto-created Default-Services-Monitor). Only create when
#    none exists at all.
_mon_created=false
_mon_failed=false
MON_ARN="$(read_aws ce get-anomaly-monitors --region "$AN_REGION" \
  --query "AnomalyMonitors[?MonitorName=='$MON_NAME'].MonitorArn | [0]" \
  --output text 2>/dev/null || true)"

if [ -z "$MON_ARN" ] || [ "$MON_ARN" = "None" ]; then
  # No monitor of our name: adopt any existing SERVICE-dimension monitor.
  MON_ARN="$(read_aws ce get-anomaly-monitors --region "$AN_REGION" \
    --query "AnomalyMonitors[?MonitorDimension=='SERVICE'].MonitorArn | [0]" \
    --output text 2>/dev/null || true)"
  if [ -n "$MON_ARN" ] && [ "$MON_ARN" != "None" ]; then
    _adopted_name="$(read_aws ce get-anomaly-monitors --region "$AN_REGION" \
      --query "AnomalyMonitors[?MonitorDimension=='SERVICE'].MonitorName | [0]" --output text 2>/dev/null || true)"
    ok "adopting existing SERVICE monitor '${_adopted_name:-?}' (one dimensional monitor per account)"
  fi
fi

if [ -n "$MON_ARN" ] && [ "$MON_ARN" != "None" ]; then
  [ -z "${_adopted_name:-}" ] && ok "anomaly monitor '$MON_NAME' already exists — skipping"
  _reconcile_tag "monitor" "$(_tag_live_ce "$MON_ARN")" \
    ce tag-resource --resource-arn "$MON_ARN" --region "$AN_REGION" \
    --resource-tags Key=ManagedBy,Value="${MANAGED_BY_TAG:-}" >/dev/null
else
  log "creating SERVICE-dimension anomaly monitor '$MON_NAME' (none exists yet)"
  _an_tags="$(_tag_json)"
  if [ -n "$_an_tags" ]; then
    run_aws ce create-anomaly-monitor --region "$AN_REGION" \
      --anomaly-monitor "{\"MonitorName\":\"$MON_NAME\",\"MonitorType\":\"DIMENSIONAL\",\"MonitorDimension\":\"SERVICE\"}" \
      --resource-tags "$_an_tags" && _mon_created=true || _mon_failed=true
  else
    run_aws ce create-anomaly-monitor --region "$AN_REGION" \
      --anomaly-monitor "{\"MonitorName\":\"$MON_NAME\",\"MonitorType\":\"DIMENSIONAL\",\"MonitorDimension\":\"SERVICE\"}" \
      && _mon_created=true || _mon_failed=true
  fi
  if [ "$_mon_failed" = true ]; then
    err "failed to create the anomaly monitor; skipping the subscription (nothing to attach it to)."
    record anomaly failed "monitor create failed (see error above); subscription not attempted"
    return 0
  fi
  # Re-read the ARN so the subscription can reference it. In dry-run the monitor
  # does not exist yet, so use a placeholder for the preview.
  if [ "$APPLY" = "true" ]; then
    MON_ARN="$(read_aws ce get-anomaly-monitors --region "$AN_REGION" \
      --query "AnomalyMonitors[?MonitorName=='$MON_NAME'].MonitorArn | [0]" --output text 2>/dev/null || true)"
  else
    MON_ARN="<MONITOR_ARN (created above)>"
  fi
fi

# 2. Subscription: email alert tied to the monitor. Create if absent, else reconcile
#    its threshold/frequency to config (diff-first).
SUB_ARN="$(read_aws ce get-anomaly-subscriptions --region "$AN_REGION" \
  --query "AnomalySubscriptions[?SubscriptionName=='$SUB_NAME'].SubscriptionArn | [0]" \
  --output text 2>/dev/null || true)"

_threshold_expr="{\"Dimensions\":{\"Key\":\"ANOMALY_TOTAL_IMPACT_ABSOLUTE\",\"MatchOptions\":[\"GREATER_THAN_OR_EQUAL\"],\"Values\":[\"$THRESHOLD\"]}}"

if [ -n "$SUB_ARN" ] && [ "$SUB_ARN" != "None" ]; then
  # Exists: compare the live threshold to config (diff-first).
  _live_thr="$(read_aws ce get-anomaly-subscriptions --region "$AN_REGION" \
    --query "AnomalySubscriptions[?SubscriptionName=='$SUB_NAME'].ThresholdExpression.Dimensions.Values[0] | [0]" \
    --output text 2>/dev/null || true)"
  if [ -n "$_live_thr" ] && [ "$_live_thr" != "None" ] && \
     awk "BEGIN{exit !($_live_thr==$THRESHOLD)}" 2>/dev/null; then
    ok "anomaly subscription '$SUB_NAME' already at threshold \$$THRESHOLD"
    _sub_action="present"
  elif [ "$UPDATE" = "true" ]; then
    log "updating anomaly subscription '$SUB_NAME' (threshold -> \$$THRESHOLD, DAILY)"
    run_aws ce update-anomaly-subscription --region "$AN_REGION" \
      --subscription-arn "$SUB_ARN" \
      --frequency DAILY \
      --threshold-expression "$_threshold_expr"
    _sub_action="updated"
  else
    warn "anomaly subscription '$SUB_NAME' threshold is \$$_live_thr but config says \$$THRESHOLD."
    warn "Re-run with --update to change it (plain --apply does not modify existing values)."
    _sub_action="drift"
  fi
  # Reconcile the ManagedBy tag on the subscription (diff-first, --update only).
  _reconcile_tag "subscription '$SUB_NAME'" "$(_tag_live_ce "$SUB_ARN")" \
    ce tag-resource --resource-arn "$SUB_ARN" --region "$AN_REGION" \
    --resource-tags Key=ManagedBy,Value="${MANAGED_BY_TAG:-}" >/dev/null
else
  # Guard: never attach a subscription to an unresolved monitor ARN.
  if [ -z "$MON_ARN" ] || [ "$MON_ARN" = "None" ]; then
    err "no monitor ARN to attach the subscription to; skipping subscription."
    record anomaly partial "monitor ok but subscription skipped (monitor ARN unresolved)"
    return 0
  fi
  log "creating anomaly subscription '$SUB_NAME' (email $ALERT_EMAIL, threshold \$$THRESHOLD)"
  _an_sub_tags="$(_tag_json)"
  _sub_ok=false
  if [ -n "$_an_sub_tags" ]; then
    run_aws ce create-anomaly-subscription --region "$AN_REGION" \
      --anomaly-subscription "{\"SubscriptionName\":\"$SUB_NAME\",\"MonitorArnList\":[\"$MON_ARN\"],\"Subscribers\":[{\"Type\":\"EMAIL\",\"Address\":\"$ALERT_EMAIL\"}],\"Frequency\":\"DAILY\",\"ThresholdExpression\":$_threshold_expr}" \
      --resource-tags "$_an_sub_tags" && _sub_ok=true || _sub_ok=false
  else
    run_aws ce create-anomaly-subscription --region "$AN_REGION" \
      --anomaly-subscription "{\"SubscriptionName\":\"$SUB_NAME\",\"MonitorArnList\":[\"$MON_ARN\"],\"Subscribers\":[{\"Type\":\"EMAIL\",\"Address\":\"$ALERT_EMAIL\"}],\"Frequency\":\"DAILY\",\"ThresholdExpression\":$_threshold_expr}" \
      && _sub_ok=true || _sub_ok=false
  fi
  if [ "$_sub_ok" = true ] || [ "$APPLY" != "true" ]; then
    _sub_action="created"
  else
    err "failed to create the anomaly subscription (see error above)."
    _sub_action="failed"
  fi
fi

# Outcome.
_mon_state="present"
[ "$_mon_created" = true ] && _mon_state="created"
[ -n "${_adopted_name:-}" ] && _mon_state="adopted existing"
if [ "$_sub_action" = "failed" ]; then
  record anomaly partial "monitor $_mon_state; subscription '$SUB_NAME' FAILED (see error above)"
elif [ "$_sub_action" = "drift" ]; then
  record anomaly skipped "subscription '$SUB_NAME' threshold differs (\$$_live_thr vs \$$THRESHOLD); use --update"
elif [ "$APPLY" = "true" ]; then
  record anomaly applied "monitor $_mon_state; subscription '$SUB_NAME' $_sub_action (threshold \$$THRESHOLD)"
else
  record anomaly would-apply "monitor '$MON_NAME'; subscription '$SUB_NAME' would be $_sub_action (threshold \$$THRESHOLD)"
fi
