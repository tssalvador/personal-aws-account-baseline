# Manual steps (console-only)

Two actions in this baseline have no AWS CLI equivalent and must be done in the
console.Most of the other steps are scripted under commands/, with any exceptions
that require the console called out.


## 1. Root user MFA

This is the single most important security control. The root user can't be
restricted by IAM policies at all, and assigning it an Multi-Factor Authentication
(MFA) device has no CLI or API, so this is inherently a console action. (The one
exception to "root can't be restricted" is the root user of a *member* account in
an AWS Organizations structure, which can be governed by service control policies
and centralized root management. A standalone account or the management account
of an AWS Organization has no such restriction.)

- Sign in as **root**. Under *Security credentials* → *Multi-factor authentication
  (MFA)*, assign a device (a hardware key like a [YubiKey](https://www.yubico.com/), or an [authenticator app](https://2fas.com/);
  more than one device is better).
- Repeat for each IAM user that has a console password, under IAM → Users →
  *Security credentials*.

**Verify (CLI).** There's no "is MFA on" API call, but the credential report's
`mfa_active` column can be used to verify:
```
aws iam generate-credential-report
aws iam get-credential-report --query Content --output text | base64 --decode
```
Confirm `mfa_active` is `true` on the `<root_account>` row and on each user row.


## 2. Activate IAM billing access for IAM users

By default only the root user can open the Billing console, regardless of IAM
permissions. Enabling billing access for non-root users lets users with the
appropriate IAM permissions view spend, budgets, and Cost Explorer, minimising the
need to log in as the root user. This is an account-level toggle, only available in
the console.

- Signed in as the root user, go to
  *Account* → *IAM user and role access to billing information* → **Activate IAM
  Access**.

**Verify.** Sign in as an IAM user and confirm the Billing console loads.
