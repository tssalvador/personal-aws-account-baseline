# IAM permission scoping

Some actions, like creating IAM users or changing account and Organizations
policies, need `AdministratorAccess` (or specific IAM permissions) that fall outside
`PowerUserAccess`, the managed policy that strikes a good balance for an individual
account owner's day-to-day work. Rather than running everything as an administrator,
this baseline creates an admin role you
[assume](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_manage-assume.html)
only when needed.


## Daily-driver identity + Admin role

- **Admin role (assumable with MFA):** rather than a standing admin user, create a
  role with `AdministratorAccess` whose trust policy requires MFA. The right to
  assume it is held by a dedicated `admins` group; the daily driver is a member and
  assumes the role only when needed (`aws sts assume-role` with an MFA token),
  getting temporary credentials that expire. Keeping the assume grant on its own
  group (not the `daily-drivers` group) means "can elevate to admin" is decided by
  admins-group membership, independent of everyday access. See
  `steps/security/admin-role.md`.
- **Daily-driver identity:** scoped to everyday work. Starts from `PowerUserAccess`
  (everything except IAM/Org) plus `AWSBillingReadOnlyAccess`, and can be scoped
  down further. See `steps/security/daily-driver.md`.


## IAM user permissions through groups

Permissions for IAM users are attached to an **IAM group** rather than directly to
the daily-driver user. This is the
[AWS-recommended approach](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
and paves the way for adding more users later if your usage pattern changes (for
example, a family member).
