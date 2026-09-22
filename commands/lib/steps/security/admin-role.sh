#!/usr/bin/env bash
# Step — Admin role (assumable with MFA). See docs/steps/security/admin-role.md.
[ "${CREATE_ADMIN_ROLE:-false}" = "true" ] || { log "admin-role: disabled in config, skipping"; record admin-role disabled-in-config "CREATE_ADMIN_ROLE=false"; return 0; }
require ADMIN_ROLE
require ADMIN_GROUP
require DAILY_DRIVER_USER   # the IAM user added to the admins group

step "Admin role (assumable with MFA)"
SA_ROLE="$ADMIN_ROLE"
AD_GROUP="$ADMIN_GROUP"
DD_USER="$DAILY_DRIVER_USER"
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${SA_ROLE}"

# Session durations (seconds):
#   MAX_SESSION_DURATION = the role's ceiling (AWS range 3600..43200; can't go below
#     1h). Applied at create time only.
#   SESSION_DURATION     = what the CLI profile requests per assume (AWS range
#     900..MaxSessionDuration). This is the knob that makes sessions SHORTER than 1h.
#   Effective session = min(SESSION_DURATION, MAX_SESSION_DURATION).
MAX_SESSION_DURATION="${ADMIN_MAX_SESSION_DURATION:-3600}"
SESSION_DURATION="${ADMIN_SESSION_DURATION:-1800}"
case "$MAX_SESSION_DURATION" in *[!0-9]*|'') err "ADMIN_MAX_SESSION_DURATION must be a number of seconds."; exit 1 ;; esac
case "$SESSION_DURATION" in *[!0-9]*|'') err "ADMIN_SESSION_DURATION must be a number of seconds."; exit 1 ;; esac
if [ "$MAX_SESSION_DURATION" -lt 3600 ] || [ "$MAX_SESSION_DURATION" -gt 43200 ]; then
  err "ADMIN_MAX_SESSION_DURATION must be 3600..43200 (1h..12h)."; exit 1
fi
if [ "$SESSION_DURATION" -lt 900 ] || [ "$SESSION_DURATION" -gt "$MAX_SESSION_DURATION" ]; then
  err "ADMIN_SESSION_DURATION must be 900..$MAX_SESSION_DURATION (15m..the role cap)."; exit 1
fi

# The daily driver must be an IAM user to join the admins group. Decide up front and
# skip cleanly otherwise:
#   - IAM user exists now                    -> eligible.
#   - Not found but this run will create it   -> eligible (daily-driver step creates
#     an IAM user first; on --apply it exists by the time this runs).
#   - Exists but is not an IAM user           -> skip (nothing to add to the group).
if read_aws iam get-user --user-name "$DD_USER" >/dev/null 2>&1; then
  :   # eligible: IAM user present
elif [ "${CREATE_DAILY_DRIVER:-true}" = "true" ]; then
  :   # eligible: the daily-driver step creates an IAM user in this run
else
  warn "daily driver '$DD_USER' is not an IAM user, so it can't join the admins group."
  warn "This step needs an IAM-user daily driver. Skipping."
  record admin-role skipped "daily driver '$DD_USER' is not an IAM user"
  return 0
fi

# --- 1. The role (create if absent; never modify an existing one). ---
# Trust policy: any IAM identity in THIS account may assume the role, but ONLY with
# an MFA-authenticated session. (Principal :root = the account, not the root user;
# the assume is still gated by the group's sts:AssumeRole grant plus the MFA
# condition.)
TRUST="$(printf '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"AWS":"arn:aws:iam::%s:root"},"Action":"sts:AssumeRole","Condition":{"Bool":{"aws:MultiFactorAuthPresent":"true"}}}]}' "$ACCOUNT_ID")"

if read_aws iam get-role --role-name "$SA_ROLE" >/dev/null 2>&1; then
  ok "role '$SA_ROLE' already exists — not modifying it"
  _reconcile_tag "role '$SA_ROLE'" "$(_tag_live_iam_role "$SA_ROLE")" \
    iam tag-role --role-name "$SA_ROLE" --tags Key=ManagedBy,Value="${MANAGED_BY_TAG:-}" >/dev/null
