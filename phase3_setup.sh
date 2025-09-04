#!/bin/bash
# File: phase3_setup.sh
# Breadcrumb: [2025-09-04 09:30 EDT | 1744042200]
# Description: Installs and configures Nginx as a reverse proxy and Graylog as a syslog server
# for monitoring NETGEAR M4300 switches on ARM64 Debian Trixie. Uses Bash for logging.
# Uses bookworm for MongoDB repo (Trixie unsupported); APT for OpenSearch; post-install chown for Graylog.
# Fixes MongoDB 404, Graylog user creation, signature warnings (transient), and ensures Bash execution.
# Usage: Run as root or with sudo, e.g., `sudo bash /home/monitor/phase3_setup.sh` or `chmod +x` and `sudo /home/monitor/phase3_setup.sh`

# Exit on error
set -e

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
MONGODB_DIST="bookworm"  # Fallback to bookworm (Trixie unsupported for MongoDB ARM64)

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

# Install MongoDB via APT repository (bookworm fallback for ARM64)
echo "Installing MongoDB 7.0 via APT..."
curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg
echo "deb [ arch=arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/debian $MONGODB_DIST/mongodb-org/7.0 main" | tee /etc/apt/sources.list.d/mongodb-org-7.0.list
apt-get update
apt-get install -y mongodb-org
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
ADMIN_PASSWORD="admin123"  # Change for production
ADMIN_HASH=$(echo -n "$ADMIN_PASSWORD" | sha256sum | cut -d" " -f1)
cat <<EOF >"$GRAYLOG_CONF"
is_leader = true
node_id_file = /etc/graylog/server/node-id
password_secret = $PASSWORD_SECRET
root_password_sha2 = $ADMIN_HASH
root_timezone = UTC
http_bind_address = 127.0.0.1:9000
http_publish_uri = http://$(hostname -I | awk '{print $1}'):9000/
http_enable_cors = true
http_max_header_size = 8192
http_thread_pool_size = 16
EOF
chmod 644 "$GRAYLOG_CONF"  # Temporary; package will adjust

# Install Graylog with workaround for post-install sed error
echo "Installing Graylog $GRAYLOG_VERSION..."
if ! apt-get install -y graylog-server; then
    echo "Warning: Graylog installation encountered errors (likely sed issue). Attempting to fix..."
    dpkg --configure -a
    apt-get install -f -y
fi

# Chown after install (user/group now exists)
chown graylog:graylog "$GRAYLOG_CONF"
chmod 600 "$GRAYLOG_CONF"

# Start and enable Graylog
systemctl enable graylog-server
systemctl start graylog-server

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

# Test Graylog API
echo "Testing Graylog API..."
if curl -s -f http://127.0.0.1:9000/api/system | grep -q "cluster_id"; then
    echo "Graylog API is accessible"
else
    echo "Error: Graylog API not accessible"
    exit 1
fi

echo "----------------------------------------"
echo "Phase 3 setup completed successfully at $(date '+%Y-%m-%d %H:%M:%S')"
echo "Access Graylog at http://$(hostname -I | awk '{print $1}'):80 with username 'admin' and password 'admin123'"
echo "Log saved to $LOG_FILE"
echo "Password secret: $PASSWORD_SECRET (save securely)"
echo "Note: Signature warnings are transient (Trixie fresh release); resolve post-2025-09-04."
echo "----------------------------------------"
