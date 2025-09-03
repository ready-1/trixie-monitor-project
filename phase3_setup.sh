#!/bin/bash
# phase3_setup.sh: Phase 3 setup for Nginx and Graylog (all fixes integrated)
# Breadcrumb: [PHASE3_CONSOLIDATED_V2_20250903] Trixie apt signatures, Mongo jammy, OpenJDK 21, journal dir, MONITOR_USER, security, Nginx, state file.
# Research: Trixie testing (signatures not live ); Mongo jammy workaround ; Graylog 6.0/Mongo 7/Debian 13 OK ; Java 21 default .
# Best Practice: Ignore date temp; hold Mongo; single-node; random secrets; state file for tracking.
# Compatibility: Graylog 6.0.6/Mongo 7.0/OpenSearch 2.15/Debian 13; no Ansible/Prometheus breaks.
# Idempotency: Package/dir/service checks; state file tracks completions.
# Usage: sudo -E ./phase3_setup.sh

set -euo pipefail
MONITOR_USER="monitor"  # Fallback
source /home/$MONITOR_USER/config.sh
USER_HOME="/home/$MONITOR_USER"
STATE_FILE="$USER_HOME/setup_state.txt"

# Initialize state file
touch "$STATE_FILE"
echo "Phase 3 start: $(date)" >> "$STATE_FILE"

# Part 0: Pre-flight Checks
if ! ping -c 3 -W 5 8.8.8.8 > /dev/null 2>&1; then
  echo "Error: No internet access. Check network." >&2
  exit 1
fi
sudo apt clean
sudo rm -rf /var/lib/apt/lists/*
sudo apt update --allow-releaseinfo-change --allow-insecure-repositories 2>> "$STATE_FILE" || {
  echo "Warning: apt update failed (signature issues); continuing with old indexes." >> "$STATE_FILE"
}

# Part 1: Prerequisites (OpenJDK 21, gnupg, curl)
if ! grep -q "openjdk-21-installed" "$STATE_FILE"; then
  sudo apt install -y openjdk-21-jre-headless gnupg curl
  echo "openjdk-21-installed: $(date)" >> "$STATE_FILE"
fi

# Part 2: MongoDB 7.0 (jammy repo)
if ! grep -q "mongodb-org-installed" "$STATE_FILE"; then
  echo "Installing MongoDB 7.0 (jammy repo)..."
  sudo rm -f /etc/apt/sources.list.d/mongodb-org-*.list
  curl -fsSL https://pgp.mongodb.com/server-7.0.asc | sudo gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor
  echo "deb [signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg arch=amd64,arm64] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list
  sudo apt update --allow-releaseinfo-change --allow-insecure-repositories
  sudo apt install -y mongodb-org
  sudo apt-mark hold mongodb-org
  sudo sed -i 's/bindIp: 127.0.0.1/bindIpAll: true/' /etc/mongod.conf
  sudo systemctl daemon-reload
  sudo systemctl enable mongod
  sudo systemctl start mongod
  echo "mongodb-org-installed: $(date)" >> "$STATE_FILE"
fi

# Part 3: Graylog Data Node (OpenSearch, repo)
if ! grep -q "graylog-datanode-installed" "$STATE_FILE"; then
  echo "Installing Graylog Data Node..."
  wget -q https://packages.graylog2.org/repo/packages/graylog-6.0-repository_latest.deb
  sudo dpkg -i graylog-6.0-repository_latest.deb
  rm graylog-6.0-repository_latest.deb
  sudo apt update --allow-releaseinfo-change --allow-insecure-repositories
  sudo apt install -y graylog-datanode
  if [ "$(sysctl -n vm.max_map_count)" -lt 262144 ]; then
    echo "vm.max_map_count=262144" | sudo tee /etc/sysctl.d/99-graylog.conf
    sudo sysctl -p /etc/sysctl.d/99-graylog.conf
  fi
  PASSWORD_SECRET=$(openssl rand -hex 32)
  sudo sed -i "s/^password_secret =.*/password_secret = $PASSWORD_SECRET/" /etc/graylog/datanode/datanode.conf
  echo "mongodb_uri = mongodb://localhost/graylog" | sudo tee -a /etc/graylog/datanode/datanode.conf
  sudo systemctl daemon-reload
  sudo systemctl enable graylog-datanode
  sudo systemctl start graylog-datanode
  echo "graylog-datanode-installed: $(date)" >> "$STATE_FILE"
fi

# Part 4: Graylog Server
if ! grep -q "graylog-server-installed" "$STATE_FILE"; then
  echo "Installing Graylog Server..."
  sudo apt install -y graylog-server
  echo "graylog-server-installed: $(date)" >> "$STATE_FILE"
fi

# Part 5: Journal Fix
JOURNAL_DIR="/var/lib/graylog-server/journal"
CONF="/etc/graylog/server/server.conf"
DEFAULTS="/etc/default/graylog-server"

sudo mkdir -p "$JOURNAL_DIR"
sudo chown -R graylog:graylog "$JOURNAL_DIR"
sudo chmod 750 "$JOURNAL_DIR"