else
  log "creating MFA-gated admin role '$SA_ROLE' (max session ${MAX_SESSION_DURATION}s)"
  run_aws iam create-role --role-name "$SA_ROLE" --assume-role-policy-document "$TRUST" \
    --max-session-duration "$MAX_SESSION_DURATION" $(_tag_iam_args)
  log "attaching AdministratorAccess to '$SA_ROLE'"
  run_aws iam attach-role-policy --role-name "$SA_ROLE" \
    --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
fi

# --- 2. The admins group holds the assume-role grant. ---
if read_aws iam get-group --group-name "$AD_GROUP" >/dev/null 2>&1; then
  ok "group '$AD_GROUP' already exists"
else
  log "creating admins group '$AD_GROUP'"
  run_aws iam create-group --group-name "$AD_GROUP"
fi
log "granting group '$AD_GROUP' sts:AssumeRole on '$SA_ROLE'"
run_aws iam put-group-policy --group-name "$AD_GROUP" \
  --policy-name "assume-${SA_ROLE}" \
  --policy-document "$(printf '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"sts:AssumeRole","Resource":"%s"}]}' "$ROLE_ARN")"

# --- 3. The daily-driver user joins the admins group. ---
log "adding '$DD_USER' to the admins group '$AD_GROUP'"
run_aws iam add-user-to-group --user-name "$DD_USER" --group-name "$AD_GROUP"

