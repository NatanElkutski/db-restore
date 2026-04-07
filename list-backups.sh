#!/usr/bin/env bash
#
# list-backups.sh — List all dumps in the R2 backups/ folder, newest first.
#
# Required env: R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET
#

set -euo pipefail

: "${R2_ACCOUNT_ID:?R2_ACCOUNT_ID is not set}"
: "${R2_ACCESS_KEY_ID:?R2_ACCESS_KEY_ID is not set}"
: "${R2_SECRET_ACCESS_KEY:?R2_SECRET_ACCESS_KEY is not set}"
: "${R2_BUCKET:?R2_BUCKET is not set}"

ENDPOINT="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="auto"

PREFIX="${1:-backups/}"

echo "Listing s3://${R2_BUCKET}/${PREFIX} (newest first)"
echo "-----------------------------------------------------------"

aws s3api list-objects-v2 \
  --endpoint-url "$ENDPOINT" \
  --bucket "$R2_BUCKET" \
  --prefix "$PREFIX" \
  --query 'reverse(sort_by(Contents, &LastModified))[].[LastModified, Size, Key]' \
  --output table
