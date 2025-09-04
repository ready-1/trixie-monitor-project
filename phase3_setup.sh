#!/bin/bash
# File: phase3_setup.sh
# Breadcrumb: [2025-09-04 10:10 EDT | 1744044600]
# Description: Installs and configures Nginx as a reverse proxy and Graylog as a syslog server
# for monitoring NETGEAR M4300 switches on ARM64 Debian Trixie. Uses Bash for logging.
# Uses jammy for MongoDB repo; APT for OpenSearch and Graylog; post-install chown for Graylog.
# Fixes Graylog startup with journal/log permissions, API with retry loop, conffile prompt, MongoDB APT, sed error, and signature warnings (transient).
# Usage: Run as root or with sudo, e.g., `sudo bash /home/monitor/phase3_setup.sh` or `chmod +x` and `sudo /home/monitor/phase3_setup.sh`

# Exit on error
set -e

# Verify Bash is used
if [ -z "$BASH_VERSION" ]; then
    echo "Error: This script requires Bash. Run with 'bash $0' or ensure executable permissions."
    exit 1
fi

# Verify MONITOR_PASS is set
if [ -z "$MONITOR_PASS" ]; then
    echo "Error: MONITOR_PASS environment variable not set."
    echo "Set it with: export MONITOR_PASS='FuseFuse123!' and rerun."
    exit 1
fi

# Detect architecture
ARCH=$(dpkg --print-architecture)
if [ "$ARCH" != "arm64" ] && [ "$ARCH" != "aarch64" ]; then
    echo "Error: This script is optimized for ARM64. Detected: $ARCH"
    exit 1
fi

# Define variables
LOG_FILE="/home/monitor/phase3_setup.log"
GRAYLOG_VERSION="6.0"
OPENSEARCH_VERSION="2.11.1"  # Specific version; falls back to latest 2.x if unavailable
NGINX_CONF="/etc/nginx/sites-available/graylog"
GRAYLOG_CONF="/etc/graylog/server/server.conf"
REPO_URL="https://packages.graylog2.org/repo/packages/graylog-$GRAYLOG_VERSION-repository_latest.deb"
MONGODB_DIST="jammy"  # Use Ubuntu jammy for MongoDB ARM64
# Alternative: MONGODB_DIST="bookworm" (uncomment if jammy fails)

# Log all output to file and console (Bash-specific)
exec > >(tee -a "$LOG_FILE") 2>&1
echo "----------------------------------------"
echo "Starting Phase 3 setup at $(date '+%Y-%m-%d %H:%M:%S') (ARM64 detected)"
echo "----------------------------------------"

# Install required packages (OpenJDK 21 via APT for ARM64)
echo "Installing dependencies..."
apt-get update
apt-get install -y curl gnupg apt-transport-https lsb-release ca-certificates openjdk-21-jre-headless uuid-runtime nginx pwgen

# Install OpenSearch via APT repository (fixes 403 direct download error)
echo "Installing OpenSearch $OPENSEARCH_VERSION via APT (ARM64)..."
curl -o- https://artifacts.opensearch.org/publickeys/opensearch.pgp | gpg --dearmor --batch --yes -o /usr/share/keyrings/opensearch-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/opensearch-keyring.gpg] https://artifacts.opensearch.org/releases/bundle/opensearch/2.x/apt stable main" | tee /etc/apt/sources.list.d/opensearch-2.x.list
apt-get update
# Install specific version if available; otherwise latest 2.x
if apt-cache policy opensearch | grep -q "$OPENSEARCH_VERSION"; then
    apt-get install -y "opensearch=$OPENSEARCH_VERSION"
else
    echo "Warning: $OPENSEARCH_VERSION not available; installing latest 2.x"
    apt-get install -y opensearch
fi

# Configure OpenSearch (disable security for simplicity; enable in production)
echo "Configuring OpenSearch..."
cat <<EOF >/etc/opensearch/opensearch.yml
cluster.name: graylog
network.host: 127.0.0.1
discovery.type: single-node
plugins.security.disabled: true
EOF
systemctl daemon-reload
systemctl enable opensearch
systemctl start opensearch

# Install MongoDB via APT repository (jammy for ARM64)
echo "Installing MongoDB 7.0 via APT (jammy)..."
curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg
echo "deb [ arch=arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu $MONGODB_DIST/mongodb-org/7.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-7.0.list
apt-get update
apt-get install -y mongodb-org || { echo "MongoDB installation failed; check repo or try MONGODB_DIST=bookworm"; exit 1; }
systemctl enable mongod
systemctl start mongod

