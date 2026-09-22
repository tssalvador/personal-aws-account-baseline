#!/usr/bin/env bash
# Step — Daily-driver IAM user. See docs/steps/security/daily-driver.md.

step "Daily-driver IAM user"
DD_USER="${DAILY_DRIVER_USER:-}"
DD_GROUP="${DAILY_DRIVER_GROUP:-daily-drivers}"
CREATE="${CREATE_DAILY_DRIVER:-true}"

# --- Opt-out path: verify an existing daily driver, don't create one. ---
if [ "$CREATE" != "true" ]; then
  if [ -z "$DD_USER" ]; then
    err "CREATE_DAILY_DRIVER=false but DAILY_DRIVER_USER is empty. Name your existing"
    err "daily-driver IAM user so the baseline can verify it."
    exit 1
  fi
  if read_aws iam get-user --user-name "$DD_USER" >/dev/null 2>&1; then
    ok "verified existing IAM daily driver '$DD_USER'"
    record daily-driver verified "existing IAM user '$DD_USER'"
    return 0
  fi
  err "DAILY_DRIVER_USER '$DD_USER' is not an IAM user. Fix the name, or set"
  err "CREATE_DAILY_DRIVER=true to create one."
  exit 1
fi

# --- Create path (default). ---
require DAILY_DRIVER_USER

# If the user already exists, this is a no-op for the identity itself — do NOT touch
# an existing user's identity or permissions. The ManagedBy TAG is the one benign
# exception: reconcile it diff-first (under --update only).
if read_aws iam get-user --user-name "$DD_USER" >/dev/null 2>&1; then
  _tag_status="$(_reconcile_tag "user '$DD_USER'" "$(_tag_live_iam_user "$DD_USER")" \
    iam tag-user --user-name "$DD_USER" --tags Key=ManagedBy,Value="${MANAGED_BY_TAG:-}")"
  case "$_tag_status" in
    updated|would-update) record daily-driver applied "user '$DD_USER' exists; ManagedBy tag reconciled" ;;
    drift)                record daily-driver already-present "user '$DD_USER' exists; ManagedBy tag differs (use --update)" ;;
    *)                    record daily-driver already-present "user '$DD_USER' exists" ;;
  esac
  ok "IAM user '$DD_USER' already exists — not modifying the user"
  return 0
fi

# Group with the scoped policies (PowerUserAccess = everything except IAM/Org).
if read_aws iam get-group --group-name "$DD_GROUP" >/dev/null 2>&1; then
  ok "group '$DD_GROUP' already exists"
else
  log "creating group '$DD_GROUP'"
  run_aws iam create-group --group-name "$DD_GROUP"
fi
log "attaching PowerUserAccess + AWSBillingReadOnlyAccess to '$DD_GROUP'"
run_aws iam attach-group-policy --group-name "$DD_GROUP" \
  --policy-arn arn:aws:iam::aws:policy/PowerUserAccess
run_aws iam attach-group-policy --group-name "$DD_GROUP" \
  --policy-arn arn:aws:iam::aws:policy/AWSBillingReadOnlyAccess

log "creating user '$DD_USER' and adding to '$DD_GROUP'"
run_aws iam create-user --user-name "$DD_USER" $(_tag_iam_args)
run_aws iam add-user-to-group --user-name "$DD_USER" --group-name "$DD_GROUP"

warn "NEXT (manual, console): set '$DD_USER' a console password and enrol its MFA,"
warn "then re-authenticate as '$DD_USER' for day-to-day work. See the step doc."
warn "  Console: https://console.aws.amazon.com/iam/home#/users/details/$DD_USER"

if [ "$APPLY" = "true" ]; then
  record daily-driver applied "user '$DD_USER' in '$DD_GROUP' (set password + MFA in console)"
else
  record daily-driver would-apply "would create '$DD_USER' in '$DD_GROUP'"
fi
