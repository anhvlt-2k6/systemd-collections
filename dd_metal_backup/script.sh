#!/bin/bash
set -euo pipefail

# safer error handler: prints exit code, line, and last command; removes tmp file if present
TMP_FILE=""
error_exit() {
    local rc=${1:-$?}
    local line=${2:-$LINENO}
    echo "[$(date -Iseconds)] ERROR: exit code ${rc} at line ${line}. Last command: \"${BASH_COMMAND}\"" >&2
    if [ -n "$TMP_FILE" ] && [ -f "$TMP_FILE" ]; then
        echo "Removing partial file: $TMP_FILE" >&2
        rm -f "$TMP_FILE" || true
    fi
    exit "$rc"
}
trap 'error_exit $? $LINENO' ERR INT TERM

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root" >&2
    exit 1
fi

# required commands
for cmd in dd date gzip; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "$cmd is required to run!" >&2
        exit 1
    fi
done

DATE=$(date +"%Y-%m-%d")
TARGET_DEVICE="nvme0n1p4"
BACKUP_DEST="/mnt/dc01_backup"
BACKUP_DEVICE="/dev/$TARGET_DEVICE"

# sanity checks
if [ ! -b "$BACKUP_DEVICE" ]; then
    echo "Backup device $BACKUP_DEVICE does not exist or is not a block device." >&2
    exit 1
fi

if [ ! -d "$BACKUP_DEST" ]; then
    echo "Backup destination $BACKUP_DEST does not exist. Attempting to create it..." >&2
    mkdir -p "$BACKUP_DEST"
fi

if [ ! -w "$BACKUP_DEST" ]; then
    echo "Backup destination $BACKUP_DEST is not writable." >&2
    exit 1
fi

# Clean-up Backup Destination (Only one copy allowed) — safer: remove only matching files in BACKUP_DEST
echo "Cleaning old backups in $BACKUP_DEST..."
rm -f "$BACKUP_DEST"/*.img.gz || true

# prepare temp file path
TMP_FILE="$BACKUP_DEST/${TARGET_DEVICE}_${DATE}.img.gz.tmp"
FINAL_FILE="$BACKUP_DEST/${TARGET_DEVICE}_${DATE}.img.gz"

echo "Starting backup of $BACKUP_DEVICE -> $FINAL_FILE"
# Use status=progress if dd supports it; quote variables to avoid globbing/word-splitting
dd if="$BACKUP_DEVICE" conv=sync,noerror bs=64K status=progress | gzip -c > "$TMP_FILE"
# ensure gzip finished successfully (pipe failure would have triggered ERR because of set -e)
mv -f "$TMP_FILE" "$FINAL_FILE"
TMP_FILE=""

echo "Backup completed successfully: $FINAL_FILE"
exit 0