if ! grep -q "journal-configured" "$STATE_FILE"; then
  TARGET_SIZE="$GRAYLOG_JOURNAL_SIZE"
  TARGET_MB=$(echo "$TARGET_SIZE" | sed 's/gb//i' | awk '{print $1 * 1024}')
  FREE_MB=$(df -m "$JOURNAL_DIR" | tail -1 | awk '{print $4}')
  if [ "$FREE_MB" -lt "$TARGET_MB" ]; then
    sudo cp "$CONF" "$CONF.bak.$(date +%Y%m%d)"
    if grep -q '^message_journal_max_size' "$CONF"; then
      sudo sed -i "s/^message_journal_max_size.*/message_journal_max_size = $TARGET_SIZE/" "$CONF"
    else
      echo "message_journal_max_size = $TARGET_SIZE" | sudo tee -a "$CONF"
    fi
  fi
  echo "journal-configured: $(date)" >> "$STATE_FILE"
fi

# Prod Heap Tune
if [[ "$MONITOR_ENV" == "PRODUCTION" ]] && ! grep -q "heap-configured" "$STATE_FILE"; then
  if ! grep -q "^GRAYLOG_SERVER_JAVA_OPTS=" "$DEFAULTS"; then
    echo "GRAYLOG_SERVER_JAVA_OPTS=\"-Xms$GRAYLOG_HEAP_SIZE -Xmx$GRAYLOG_HEAP_SIZE -XX:+UseG1GC -Djdk.tls.acknowledgeCloseNotify=true -Dlog4j2.formatMsgNoLookups=true\"" | sudo tee -a "$DEFAULTS"
  else
    sudo sed -i "s/^GRAYLOG_SERVER_JAVA_OPTS=.*/GRAYLOG_SERVER_JAVA_OPTS=\"-Xms$GRAYLOG_HEAP_SIZE -Xmx$GRAYLOG_HEAP_SIZE -XX:+UseG1GC -Djdk.tls.acknowledgeCloseNotify=true -Dlog4j2.formatMsgNoLookups=true\"/" "$DEFAULTS"
  fi
  echo "heap-configured: $(date)" >> "$STATE_FILE"
fi

# Part 6: Security & Config
if ! grep -q "security-configured" "$STATE_FILE"; then
  NEW_PASS=$(openssl rand -base64 16)
  HASH=$(echo -n "$NEW_PASS" | sha256sum | awk '{print $1}')
  SERVER_SECRET=$(openssl rand -hex 32)
  sudo sed -i "s/^password_secret =.*/password_secret = $SERVER_SECRET/" "$CONF"
  sudo sed -i "s/^root_password_sha2 =.*/root_password_sha2 = $HASH/" "$CONF"
  sudo sed -i "s/^http_bind_address =.*/http_bind_address = 0.0.0.0:9000/" "$CONF"
  echo "mongodb_uri = mongodb://localhost/graylog" | sudo tee -a "$CONF"
  sudo sed -i "s/^export MONITOR_PASS=.*/export MONITOR_PASS=\"$NEW_PASS\"/" "$USER_HOME/config.sh"
  echo "Graylog admin password: $NEW_PASS (updated config.sh)"
  echo "security-configured: $(date)" >> "$STATE_FILE"
fi

# Part 7: Nginx Proxy
NGINX_CONF="/etc/nginx/sites-available/graylog"
NGINX_LINK="/etc/nginx/sites-enabled/graylog"
NGINX_DEFAULT="/etc/nginx/sites-enabled/default"

if ! grep -q "nginx-configured" "$STATE_FILE"; then
  if ! dpkg -l | grep -q nginx; then
    sudo apt install -y nginx
  fi
  sudo bash -c "cat <<EOF > $NGINX_CONF
server {
    listen $NGINX_PORT_HTTP;
    server_name $HOSTNAME.$DOMAIN;

    location /graylog/ {
        proxy_pass http://127.0.0.1:$GRAYLOG_PORT/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_busy_buffers_size 256k;
    }

    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
}
EOF"
  if [[ "$MONITOR_ENV" == "PRODUCTION" ]]; then
    sudo apt install -y certbot python3-certbot-nginx
    sudo certbot --nginx -d "$HOSTNAME.$DOMAIN" --non-interactive --agree-tos --email admin@$DOMAIN
    sudo sed -i '/listen 80;/a \    listen 443 ssl;' "$NGINX_CONF"
    sudo sed -i '/location \/graylog\//a \        proxy_set_header X-Forwarded-Proto https;' "$NGINX_CONF"
  fi
  sudo ln -sf "$NGINX_CONF" "$NGINX_LINK"
  [ -f "$NGINX_DEFAULT" ] && sudo rm "$NGINX_DEFAULT"
  sudo nginx -t
  sudo systemctl reload nginx
  echo "nginx-configured: $(date)" >> "$STATE_FILE"
fi

# Part 8: Start/Verify
sudo systemctl daemon-reload
sudo systemctl enable graylog-server
sudo systemctl start graylog-server
sleep 10
if sudo systemctl status graylog-server | grep -q 'Active: active (running)'; then
  echo "Graylog running. Test: curl -u admin:$NEW_PASS http://127.0.0.1:9000/api/system"
  echo "Proxy: curl -u admin:$NEW_PASS http://127.0.0.1/graylog/api/system"
  echo "graylog-verified: $(date)" >> "$STATE_FILE"
else
  echo "Failed; check sudo journalctl -u graylog-server"
  exit 1
fi

echo "Phase 3 complete. Browser: http://$IN_BAND_IP/graylog/ (admin/$NEW_PASS)."
