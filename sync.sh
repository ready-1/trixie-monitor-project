#!/bin/bash
# sync.sh: Syncs project files to Debian Trixie server
# Purpose: Copy scripts to VM/server for Phase 1 setup
# Usage: ./sync.sh <target-ip> [--dry-run]
# Example: ./sync.sh 192.168.99.91 --dry-run
# Breadcrumb: [PHASE1_SYNC_SH_20250830] Sync script with dry-run
# Requirements: rsync, SSH access to target

set -e

TARGET_IP="$1"
DRY_RUN="$2"
RSYNC_FLAGS="-avz --exclude='.git' --exclude='config.sh'"

if [ -z "$TARGET_IP" ]; then
    echo "Error: Target IP required."
    echo "Usage: $0 <target-ip> [--dry-run]"
    exit 1
fi

# Verify SSH connectivity
if ! ping -c 1 "$TARGET_IP" >/dev/null 2>&1; then
    echo "Error: Cannot ping $TARGET_IP."
    exit 1
fi

# Sync files
if [ "$DRY_RUN" = "--dry-run" ]; then
    rsync $RSYNC_FLAGS --dry-run ./ "monitor@$TARGET_IP:/home/fuse/"
else
    rsync $RSYNC_FLAGS ./ "monitor@$TARGET_IP:/home/fuse/"
fi

echo "Sync to $TARGET_IP completed."
