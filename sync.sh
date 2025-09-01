#!/bin/zsh
# sync.sh: Syncs project files to Debian Trixie server
# Purpose: Copy scripts to VM/server for Phase 1 setup, with optional SSH key addition
# Usage: ./sync.sh <target-ip> [--dry-run] [--no-key]
# Example: ./sync.sh 192.168.99.176 --dry-run
# Breadcrumb: [PHASE1_SYNC_SH_SCP_20250831] Reverted to scp for simplicity, no remote rsync needed
# Requirements: scp, SSH access to target
# Notes: scp for one-shot initial sync (simple, no remote dependency). Files in array for replicability. --dry-run lists files. --no-key skips key addition. Explicit paths avoided (system scp on PATH).

set -e

SCP="scp"  # System scp on PATH

SSH_COPY_ID="ssh-copy-id"  # Assume on PATH
SSH_KEY="/Users/bob/.ssh/id_bob_ed25519"  # ed25519 key

TARGET_IP="$1"
DRY_RUN="$2"
NO_KEY="$3"

if [ -z "$TARGET_IP" ]; then
    echo "Error: Target IP required."
    echo "Usage: $0 <target-ip> [--dry-run] [--no-key]"
    exit 1
fi

# Verify SSH connectivity
if ! ping -c 1 "$TARGET_IP" >/dev/null 2>&1; then
    echo "Error: Cannot ping $TARGET_IP."
    exit 1
fi

# Optional SSH key addition
if [ "$NO_KEY" != "--no-key" ]; then
    echo "Adding SSH key to $TARGET_IP..."
    "$SSH_COPY_ID" -i "$SSH_KEY" monitor@$TARGET_IP
else
    echo "Skipping SSH key addition."
fi

# Files to sync (expand array for future phases)
FILES=("phase1_setup.sh" "phase2_setup.sh" "config.sh")

# Sync files
if [ "$DRY_RUN" = "--dry-run" ]; then
    echo "Dry-run: Would sync to monitor@$TARGET_IP:/home/monitor/"
    for file in "${FILES[@]}"; do
        echo " - $file"
    done
else
    for file in "${FILES[@]}"; do
        "$SCP" "$file" "monitor@$TARGET_IP:/home/monitor/"
    done
fi

echo "Sync to $TARGET_IP completed $(date)."
