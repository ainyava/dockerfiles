#!/usr/bin/env bash
set -euo pipefail

# Required env vars:
#   BACKUP_SOURCE   path where the PVC is mounted inside the job (e.g. /data)
#   RCLONE_REMOTE   e.g. s3:my-bucket/pvc-backups  (any rclone remote:path)
# Optional:
#   BACKUP_NAME     prefix for the archive name (default: pvc)

: "${BACKUP_SOURCE:?BACKUP_SOURCE is required}"
: "${RCLONE_REMOTE:?RCLONE_REMOTE is required}"
BACKUP_NAME="${BACKUP_NAME:-pvc}"

if [ ! -d "${BACKUP_SOURCE}" ]; then
  echo "ERROR: BACKUP_SOURCE '${BACKUP_SOURCE}' is not a directory" >&2
  exit 1
fi

DATE=$(date -u +%Y-%m-%d)
ARCHIVE="/tmp/${BACKUP_NAME}-backup-${DATE}.tar.gz"

echo "Archiving ${BACKUP_SOURCE} -> ${ARCHIVE}..."
tar \
  --create \
  --gzip \
  --file="${ARCHIVE}" \
  --directory="${BACKUP_SOURCE}" \
  .

echo "Archive written to ${ARCHIVE} ($(du -sh "${ARCHIVE}" | cut -f1))"

echo "Uploading to ${RCLONE_REMOTE}..."
rclone copy "${ARCHIVE}" "${RCLONE_REMOTE}" --progress

echo "Upload complete. Cleaning up..."
rm -f "${ARCHIVE}"

echo "Done."
