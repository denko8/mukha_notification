#!/usr/bin/env bash
# Run from backend/ on the VPS. Copy encrypted backups off the VPS separately.
set -euo pipefail
umask 077
mkdir -p backups
file="backups/smartnotes-$(date -u +%Y%m%dT%H%M%SZ)-$$.dump"
trap 'rm -f "$file.partial"' EXIT
docker compose -f compose.vps.yaml exec -T db pg_dump -U smartnotes -d smartnotes -Fc > "$file.partial"
test -s "$file.partial"
mv "$file.partial" "$file"
printf 'Backup saved: %s\n' "$file"