# Install Graylog repository
echo "Installing Graylog $GRAYLOG_VERSION repository..."
wget -4 --timeout=30 --tries=3 -O graylog-repo.deb "$REPO_URL"
dpkg -i graylog-repo.deb || { echo "Graylog repository installation failed"; exit 1; }
rm graylog-repo.deb
apt-get update

# Preconfigure Graylog server.conf to avoid sed error (before install; chown after)
echo "Preconfiguring Graylog to avoid sed error..."
mkdir -p /etc/graylog/server
PASSWORD_SECRET=$(pwgen -N 1 -s 96)
ADMIN_HASH=$(echo -n "$MONITOR_PASS" | sha256sum | cut -d" " -f1)
cat <<EOF >"$GRAYLOG_CONF"
mongodb_uri = mongodb://localhost/graylog
elasticsearch_hosts = http://127.0.0.1:9200
is_leader = true
node_id_file = /etc/graylog/server/node-id
password_secret = $PASSWORD_SECRET
root_password_sha2 = $ADMIN_HASH
root_timezone = UTC
http_bind_address = 127.0.0.1:9000
http_publish_uri = http://192.168.99.91:9000/
http_enable_cors = true
http_max_header_size = 8192
http_thread_pool_size = 16
message_journal_max_size = 1g
EOF
chmod 644 "$GRAYLOG_CONF"  # Temporary; package will adjust

# Install Graylog with noninteractive handling to avoid conffile prompt
echo "Installing Graylog $GRAYLOG_VERSION..."
export DEBIAN_FRONTEND=noninteractive
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" graylog-server || { echo "Graylog installation failed; attempting to fix..."; dpkg --configure -a; apt-get install -f -y; }

# Create and chown Graylog journal and log directories (fixes missing permissions)
mkdir -p /var/lib/graylog-server/journal
chown graylog:graylog /var/lib/graylog-server/journal
mkdir -p /var/log/graylog-server
chown graylog:graylog /var/log/graylog-server

# Chown after install (user/group now exists)
chown graylog:graylog "$GRAYLOG_CONF"
chmod 600 "$GRAYLOG_CONF"

# Start and enable Graylog
systemctl enable graylog-server
systemctl start graylog-server

# Wait for Graylog to start (up to 60 seconds)
echo "Waiting for Graylog API to become available..."
for i in {1..12}; do
    if curl -s -f http://127.0.0.1:9000/api/system | grep -q "cluster_id"; then
        echo "Graylog API is accessible"
        break
    fi
    echo "Attempt $i: Graylog API not yet available, waiting 5 seconds..."
    sleep 5
done

# Final API test
echo "Testing Graylog API..."
if curl -s -f http://127.0.0.1:9000/api/system | grep -q "cluster_id"; then
    echo "Graylog API is accessible"
else
    echo "Error: Graylog API not accessible"
    echo "Diagnostics:"
    echo "- Check Graylog logs: journalctl -u graylog-server -n 50"
    echo "- Verify port 9000: netstat -tuln | grep 9000"
    echo "- Ensure MongoDB/OpenSearch: systemctl status mongod opensearch"
    echo "- Check /var space: df -h /var"
    echo "- Check Graylog server log: cat /var/log/graylog-server/server.log | tail -n 50"
    exit 1
fi

# Install and configure Nginx
echo "Configuring Nginx as reverse proxy..."
cat <<EOF >"$NGINX_CONF"
server {
    listen 80;
    server_name $(hostname -f);
    location / {
        proxy_pass http://127.0.0.1:9000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
ln -sf /etc/nginx/sites-available/graylog /etc/nginx/sites-enabled/graylog
nginx -t || { echo "Nginx configuration test failed"; exit 1; }
systemctl enable nginx
systemctl restart nginx

# Verify services
echo "Verifying services..."
for svc in opensearch mongod graylog-server nginx; do
    if ! systemctl is-active --quiet "$svc"; then
        echo "Error: $svc service not running"
        exit 1
    else
        echo "$svc service is running"
    fi
done

echo "----------------------------------------"
echo "Phase 3 setup completed successfully at $(date '+%Y-%m-%d %H:%M:%S')"
echo "Access Graylog at http://192.168.99.91:80 with username 'admin' and password set in MONITOR_PASS"
echo "Log saved to $LOG_FILE"
echo "Password secret: $PASSWORD_SECRET (save securely)"
echo "Note: Signature warnings are transient (Trixie fresh release); resolve post-2025-09-04."
echo "----------------------------------------"
