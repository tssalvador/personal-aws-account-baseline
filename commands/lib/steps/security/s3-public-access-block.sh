#!/usr/bin/env bash
# Step — S3 account public-access block. See docs/steps/security/s3-public-access-block.md.
[ "${ENABLE_S3_BLOCK:-false}" = "true" ] || { log "s3-block: disabled, skipping"; record s3-block disabled-in-config "ENABLE_S3_BLOCK=false"; return 0; }

step "S3 account public-access block"
if read_aws s3control get-public-access-block --account-id "$ACCOUNT_ID" >/dev/null 2>&1; then
  ok "account-level block already present — skipping"
  record s3-block already-present "account-level block already on"
else
  log "enabling all four account-level block flags"
  run_aws s3control put-public-access-block --account-id "$ACCOUNT_ID" \
    --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
  if [ "$APPLY" = "true" ]; then record s3-block applied "all 4 block flags on"; else record s3-block would-apply "no account-level block yet"; fi
fi
