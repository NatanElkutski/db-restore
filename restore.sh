#!/usr/bin/env bash
#
# restore.sh — Restore a Postgres dump from Cloudflare R2 into a Postgres DB.
#
# Usage:
#   ./restore.sh <dump-key> [--force]
#
# Examples:
#   ./restore.sh backups/2026-04-07_23-00.sql.gz
#   ./restore.sh backups/latest.dump --force
#
# Required environment variables:
#   R2_ACCOUNT_ID          Cloudflare account ID
#   R2_ACCESS_KEY_ID       R2 S3-compatible access key
#   R2_SECRET_ACCESS_KEY   R2 S3-compatible secret key
#   R2_BUCKET              R2 bucket name (e.g. pwrdesk-db-backup)
#   DATABASE_URL           Target Postgres connection string
#
# Supported dump formats (auto-detected):
#   *.sql            plain SQL           -> psql
#   *.sql.gz         gzipped plain SQL   -> gunzip | psql
#   *.dump           pg_dump -Fc custom  -> pg_restore
#   *.dump.gz        gzipped custom      -> gunzip | pg_restore
#

set -euo pipefail

# ---------- args ----------
if [ $# -lt 1 ]; then
  echo "Usage: $0 <dump-key> [--force]"
  echo "Example: $0 backups/2026-04-07_23-00.sql.gz"
  exit 1
fi

DUMP_KEY="$1"
FORCE="${2:-}"

# ---------- env check ----------
: "${R2_ACCOUNT_ID:?R2_ACCOUNT_ID is not set}"
: "${R2_ACCESS_KEY_ID:?R2_ACCESS_KEY_ID is not set}"
: "${R2_SECRET_ACCESS_KEY:?R2_SECRET_ACCESS_KEY is not set}"
: "${R2_BUCKET:?R2_BUCKET is not set}"
: "${DATABASE_URL:?DATABASE_URL is not set}"

command -v aws   >/dev/null || { echo "ERROR: aws CLI not installed"; exit 1; }
command -v psql  >/dev/null || { echo "ERROR: psql not installed"; exit 1; }

ENDPOINT="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="auto"

# ---------- confirm destructive action ----------
# Mask credentials in the URL for display
SAFE_URL=$(echo "$DATABASE_URL" | sed -E 's#(://[^:]+:)[^@]+(@)#\1****\2#')

cat <<EOF

==========================================================
  WARNING: DESTRUCTIVE OPERATION
==========================================================
  Dump source : s3://${R2_BUCKET}/${DUMP_KEY}
  Target DB   : ${SAFE_URL}

  This will DROP the public schema and replace all data.
  Any data not in the dump will be PERMANENTLY LOST.
==========================================================

EOF

if [ "$FORCE" != "--force" ]; then
  read -r -p "Type 'RESTORE' to continue: " CONFIRM
  if [ "$CONFIRM" != "RESTORE" ]; then
    echo "Aborted."
    exit 1
  fi
fi

# ---------- verify object exists ----------
echo "[1/4] Checking object exists in R2..."
if ! aws s3api head-object \
      --endpoint-url "$ENDPOINT" \
      --bucket "$R2_BUCKET" \
      --key "$DUMP_KEY" >/dev/null 2>&1; then
  echo "ERROR: object not found: s3://${R2_BUCKET}/${DUMP_KEY}"
  echo "Run ./list-backups.sh to see available dumps."
  exit 1
fi

# ---------- detect format ----------
echo "[2/4] Detecting dump format..."
GZIPPED=false
FORMAT=""

case "$DUMP_KEY" in
  *.sql.gz)   GZIPPED=true;  FORMAT="plain" ;;
  *.dump.gz)  GZIPPED=true;  FORMAT="custom" ;;
  *.sql)      GZIPPED=false; FORMAT="plain" ;;
  *.dump)     GZIPPED=false; FORMAT="custom" ;;
  *)
    echo "ERROR: cannot detect format from filename: $DUMP_KEY"
    echo "Expected extension: .sql, .sql.gz, .dump, or .dump.gz"
    exit 1
    ;;
esac

echo "        format: $FORMAT  gzipped: $GZIPPED"

# ---------- reset target schema ----------
echo "[3/4] Dropping and recreating public schema..."
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<'SQL'
DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;
GRANT ALL ON SCHEMA public TO public;
SQL

# ---------- stream restore ----------
echo "[4/4] Streaming dump from R2 and restoring..."

# Build the read pipeline
read_cmd=( aws s3 cp "s3://${R2_BUCKET}/${DUMP_KEY}" - --endpoint-url "$ENDPOINT" --quiet )

if [ "$FORMAT" = "plain" ]; then
  if [ "$GZIPPED" = true ]; then
    "${read_cmd[@]}" | gunzip | psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q
  else
    "${read_cmd[@]}" | psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q
  fi
else
  command -v pg_restore >/dev/null || { echo "ERROR: pg_restore not installed"; exit 1; }
  if [ "$GZIPPED" = true ]; then
    "${read_cmd[@]}" | gunzip | pg_restore --clean --if-exists --no-owner --no-privileges -d "$DATABASE_URL"
  else
    "${read_cmd[@]}" | pg_restore --clean --if-exists --no-owner --no-privileges -d "$DATABASE_URL"
  fi
fi

echo ""
echo "✅ Restore complete."
