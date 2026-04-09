#!/usr/bin/env bash
set -euo pipefail

# Configuration
ENDPOINT="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="auto"

list_backups() {
    echo "📂 Available Backups (Newest First):"
    aws s3api list-objects-v2 --endpoint-url "$ENDPOINT" --bucket "$R2_BUCKET" --prefix "backups/" \
        --query 'reverse(sort_by(Contents, &LastModified))[].[Key, Size, LastModified]' --output table
}

restore_backup() {
    local DUMP_KEY="${1:-}"
    
    # Auto-detect latest if no key provided
    if [ -z "$DUMP_KEY" ]; then
        echo "🔍 No key provided. Searching for latest backup..."
        DUMP_KEY=$(aws s3api list-objects-v2 --endpoint-url "$ENDPOINT" --bucket "$R2_BUCKET" --prefix "backups/" \
            --query 'reverse(sort_by(Contents, &LastModified)).Key' --output text)
    fi

    echo "🚀 Restoring: s3://$R2_BUCKET/$DUMP_KEY"
    read -p "⚠️  This will WIPE your database. Type 'YES' to proceed: " CONFIRM
    [[ "$CONFIRM" != "YES" ]] && echo "Aborted." && exit 1

    echo "🧹 Wiping public schema..."
    psql "$DATABASE_URL" -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"

    echo "📥 Streaming and restoring..."
    # Handles .sql.gz and .dump.gz automatically
    if [[ "$DUMP_KEY" == *.sql.gz ]]; then
        aws s3 cp "s3://$R2_BUCKET/$DUMP_KEY" - --endpoint-url "$ENDPOINT" --quiet | gunzip | psql "$DATABASE_URL"
    else
        aws s3 cp "s3://$R2_BUCKET/$DUMP_KEY" - --endpoint-url "$ENDPOINT" --quiet | gunzip | pg_restore -d "$DATABASE_URL" --no-owner --no-privileges
    fi

    echo "✅ Success! Database is restored."
}

# Simple Menu
case "${1:-}" in
    list)    list_backups ;;
    restore) restore_backup "${2:-}" ;;
    *)       echo "Usage: ./manage.sh [list | restore <optional-key>]" ;;
esac
