# Contacts, notifications & recovery-path independence

**Script:** `contacts.sh` · **Cost:** free

## Why

If AWS can't reach you, you miss security and billing alerts. And if your recovery
path depends on infrastructure inside the account, a suspension or accidental
deletion can lock you out of the mailbox you need to get back in.

## Recovery-independence rule

Your root email and MFA recovery must not depend on anything hosted in this account.
If your root-email domain has its DNS/mail served from this same account (Route 53 +
SES), that is a circular dependency. Use an independent mailbox.

## What the script does

Runs in the root bootstrap, not as the daily driver: `account:PutAlternateContact`
is an account-management action outside `PowerUserAccess`, so the daily driver
cannot set contacts. Root (or the admin role) can.

Sets the SECURITY and BILLING alternate contacts to `RECOVERY_EMAIL` (an
independent mailbox), not `ALERT_EMAIL`, so AWS has a second channel if your primary
inbox is unavailable. If `RECOVERY_EMAIL` is unset or equals `ALERT_EMAIL`, it still
sets the contacts but warns there is no real redundancy.
```
aws account put-alternate-contact --alternate-contact-type SECURITY \
  --name "<NAME>" --title "<TITLE>" --email-address "<RECOVERY_EMAIL>" --phone-number "<PHONE>"
```

Alternate contacts are scoped by type and additive: a set alternate receives only
that category's correspondence (a Billing alternate gets finalized bills, a Security
alternate gets security notices), and it is an extra recipient alongside the root
email, not a replacement. This step sets SECURITY and BILLING; it does not set the
Operations contact, so operational notices still go to root only.

## Verify

```
aws account get-alternate-contact --alternate-contact-type SECURITY
aws ses list-identities
aws route53 list-hosted-zones
```
`get-alternate-contact` returns each type instead of `ResourceNotFoundException`. If
`ses list-identities` shows no identity for your root-email domain, mail for it is
not served from this account, which is what you want for recovery independence.
