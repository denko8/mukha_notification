#!/usr/bin/env bash
# Restore into a SEPARATE temporary database, never into the working database.
set -euo pipefail
file="${1:?Usage: bash scripts/restore-check.sh backups/filename.dump}"
test -s "$file"
name="restore_check_$(date +%s)_$$"
dc=(docker compose -f compose.vps.yaml)
"${dc[@]}" exec -T db createdb -U smartnotes "$name"
trap '"${dc[@]}" exec -T db dropdb -U smartnotes "$name"' EXIT
"${dc[@]}" exec -T db pg_restore -U smartnotes -d "$name" --exit-on-error < "$file"
"${dc[@]}" exec -T db psql -U smartnotes -d "$name" -v ON_ERROR_STOP=1 -c 'SELECT version_num FROM alembic_version; SELECT count(*) FROM users; SELECT count(*) FROM notes;'
printf 'Restore check passed in isolated database.\n'
