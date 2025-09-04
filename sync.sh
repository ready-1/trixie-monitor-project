#!/bin/zsh
# Breadcrumb: [2025-09-03 20:38 EDT | 1743989880] Sync Script for Trixie Monitor Project
# Description: Copies specified scripts from Mac to Debian Trixie VM for development and pushes to GitHub.
# Hardcoded paths used per user request. Includes passwordless SSH setup (manual key management supported).
# Pushes to GitHub 'main' branch for visibility, no fetching. Continues on clean Git tree.
# Usage: ./sync.sh <target-ip> [--dry-run] [--no-key]
# Example: ./sync.sh 192.168.99.176 --dry-run
# Requirements: scp, ssh-copy-id, git, SSH access to target, sshkeys file
# Notes: Uses zsh for macOS compatibility. Files listed explicitly for replicability. Logs to sync.log.

set -e  # Exit on error

clear

# Hardcoded variables (update as needed)
TARGET_IP="$1"
DRY_RUN="$2"
NO_KEY="$3"
VM_USER="monitor"
VM_DEST="/home/monitor/"
LOCAL_REPO="$(pwd)"  # Assumes run from repo root
LOG_FILE="$LOCAL_REPO/sync.log"
SSH_KEY="/Users/bob/.ssh/id_bob_ed25519"  # ed25519 key
SCP="scp"  # System scp on PATH
SSH_COPY_ID="ssh-copy-id"  # System ssh-copy-id on PATH

# Files to sync (update for future phases)
FILES=(
    "phase1_setup.sh"
    "phase2_setup.sh"
    "phase3_setup.sh"
    "config.sh"
    "sudoit.sh"
    "doit.sh"
    "m4300-cli-manual-repaired.pdf"
    "phase3_graylog_journal_fix.sh"
)

# Function for formatted section output
print_section() {
    echo "----------------------------------------"
    echo "$1"
    echo "----------------------------------------"
}

# Start logging and output
exec > >(tee -a "$LOG_FILE") 2>&1
print_section "Starting sync at $(date '+%Y-%m-%d %H:%M:%S')"

# Validate sshkeys file
print_section "Checking sshkeys file"
if [[ -f "sshkeys" ]]; then
    source sshkeys || { echo "Error: Failed to source sshkeys."; exit 1 }
else
    echo "Error: sshkeys file not found in $LOCAL_REPO."
    exit 1
fi

# Validate target IP
if [[ -z "$TARGET_IP" ]]; then
    echo "Error: Target IP required."
    echo "Usage: $0 <target-ip> [--dry-run] [--no-key]"
    exit 1
fi

# Verify SSH connectivity
print_section "Verifying connectivity to $TARGET_IP"
if ssh -o ConnectTimeout=5 "$VM_USER@$TARGET_IP" true 2>/dev/null; then
    echo "SSH connectivity confirmed."
else
    echo "Error: Cannot connect to $TARGET_IP via SSH."
    exit 1
fi

# Validate SSH key for copy-id
if [[ "$NO_KEY" != "--no-key" ]]; then
    print_section "Checking SSH key"
    if [[ ! -f "$SSH_KEY" ]]; then
        echo "Error: SSH key $SSH_KEY not found."
        exit 1
    fi
    # Add SSH key to VM
    print_section "Adding SSH key to $TARGET_IP"
    if "$SSH_COPY_ID" -i "$SSH_KEY" "$VM_USER@$TARGET_IP"; then
        echo "SSH key added successfully."
    else
        echo "Error: Failed to add SSH key."
        exit 1
    fi
else
    print_section "Skipping SSH key addition (--no-key specified)"
fi

# Validate files exist
print_section "Checking local files"
MISSING_FILES=0
for file in "${FILES[@]}"; do
    if [[ ! -f "$file" ]]; then
        echo "Error: File $file not found."
        MISSING_FILES=1
    fi
done
if [[ "$MISSING_FILES" -eq 1 ]]; then
    echo "Error: One or more files missing. Aborting."
    exit 1
fi
echo "All ${#FILES[@]} files found."

# Sync files to VM
print_section "Copying files to $VM_USER@$TARGET_IP:$VM_DEST"
if [[ "$DRY_RUN" = "--dry-run" ]]; then
    echo "Dry-run: Would sync ${#FILES[@]} files:"
    echo "  %-30s %s" "File" "Status"
    echo "  %-30s %s" "----" "------"
    for file in "${FILES[@]}"; do
        echo "  %-30s %s" "$file" "Ready"
    done
else
    for file in "${FILES[@]}"; do
        if "$SCP" "$file" "$VM_USER@$TARGET_IP:$VM_DEST"; then
            echo "  Copied $file successfully."
        else
            echo "Error: Failed to copy $file."
            exit 1
        fi
    done
fi

# Push to GitHub
print_section "Pushing to GitHub from $LOCAL_REPO"
if [[ -d ".git" ]]; then
    git add . || echo "Warning: git add failed (no changes?)."
    if git diff --staged --quiet; then
        echo "No changes to commit, continuing..."
    else
        git commit -m "Auto commit $(date '+%Y-%m-%d %H:%M:%S')" || echo "Nothing to commit."
    fi
    if git push origin main; then
        echo "Push successful."
    else
        echo "Error: git push failed."
        exit 1
    fi
else
    echo "Error: $LOCAL_REPO is not a Git repository."
    exit 1
fi

print_section "Sync completed at $(date '+%Y-%m-%d %H:%M:%S')"
echo "Log saved to $LOG_FILE"
