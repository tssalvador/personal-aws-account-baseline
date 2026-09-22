#!/usr/bin/env bash
# Step — Budgets. See docs/steps/cost/budgets.md.
[ "${ENABLE_BUDGETS:-false}" = "true" ] || { log "budgets: disabled, skipping"; record budgets disabled-in-config "ENABLE_BUDGETS=false"; return 0; }
require ALERT_EMAIL

step "Budgets"

_have_budget() {
  read_aws budgets describe-budget --account-id "$ACCOUNT_ID" --budget-name "$1" \
    --region us-east-1 >/dev/null 2>&1
}
_notify_json() {
  printf '[{"Notification":{"NotificationType":"ACTUAL","ComparisonOperator":"GREATER_THAN","Threshold":%s},"Subscribers":[{"SubscriptionType":"EMAIL","Address":"%s"}]}]' "$1" "$ALERT_EMAIL"
}

require MONTHLY_BUDGET_AMOUNT
_budget_json="{\"BudgetName\":\"Monthly-Cost\",\"BudgetLimit\":{\"Amount\":\"$MONTHLY_BUDGET_AMOUNT\",\"Unit\":\"USD\"},\"TimeUnit\":\"MONTHLY\",\"BudgetType\":\"COST\"}"

if _have_budget "Monthly-Cost"; then
  # Exists: compare the live limit to config (diff-first). update-budget replaces the
  # budget definition; the notification subscriber is left in place.
  _live_amount="$(read_aws budgets describe-budget --account-id "$ACCOUNT_ID" \
    --budget-name "Monthly-Cost" --region us-east-1 \
    --query 'Budget.BudgetLimit.Amount' --output text 2>/dev/null || true)"
  # AWS may return the amount as e.g. "10.0"; compare numerically where possible.
  if [ "$_live_amount" = "$MONTHLY_BUDGET_AMOUNT" ] || \
     { [ -n "$_live_amount" ] && [ "$_live_amount" != "None" ] && \
       awk "BEGIN{exit !($_live_amount==$MONTHLY_BUDGET_AMOUNT)}" 2>/dev/null; }; then
    ok "Monthly-Cost budget already at \$$MONTHLY_BUDGET_AMOUNT"
    record budgets already-present "Monthly-Cost budget matches config (\$$MONTHLY_BUDGET_AMOUNT)"
  elif [ "$UPDATE" = "true" ]; then
    log "updating Monthly-Cost budget: \$$_live_amount -> \$$MONTHLY_BUDGET_AMOUNT"
    run_aws budgets update-budget --account-id "$ACCOUNT_ID" --region us-east-1 \
      --new-budget "$_budget_json"
    record budgets applied "Monthly-Cost budget updated to \$$MONTHLY_BUDGET_AMOUNT"
  else
    warn "Monthly-Cost budget is \$$_live_amount but config says \$$MONTHLY_BUDGET_AMOUNT."
    warn "Re-run with --update to change it (plain --apply does not modify existing values)."
    record budgets skipped "Monthly-Cost differs (\$$_live_amount vs \$$MONTHLY_BUDGET_AMOUNT); use --update"
  fi
  # Reconcile the ManagedBy tag (diff-first, --update only). Independent of the
  # amount: an existing budget may need only its tag brought into line.
  _budget_arn="arn:aws:budgets::${ACCOUNT_ID}:budget/Monthly-Cost"
  _reconcile_tag "budget 'Monthly-Cost'" "$(_tag_live_budgets "$_budget_arn")" \
    budgets tag-resource --resource-arn "$_budget_arn" --region us-east-1 \
    --resource-tags Key=ManagedBy,Value="${MANAGED_BY_TAG:-}" >/dev/null
else
  log "creating Monthly-Cost budget \$$MONTHLY_BUDGET_AMOUNT (alerts at 80%)"
  _budget_tags="$(_tag_json)"
  if [ -n "$_budget_tags" ]; then
    run_aws budgets create-budget --account-id "$ACCOUNT_ID" --region us-east-1 \
      --budget "$_budget_json" \
      --notifications-with-subscribers "$(_notify_json 80)" \
      --resource-tags "$_budget_tags"
  else
    run_aws budgets create-budget --account-id "$ACCOUNT_ID" --region us-east-1 \
      --budget "$_budget_json" \
      --notifications-with-subscribers "$(_notify_json 80)"
  fi
  if [ "$APPLY" = "true" ]; then
    record budgets applied "Monthly-Cost budget \$$MONTHLY_BUDGET_AMOUNT created"
  else
    record budgets would-apply "would create Monthly-Cost budget \$$MONTHLY_BUDGET_AMOUNT"
  fi
fi
