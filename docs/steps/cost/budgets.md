# Budgets (monthly cost)

**Script:** `budgets.sh` · **Cost:** free (first two budgets per account are free)

## Why

A monthly spend budget notifies you as your spend approaches the limit, reducing
surprise spend and giving you the chance to act. You're alerted when spend passes
80% of the budget.

### Refresh cadence

AWS Budgets updates its cost data up to three times a day, typically 8 to 12 hours
apart ([AWS docs](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html)).
So a budget alert is not real-time: if you are experimenting heavily, spend can run
ahead of what the budget has seen, and the alert can lag several hours behind the
actual charge. Treat it as a same-day safety net, not an instant cutoff.

## What the script does

Creates a monthly cost budget at `MONTHLY_BUDGET_AMOUNT` (USD) that emails
`ALERT_EMAIL` when actual spend passes 80% of the limit. If the budget already
exists, its amount is updated to match your config when you run with `--update`, so
to change the limit you edit `MONTHLY_BUDGET_AMOUNT` and re-run with `--update`
(plain `--apply` leaves an existing budget as-is).
```
aws budgets create-budget --account-id <ACCOUNT_ID> --region us-east-1 \
  --budget '{"BudgetName":"Monthly-Cost","BudgetLimit":{"Amount":"<MONTHLY_BUDGET_AMOUNT>","Unit":"USD"},"TimeUnit":"MONTHLY","BudgetType":"COST"}' \
  --notifications-with-subscribers '<NOTIFY>'
```
`<NOTIFY>` is a subscriber block, e.g.
`[{"Notification":{"NotificationType":"ACTUAL","ComparisonOperator":"GREATER_THAN","Threshold":80},"Subscribers":[{"SubscriptionType":"EMAIL","Address":"<ALERT_EMAIL>"}]}]`.
On an update, the budget amount is replaced via `update-budget`; the notification
subscriber is left in place.

The budget is tagged `ManagedBy` (create time, and reconciled on `--update`); see
[Resource tags](../../configuration.md#resource-tags).


## Verify

```
aws budgets describe-budgets --account-id <ACCOUNT_ID> --region us-east-1
```
Lists your Monthly-Cost budget with the right subscriber.
