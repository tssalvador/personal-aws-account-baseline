#!/usr/bin/env bash
# Step — Alternate contacts (Security + Billing). See docs/steps/security/contacts.md.
[ "${ENABLE_CONTACTS:-false}" = "true" ] || { log "contacts: disabled in config, skipping"; record contacts disabled-in-config "ENABLE_CONTACTS=false"; return 0; }
require ALERT_EMAIL; require CONTACT_NAME; require CONTACT_PHONE

step "Alternate contacts"

# Alternate contacts should use an INDEPENDENT recovery mailbox for real
# redundancy. Fall back to ALERT_EMAIL (the primary inbox) with a warning if
# RECOVERY_EMAIL is unset or identical — same-inbox alternates add no redundancy.
CONTACT_EMAIL="${RECOVERY_EMAIL:-}"
_redundant=1
if [ -z "$CONTACT_EMAIL" ] || [ "$CONTACT_EMAIL" = "$ALERT_EMAIL" ]; then
  warn "RECOVERY_EMAIL is unset or same as ALERT_EMAIL — alternates will point at your primary inbox (no real redundancy). Set RECOVERY_EMAIL to an independent mailbox."
  CONTACT_EMAIL="$ALERT_EMAIL"
  _redundant=0
fi

_contacts_set=0; _contacts_would=0; _contacts_failed=0
for t in SECURITY BILLING; do
  if read_aws account get-alternate-contact --alternate-contact-type "$t" >/dev/null 2>&1; then
    ok "$t already set — skipping"
    _contacts_set=$((_contacts_set+1))
  else
    log "setting $t contact -> $CONTACT_EMAIL"
    if run_aws account put-alternate-contact \
      --alternate-contact-type "$t" \
      --name "$CONTACT_NAME" --title "${CONTACT_TITLE:-Owner}" \
      --email-address "$CONTACT_EMAIL" --phone-number "$CONTACT_PHONE"; then
      _contacts_would=$((_contacts_would+1))
    else
      err "failed to set $t alternate contact (see error above)."
      _contacts_failed=$((_contacts_failed+1))
    fi
  fi
done

_redun_note="recovery mailbox"; [ "$_redundant" -eq 0 ] && _redun_note="PRIMARY inbox — no redundancy"
if [ "$_contacts_failed" -gt 0 ]; then
  if [ "$_contacts_would" -gt 0 ] || [ "$_contacts_set" -gt 0 ]; then
    record contacts partial "$_contacts_failed of 2 contacts failed (likely missing account-management permission; run in the root bootstrap)"
  else
    record contacts failed "could not set alternate contacts (needs account-management permission; run in the root bootstrap)"
  fi
elif [ "$_contacts_would" -eq 0 ]; then
  record contacts already-present "SECURITY + BILLING already set"
elif [ "$APPLY" = "true" ]; then
  record contacts applied "set $_contacts_would to $CONTACT_EMAIL ($_redun_note)"
else
  record contacts would-apply "$_contacts_would not set; would use $_redun_note"
fi
