# S3 account public-access block

**Script:** `s3-public-access-block.sh` · **Cost:** free

## Why

A publicly-readable bucket is one of the most common causes of accidental data
exposure: anyone on the internet can list and download its objects, so a
misconfigured bucket can leak backups, logs, or personal files with no warning. 

Since April 2023 AWS enables Block Public Access on each *new* bucket by default
(and disables ACLs), so fresh buckets start private. That is per-bucket, though. The
account-level setting this step turns on is the stronger, catch-all layer: it covers
buckets created before that change and can't be silently undone bucket-by-bucket.

Making a bucket public is still possible when you genuinely intend it (for example,
hosting a static website). In that case you'd disable this setting and make the
specific bucket public.


## What the script does

```
aws s3control put-public-access-block --account-id <ACCOUNT_ID> \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

## Verify

```
aws s3control get-public-access-block --account-id <ACCOUNT_ID>
```
All four flags `true` at the account level.
