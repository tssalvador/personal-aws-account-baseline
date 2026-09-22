# Cost Anomaly Detection

**Script:** `anomaly.sh` · **Cost:** free · **On by default** (`ENABLE_ANOMALY=true`)

## Why

Cost Anomaly Detection uses machine learning to assess your spend against your usage
patterns, flagging things like an unused service being spun up or an unusual spike
or dip. It gives you early warning when something unexpected happens. This step
creates a monitor with an anomaly threshold (default $10 USD) and emails you daily.

## What the script does

On by default (`ENABLE_ANOMALY=true`). The monitor is created only if one with the
configured name is missing. The subscription is created if it does not exist, and if
it does, running with `--update` updates its threshold and frequency to match (plain
`--apply` leaves it as-is). So to change the alert threshold, edit `ANOMALY_THRESHOLD`
and re-run with `--update`. Cost
Anomaly Detection is a global service, so its API calls use `us-east-1`. Alerts go
to `ALERT_EMAIL`.

```
aws ce create-anomaly-monitor --region us-east-1 \
  --anomaly-monitor '{"MonitorName":"<ANOMALY_MONITOR_NAME>","MonitorType":"DIMENSIONAL","MonitorDimension":"SERVICE"}'
aws ce create-anomaly-subscription --region us-east-1 \
  --anomaly-subscription '{"SubscriptionName":"<ANOMALY_SUBSCRIPTION_NAME>","MonitorArnList":["<MONITOR_ARN>"],"Subscribers":[{"Type":"EMAIL","Address":"<ALERT_EMAIL>"}],"Frequency":"DAILY","ThresholdExpression":{"Dimensions":{"Key":"ANOMALY_TOTAL_IMPACT_ABSOLUTE","MatchOptions":["GREATER_THAN_OR_EQUAL"],"Values":["<ANOMALY_THRESHOLD>"]}}}'
```

The monitor watches spend per service. The subscription controls who is alerted and
when: `ANOMALY_THRESHOLD` (USD) is the anomaly total-impact level at or above which
an alert is sent, and `Frequency` DAILY batches alerts into one daily email.

The monitor and subscription are tagged `ManagedBy` (create time, and reconciled on
`--update`); see [Resource tags](../../configuration.md#resource-tags).

## Config

- `ENABLE_ANOMALY` (default `true`)
- `ANOMALY_MONITOR_NAME` (default `account-services-monitor`)
- `ANOMALY_SUBSCRIPTION_NAME` (default `account-anomaly-alerts`)
- `ANOMALY_THRESHOLD` (default `10`, in USD)

## Verify

```
aws ce get-anomaly-monitors --region us-east-1
aws ce get-anomaly-subscriptions --region us-east-1
```
The monitor and subscription exist with your configured names, and the subscription
lists your alert email.
