# Admin role (assumable with MFA)

**Script:** `admin-role.sh` · **Cost:** free · **On by default** (`CREATE_ADMIN_ROLE=true`)

## Why

The admin identity is an **assumable role** with `AdministratorAccess`, not a
standing admin user. Its trust policy requires MFA, so you assume it only for the
rare IAM/Org-level tasks, get temporary credentials that expire, then drop back to
the daily driver. This keeps those actions off root and leaves no standing admin
login.

## What the script does

On by default (opt out with `CREATE_ADMIN_ROLE=false`), this script performs four
actions:

1. **Admin IAM role creation** (`ADMIN_ROLE`, default `admin-role`): created with
   `AdministratorAccess`, a trust policy requiring MFA, and a max session duration
   (`ADMIN_MAX_SESSION_DURATION`, default 3600s = 1h, AWS range 3600..43200). An
   existing role is never modified, so the cap applies only at creation.
2. **Admin IAM group creation** (`ADMIN_GROUP`, default `admins`): holds the
   `sts:AssumeRole` grant on the role. Keeping "who may elevate to admin" on its own
   group, separate from the `daily-drivers` group, means everyday access and admin
   elevation are granted independently.
3. **Add daily-driver user to the IAM admin group:** the `DAILY_DRIVER_USER` joins
   the admins group, so it can assume the role (with MFA).
4. **Write / reconcile a CLI profile** (`WRITE_ADMIN_PROFILE=true`,
   `ADMIN_PROFILE_NAME` default `admin`): writes a `[profile <name>]` stub to
   `~/.aws/config` so `aws --profile <name>` auto-assumes the role. It fills
   `mfa_serial` from the daily driver's enrolled MFA device when one exists; at
   bootstrap (before MFA is enrolled) it writes a placeholder. This is
   self-healing across runs: if the profile already has the placeholder and MFA has
   since been enrolled, a later run updates just that line in place. An existing
   profile with a real serial is left alone, and no other profile is ever touched.
   See "Using it" below.

If the daily driver is not an IAM user, this step is skipped.
```
aws iam create-role --role-name <ADMIN_ROLE> --assume-role-policy-document <TRUST>
aws iam attach-role-policy --role-name <ADMIN_ROLE> \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
aws iam create-group --group-name <ADMIN_GROUP>
aws iam put-group-policy --group-name <ADMIN_GROUP> \
  --policy-name assume-<ADMIN_ROLE> --policy-document <ASSUME_GRANT>
aws iam add-user-to-group --user-name <DAILY_DRIVER_USER> --group-name <ADMIN_GROUP>
```
The trust policy lets any IAM user in the account assume the role if they have MFA,
but the `sts:AssumeRole` permission is granted only to members of the admins group 
(This is done on the permission side because IAM has no way to name a group in a
trust policy.)

The role is tagged `ManagedBy` (create time, and reconciled on `--update`); see
[Resource tags](../../configuration.md#resource-tags).


## Using it

By default (`WRITE_ADMIN_PROFILE=true`) the step writes this **named role profile**
to `~/.aws/config` for you, so the CLI does the assume-role and prompts for your MFA
code automatically. If you set `WRITE_ADMIN_PROFILE=false`, add it yourself:
```
[profile admin]
role_arn = arn:aws:iam::<ACCOUNT_ID>:role/<ADMIN_ROLE>
source_profile = default
mfa_serial = arn:aws:iam::<ACCOUNT_ID>:mfa/<DAILY_DRIVER_MFA>
duration_seconds = <ADMIN_SESSION_DURATION>
```
- `source_profile` — the credentials used to request the assume. `aws --profile
  admin` always assumes the role from this profile, not from whatever you happen to
  be "logged in as"; there is no implicit current user. The written stub uses
  `default`, assuming your `[default]` profile is the daily driver. If your daily
  driver is a different profile, change `source_profile` to name it.
- `mfa_serial` — your MFA device ARN; its presence makes the CLI prompt for a code.
  The step fills this in from your enrolled device when it can; if MFA is not
  enrolled yet, it writes a placeholder and fills in the real ARN on a later run
  once you have enrolled (or you can edit the one line yourself).
- `duration_seconds` — how long each assumed session lasts
  (`ADMIN_SESSION_DURATION`, default 1800s = 30m, up to `ADMIN_MAX_SESSION_DURATION`).

Then you never type `assume-role`; just prefix commands with the profile:
```
aws --profile admin <command>
```
The first call per session prompts `Enter MFA code for …`, assumes the role, and
caches the temporary admin credentials (for `ADMIN_SESSION_DURATION`). Later commands
reuse the cache until it expires. Without a valid code the assume is denied.

**In the console (no CLI equivalent):** signed in as the daily driver, use the
account menu's **Switch role** and enter the account id and role name (`admin-role`).
Because your console sign-in is already MFA-authenticated, no extra token is needed.
For one-click switching, bookmark (replacing the values accordingly):
`https://signin.aws.amazon.com/switchrole?account=<ACCOUNT_ID>&roleName=<ADMIN_ROLE>&displayName=Admin`

**Fallback (no profile):** the underlying call the profile automates is
`aws sts assume-role --role-arn arn:aws:iam::<ACCOUNT_ID>:role/<ADMIN_ROLE>
--role-session-name admin --serial-number <DAILY_DRIVER_MFA_ARN> --token-code <6-digit>`,
which returns temporary credentials you export manually. Prefer the profile.


## Notes / order
- Creating the role needs admin, so it's part of the root bootstrap (run alongside
  the daily-driver step, before you switch off root). The root guard exempts
  `--only admin-role` for this reason.
- The daily driver's **MFA must be enrolled** before assume-role will work (the
  `--serial-number` is that device). Enrol it in the daily-driver console follow-up
  first.


## Verify
```
aws iam get-role --role-name <ADMIN_ROLE>
aws iam get-group-policy --group-name <ADMIN_GROUP> --policy-name assume-<ADMIN_ROLE>
aws iam get-group --group-name <ADMIN_GROUP>
```
`get-group` lists the daily driver as a member. Then, as the daily driver with MFA,
confirm `aws sts assume-role ...` returns credentials (and is denied without
`--token-code`).
