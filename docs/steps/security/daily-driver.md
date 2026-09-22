# Daily-driver IAM user

**Script:** `daily-driver.sh` · **Cost:** free · **On by default** (`CREATE_DAILY_DRIVER=true`)

## Why

Use a **scoped everyday identity** for routine work and reserve a rarely-used admin
role (or root) for consequential changes. This step creates the everyday one so you
stop reaching for root. It runs early: right after the
root-only actions, before the rest of the baseline, so you can switch to it and run
everything else as the daily driver. See [../../iam-scoping.md](../../iam-scoping.md)
for the model.

## What the script does

On by default (`CREATE_DAILY_DRIVER=true`): creates the everyday user if it doesn't
already exist, and never modifies an existing one. If you already have a daily
driver, set `CREATE_DAILY_DRIVER=false` and name it in `DAILY_DRIVER_USER`; the
step then **verifies** that the IAM user exists and
fails if it can positively determine it doesn't, so opting out can't silently leave
you operating as root.

Create path:
```
aws iam create-group --group-name <DAILY_DRIVER_GROUP>
aws iam attach-group-policy --group-name <DAILY_DRIVER_GROUP> \
  --policy-arn arn:aws:iam::aws:policy/PowerUserAccess
aws iam attach-group-policy --group-name <DAILY_DRIVER_GROUP> \
  --policy-arn arn:aws:iam::aws:policy/AWSBillingReadOnlyAccess
aws iam create-user --user-name <DAILY_DRIVER_USER>
aws iam add-user-to-group --user-name <DAILY_DRIVER_USER> --group-name <DAILY_DRIVER_GROUP>
```
`PowerUserAccess` grants everything except IAM and Organizations;
`AWSBillingReadOnlyAccess` lets the user see cost/billing (paired with the console
billing-access toggle in `../../manual-steps.md`).

**Why a group, not policies on the user directly.** The policies attach to a
`daily-drivers` group and the user joins it, rather than attaching to the user.
This is the AWS-recommended pattern: the group's permissions live in one named place,
so what a daily driver can do is defined once and stays consistent. Even with a
single user today, it means a second scoped identity later just joins the group and
inherits the same access, with no drift.

The user is tagged `ManagedBy` (create time, and reconciled on `--update`); see
[Resource tags](../../configuration.md#resource-tags).

## Manual follow-ups (console)

The script deliberately does not set a password or enrol MFA — nothing sensitive
is generated or written to a run log. After it creates the user, in the console
under [IAM Users](https://console.aws.amazon.com/iam/home#/users):

1. **Set a console password.** Open the user, Security credentials, enable console
   access, set a password. Copy it straight into your password manager. When the
   console offers a credentials file to download, skip it: the password is already
   in your manager, and a downloaded file is one more copy to leak.
2. **Enrol the user's MFA.** Security credentials, assign an MFA device. The
   baseline reads the enrolled device's ARN itself on the next admin-role run (you
   do not copy it anywhere).

## Switch to it

Once the daily driver has a password and MFA, **use it instead of root** for
everyday work:

- Re-authenticate as the daily-driver user, e.g. `aws login` signed in as that
  user, or set up a named CLI profile for it.
- Reserve root and the admin role for the rare consequential tasks that
  genuinely need them.

## Verify

```
aws iam get-user --user-name <DAILY_DRIVER_USER>
aws iam list-groups-for-user --user-name <DAILY_DRIVER_USER>
```
The user exists and belongs to the group; the group carries the two policies.
