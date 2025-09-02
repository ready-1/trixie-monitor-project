#!/bin/bash
# phase3_graylog_journal_fix.sh: Reduce journal size for low-space dev; scale up for prod.
# Breadcrumb: [PHASE3_GRAYLOG_JOURNAL_SPACE_FIX_20250902]
# Research: Graylog docs/community confirm reduce max_size or add space. Default 5GB; min viable ~1GB for low load. Prod: 5-12GB, match CPU cores.
# Best Practice: Prefer space allocation (LVM/extend) over reduce. Simplicity: Config edit > dir move (avoids perms issues).
# Compatibility: Graylog 6.0.6+; no integration breaks (e.g., with Nginx proxy).
# Idempotency: Check current size/free; apply if needed.
# Usage: ./phase3_graylog_journal_fix.sh [--prod]  # --prod sets 10GB (assumes space added).

set -euo pipefail
source /home/monitor/config.sh  # Load vars; assume GRAYLOG_LOG_SIZE for logs, add GRAYLOG_JOURNAL_SIZE="10G" for future.

JOURNAL_DIR="/var/lib/graylog-server/journal"
CONF="/etc/graylog/server/server.conf"
TARGET_SIZE="2gb"  # Dev default; reduce to fit ~2.2GB free.
if [ "${1:-}" = "--prod" ]; then TARGET_SIZE="10gb"; fi  # Prod: Increase if space added.

# Check space (MB)
FREE_MB=$(df -m "$JOURNAL_DIR" | tail -1 | awk '{print $4}')
if [ "$FREE_MB" -ge 5120 ]; then echo "Space sufficient; no fix needed."; exit 0; fi

# Backup conf
sudo cp "$CONF" "$CONF.bak.$(date +%Y%m%d)"

# Set max_size (uncomment/add if needed)
if grep -q '^message_journal_max_size' "$CONF"; then
  sudo sed -i "s/^message_journal_max_size.*/message_journal_max_size = $TARGET_SIZE/" "$CONF"
else
  echo "message_journal_max_size = $TARGET_SIZE" | sudo tee -a "$CONF"
fi

# Ensure dir/ownership (package should handle, but idempotent)
sudo mkdir -p "$JOURNAL_DIR"
sudo chown -R graylog:graylog "$JOURNAL_DIR"
sudo chmod 750 "$JOURNAL_DIR"

# Restart & verify
sudo systemctl restart graylog-server
sleep 10  # Wait for startup
if sudo systemctl status graylog-server | grep -q 'Active: active (running)'; then
  echo "Graylog running. Test: curl -u admin:$MONITOR_PASS http://127.0.0.1:9000/api/system"
  echo "Proxy: curl http://127.0.0.1/graylog/api/system"
else
  echo "Failed; check sudo journalctl -u graylog-server"
fi
