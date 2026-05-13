#!/usr/bin/env bash
set -euo pipefail

: "${PGHOST:?PGHOST is required}"
: "${PGPORT:=5432}"
: "${PGUSER:?PGUSER is required}"
: "${PGPASSWORD:?PGPASSWORD is required}"
: "${RCLONE_REMOTE:?RCLONE_REMOTE is required}"

export PGPASSWORD

DATE=$(date -u +%Y-%m-%d)
DUMP_FILE="/tmp/postgres-backup-${DATE}.sql.gz"

echo "Starting pg_dumpall backup from ${PGHOST}:${PGPORT} as ${PGUSER}..."
pg_dumpall \
  --host="${PGHOST}" \
  --port="${PGPORT}" \
  --username="${PGUSER}" \
  --clean \
  --if-exists \
  | gzip > "${DUMP_FILE}"

echo "Dump written to ${DUMP_FILE} ($(du -sh "${DUMP_FILE}" | cut -f1))"

echo "Uploading to ${RCLONE_REMOTE}..."
rclone copy "${DUMP_FILE}" "${RCLONE_REMOTE}" --progress

echo "Upload complete. Cleaning up..."
rm -f "${DUMP_FILE}"

echo "Done."