# --- 4. Write / reconcile a named CLI profile in ~/.aws/config (on by default). ---
# Not secret: role ARN + source profile + MFA device ARN, so 'aws --profile <name>'
# auto-assumes the role and prompts for the MFA code. Self-healing across runs:
#   - no profile          -> write it (real MFA serial if enrolled, else placeholder).
#   - has placeholder,
#     MFA now enrolled     -> update just the mfa_serial line in place ("fixes itself"
#                             on a later run, or if the user pre-existed with MFA).
#   - real serial already  -> leave it (skip).
#   - still placeholder,
#     MFA still absent      -> leave it, note it's pending.
# We only ever touch the mfa_serial line INSIDE our own profile block; other
# profiles and content are never modified.
if [ "${WRITE_ADMIN_PROFILE:-true}" = "true" ]; then
  PROFILE_NAME="${ADMIN_PROFILE_NAME:-admin}"
  AWS_CONFIG_FILE_PATH="${AWS_CONFIG_FILE:-$HOME/.aws/config}"
  PLACEHOLDER="arn:aws:iam::${ACCOUNT_ID}:mfa/<DAILY_DRIVER_MFA>"

  # Resolve the daily driver's real MFA device ARN if one is enrolled.
  MFA_SERIAL="$(read_aws iam list-mfa-devices --user-name "$DD_USER" \
    --query 'MFADevices[0].SerialNumber' --output text 2>/dev/null || true)"
  if [ -z "$MFA_SERIAL" ] || [ "$MFA_SERIAL" = "None" ]; then
    MFA_SERIAL="$PLACEHOLDER"
  fi

  _profile_exists=false
  [ -f "$AWS_CONFIG_FILE_PATH" ] && grep -Eq "^\[profile[[:space:]]+${PROFILE_NAME}\]" "$AWS_CONFIG_FILE_PATH" 2>/dev/null && _profile_exists=true

  if [ "$_profile_exists" = false ]; then
    # Region for the profile so 'aws --profile admin' works without a manual
    # AWS_REGION. Prefer the resolved default region, else PREFERRED_REGION.
    _PROFILE_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-${PREFERRED_REGION:-}}}"
    PROFILE_BLOCK="$(printf '\n[profile %s]\nrole_arn = %s\nsource_profile = default\nmfa_serial = %s\nduration_seconds = %s\nregion = %s\n' \
      "$PROFILE_NAME" "$ROLE_ARN" "$MFA_SERIAL" "$SESSION_DURATION" "$_PROFILE_REGION")"
    if [ "$APPLY" = "true" ]; then
      log "writing profile '[profile $PROFILE_NAME]' to $AWS_CONFIG_FILE_PATH"
      mkdir -p "$(dirname "$AWS_CONFIG_FILE_PATH")"
      printf '%s' "$PROFILE_BLOCK" >> "$AWS_CONFIG_FILE_PATH"
      case "$MFA_SERIAL" in
        *"<DAILY_DRIVER_MFA>"*) warn "MFA not enrolled yet: the profile has a placeholder mfa_serial. Re-run this step after enrolling MFA and it will fill in the real device ARN." ;;
      esac
    else
      printf '%s[dry-run] would append to %s:%s\n' "$C_DIM" "$AWS_CONFIG_FILE_PATH" "$C_OFF"
      printf '%s\n' "$PROFILE_BLOCK"
    fi
  else
    # Profile exists. Reconcile the mfa_serial ONLY if it is still the placeholder
    # AND we now have a real serial to write.
    _has_placeholder=false
    awk -v p="[profile ${PROFILE_NAME}]" '
      $0==p {inblk=1; next}
      /^\[/ {inblk=0}
      inblk && /^[[:space:]]*mfa_serial[[:space:]]*=/ && /<DAILY_DRIVER_MFA>/ {found=1}
      END {exit found?0:1}
    ' "$AWS_CONFIG_FILE_PATH" 2>/dev/null && _has_placeholder=true

    if [ "$_has_placeholder" = true ] && [ "$MFA_SERIAL" != "$PLACEHOLDER" ]; then
      if [ "$APPLY" = "true" ]; then
        log "reconciling profile '$PROFILE_NAME': filling in the enrolled MFA device ARN"
        _tmp="$(mktemp)"
        awk -v p="[profile ${PROFILE_NAME}]" -v serial="$MFA_SERIAL" '
          $0==p {inblk=1; print; next}
          /^\[/ {inblk=0}
          inblk && /^[[:space:]]*mfa_serial[[:space:]]*=/ { print "mfa_serial = " serial; next }
          {print}
        ' "$AWS_CONFIG_FILE_PATH" > "$_tmp" && cat "$_tmp" > "$AWS_CONFIG_FILE_PATH" && rm -f "$_tmp"
        ok "profile '$PROFILE_NAME' mfa_serial updated to the enrolled device"
      else
        printf '%s[dry-run] would update mfa_serial in profile %s to %s%s\n' "$C_DIM" "$PROFILE_NAME" "$MFA_SERIAL" "$C_OFF"
      fi
    elif [ "$_has_placeholder" = true ]; then
      ok "profile '$PROFILE_NAME' exists with a placeholder mfa_serial; MFA still not enrolled, leaving it."
    else
      ok "profile '[profile $PROFILE_NAME]' already present and complete — leaving it."
    fi
  fi
  log "use it with: aws --profile ${PROFILE_NAME} <cmd>  (prompts for your MFA code; temp creds ~1h)"
else
  warn "To use the role, add a profile to ~/.aws/config (WRITE_ADMIN_PROFILE=false):"
  warn "  [profile admin]"
  warn "  role_arn = $ROLE_ARN"
  warn "  source_profile = default"
  warn "  mfa_serial = arn:aws:iam::${ACCOUNT_ID}:mfa/<DAILY_DRIVER_MFA>"
  warn "  duration_seconds = ${SESSION_DURATION}"
  warn "  region = ${PREFERRED_REGION:-<your-region>}"
fi
log "console: bookmark this to switch role in one click (already MFA'd in the console):"
log "  https://signin.aws.amazon.com/switchrole?account=${ACCOUNT_ID}&roleName=${SA_ROLE}&displayName=Admin"
warn "Use this elevation only for Org/IAM tasks. See admin-role.md."

if [ "$APPLY" = "true" ]; then
  record admin-role applied "role '$SA_ROLE' + assume grant on group '$AD_GROUP' + '$DD_USER' joined${WRITE_ADMIN_PROFILE:+ + ~/.aws/config profile}"
else
  record admin-role would-apply "would create role '$SA_ROLE', grant assume to group '$AD_GROUP', add '$DD_USER'"
fi
