#!/bin/bash
# phase3_setup.sh: Phase 3 - Nginx reverse proxy, static site, Graylog stack (MongoDB, OpenSearch, Graylog), rsyslog forward.
# Purpose: Secure web access, syslog aggregation for M4300 (192.168.99.93) and server.
# Assumes: Run as root; Phase 1/2 complete; config.sh sourced (e.g., $MONITOR_PASS, $FUSESYSTEM="devlab").
# Workflow: Functionized for atomic exec. Call with section num (1-8); e.g., ./phase3_setup.sh 3 (only Mongo). Default (no arg): All.
# Idempotency: Checks (dpkg -l, systemctl is-enabled) skip done parts.
# Research: Graylog 6.0 (stable 6.0.6), OpenSearch 2.15 (compat Graylog), Mongo 7.0.14, OpenJDK-17. Trixie compat unproven—use Ubuntu repos for arm64. Official debs, single-node, bind local. Simplicity: HTTP only, minimal confs. Security: Local binds, UFW 514/udp allow from switch only.
# Fixes/Potential: For arm64, use Ubuntu jammy repo (Mongo). OpenJDK 17 from Bookworm. OpenSearch security disabled. Hash pw: printf for clean SHA-256. Test: curl localhost/graylog, journalctl. Nginx: Add X-Graylog-Server-URL, CORS, proxy_http_version 1.1, Connection "", proxy_redirect, debug log, Accept-Encoding, buffer sizes. Mongo/OpenSearch: Retry connectivity, reset graylog.users. Graylog: Minimal server.conf, file logging, /api/system PoL.
# Breadcrumb: [PHASE3_GRAYLOG_MINIMAL_CONF_FULL_20250902] Minimal server.conf via cat, create /var/log/graylog-server, keep Mongo/OpenSearch checks, user reset, 30s delay.

set -euo pipefail
if [ "$(id -u)" -ne 0 ]; then echo "Must run as root"; exit 1; fi
source "/home/monitor/config.sh"  # $MONITOR_PASS, etc.
LOG_FILE="/var/log/phase3_setup.log"
> "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "Phase 3 start: $(date)"

SECTION="${1:-all}"  # Default all
IN_BAND_ADDR=${IN_BAND_IP%/*}  # Strip /24

function update_inventory() {
    echo "Section 1: Update Ansible inventory with switch IP 192.168.99.93"
    if grep -q "ansible_host: \"192.168.99.93\"" "/home/monitor/ansible/inventories/$FUSESYSTEM.yaml"; then
        echo "Inventory already updated; skipping."
    else
        sed -i 's/192.168.99.94/192.168.99.93/g' "/home/monitor/ansible/inventories/$FUSESYSTEM.yaml"
        yamllint "/home/monitor/ansible/inventories/$FUSESYSTEM.yaml"  # Validate
        echo "Inventory updated. PoL: cat /home/monitor/ansible/inventories/$FUSESYSTEM.yaml"
    fi
}

function install_nginx() {
    echo "Section 2: Install/Configure Nginx (HTTP proxy, static site)"
    if dpkg -l | grep -q nginx; then
        echo "Nginx installed; checking config."
    else
        apt update
        apt install -y nginx wget unzip
        apt-mark hold nginx  # Pin stable
    fi
    # Static site setup
    mkdir -p /var/www/html/{assets,files}
    if [ ! -f "/var/www/html/assets/bootstrap.min.css" ]; then
        wget --inet4-only --timeout=30 --tries=3 -v https://github.com/twbs/bootstrap/releases/download/v5.3.3/bootstrap-5.3.3-dist.zip -O /tmp/bs.zip
        unzip /tmp/bs.zip -d /tmp
        cp /tmp/bootstrap-5.3.3-dist/css/bootstrap.min.css /var/www/html/assets/
        cp /tmp/bootstrap-5.3.3-dist/js/bootstrap.bundle.min.js /var/www/html/assets/
        rm -rf /tmp/bs.zip /tmp/bootstrap-5.3.3-dist
    fi
    # Copy M4300 manual to files dir
    if [ -f "/home/monitor/m4300-cli-manual-repaired.pdf" ] && [ ! -f "/var/www/html/files/m4300-cli-manual-repaired.pdf" ]; then
        cp /home/monitor/m4300-cli-manual-repaired.pdf /var/www/html/files/
        chown www-data:www-data /var/www/html/files/m4300-cli-manual-repaired.pdf
        chmod 644 /var/www/html/files/m4300-cli-manual-repaired.pdf
    fi
    # index.html: Dark mode default, switcher, like usgraphics.com, mobile-first
    if [ ! -f "/var/www/html/index.html" ]; then
        cat <<EOF > /var/www/html/index.html
<!DOCTYPE html>
<html lang="en" data-bs-theme="dark">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Devlab Monitoring System</title>
    <link href="/assets/bootstrap.min.css" rel="stylesheet">
</head>
<body>
    <nav class="navbar navbar-expand-lg bg-body-tertiary">
        <div class="container-fluid">
            <a class="navbar-brand" href="/">Devlab</a>
            <button class="navbar-toggler" type="button" data-bs-toggle="collapse" data-bs-target="#navbarNav" aria-controls="navbarNav" aria-expanded="false" aria-label="Toggle navigation">
                <span class="navbar-toggler-icon"></span>
            </button>
            <div class="collapse navbar-collapse" id="navbarNav">
                <ul class="navbar-nav me-auto">
                    <li class="nav-item"><a class="nav-link" href="/">Home</a></li>
                    <li class="nav-item"><a class="nav-link" href="/graylog">Graylog</a></li>
                    <li class="nav-item"><a class="nav-link" href="#">Cockpit (Future)</a></li>
                    <li class="nav-item"><a class="nav-link" href="/files/m4300-cli-manual-repaired.pdf">Documentation</a></li>
                    <li class="nav-item"><a class="nav-link" href="#">Status</a></li>
                </ul>
                <ul class="navbar-nav">
                    <li class="nav-item dropdown">
                        <button class="btn btn-outline-secondary dropdown-toggle" type="button" id="themeToggle" data-bs-toggle="dropdown" aria-expanded="false">
                            Theme
                        </button>
                        <ul class="dropdown-menu dropdown-menu-end" aria-labelledby="themeToggle">
                            <li><button class="dropdown-item" data-bs-theme-value="light">Light</button></li>
                            <li><button class="dropdown-item" data-bs-theme-value="dark">Dark</button></li>
                            <li><button class="dropdown-item" data-bs-theme-value="auto">Auto</button></li>
                        </ul>
                    </li>
                </ul>
            </div>
        </div>
    </nav>
    <div class="container my-5">
        <div class="jumbotron text-center">
            <h1>Welcome to Devlab Monitoring</h1>
            <p>System overview placeholder. Monitor M4300 switches and more.</p>
        </div>
        <section><h2>Status</h2><p>Placeholder for alerts/uptime.</p></section>
        <section><h2>Documentation</h2><p>Static links to manuals (e.g., <a href="/files/m4300-cli-manual-repaired.pdf">M4300 CLI Manual</a>).</p></section>
        <footer class="text-center mt-5">(c) 2025 Ready-1 LLC</footer>
    </div>
    <script src="/assets/bootstrap.bundle.min.js"></script>
    <script>
        (() => {
            const getStoredTheme = () => localStorage.getItem('theme');
            const setStoredTheme = theme => localStorage.setItem('theme', theme);
            const getPreferredTheme = () => {
                const stored = getStoredTheme();
                if (stored) return stored;
                return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
            };
            const setTheme = theme => {
                if (theme === 'auto') {
                    document.documentElement.setAttribute('data-bs-theme', window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
                } else {
                    document.documentElement.setAttribute('data-bs-theme', theme);
                }
            };
            setTheme(getPreferredTheme());
            document.querySelectorAll('[data-bs-theme-value]').forEach(el => {
                el.addEventListener('click', () => {
                    const theme = el.getAttribute('data-bs-theme-value');
                    setStoredTheme(theme);
                    setTheme(theme);
                });
            });
        })();
    </script>
</body>
</html>
EOF
    fi
    # Nginx conf: Root site, proxy /graylog to 127.0.0.1:9000 with subpath fix
    if [ ! -f "/etc/nginx/sites-enabled/default" ] || ! grep -q "proxy_pass http://127.0.0.1:9000" /etc/nginx/sites-enabled/default; then
        rm -f /etc/nginx/sites-enabled/default
        cat <<EOF > /etc/nginx/sites-available/default
server {
    listen 80 default_server;
    root /var/www/html;
    index index.html;
    error_log /var/log/nginx/error.log debug;
    location / {
        try_files \$uri \$uri/ =404;
    }
    location ~ ^/graylog(/.*)?$ {
        proxy_pass http://127.0.0.1:9000\$1;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Graylog-Server-URL http://\$server_name/graylog/;
        proxy_set_header Accept-Encoding "";
        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_redirect off;
    }
}
EOF
        ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/
        nginx -t && systemctl reload nginx
    fi
    if ! ufw status | grep -q "80/tcp.*ALLOW"; then
        ufw allow 80/tcp
        ufw reload
    fi
    echo "Nginx ready. PoL: curl -v localhost (check site), curl -v http://127.0.0.1/graylog/, journalctl -u nginx -n 50, systemctl status nginx"
}

function install_mongodb() {
    echo "Section 3: Install/Configure MongoDB 7.0 (for Graylog metadata)"
    if dpkg -l | grep -q mongodb-org-server; then
        echo "MongoDB installed; checking config."
    else
        apt install -y gnupg curl
        curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg
        echo "deb [arch=arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-7.0.list
        apt update
        apt install -y --fix-broken mongodb-org=7.0.14 mongodb-org-database=7.0.14 mongodb-org-server=7.0.14 mongodb-org-mongos=7.0.14 mongodb-org-tools=7.0.14 mongodb-mongosh
        apt-mark hold mongodb-org* mongodb-mongosh
    fi
    mkdir -p /var/lib/mongodb /var/log/mongodb
    chown -R mongodb:mongodb /var/lib/mongodb /var/log/mongodb
    if ! systemctl is-active mongod >/dev/null 2>&1; then
        systemctl start mongod
        sleep 5
    fi
    if ! systemctl is-enabled mongod >/dev/null 2>&1; then
        systemctl enable mongod
    fi
    # Reset and create graylog user
    mongosh --quiet mongodb://127.0.0.1:27017/graylog <<EOF
db.dropUser("graylog")
db.createUser({user: "graylog", pwd: "$MONITOR_PASS", roles: [{role: "dbOwner", db: "graylog"}]})
EOF
    # Enable auth in /etc/mongod.conf if not
    if ! grep -q "authorization: enabled" /etc/mongod.conf; then
        sed -i '/^security:/a \  authorization: enabled' /etc/mongod.conf
        systemctl restart mongod
        sleep 5
    fi
    # Test MongoDB connection
    if ! mongosh --quiet -u graylog -p "$MONITOR_PASS" --authenticationDatabase graylog mongodb://127.0.0.1:27017/graylog --eval 'db.version()' >/dev/null; then
        echo "Error: MongoDB connection failed. Check logs: journalctl -u mongod -n 50"
        exit 1
    fi
    echo "MongoDB ready. PoL: mongosh --quiet -u graylog -p '$MONITOR_PASS' --authenticationDatabase graylog mongodb://127.0.0.1:27017/graylog --eval 'db.version()'; systemctl status mongod"
}

function install_opensearch() {
    echo "Section 4: Install/Configure OpenSearch 2.15 (for Graylog storage)"
    if dpkg -l | grep -q opensearch; then
        echo "OpenSearch installed; checking config."
    else
        if ! java -version 2>&1 | grep -q "openjdk.*17"; then
            apt install -y lsb-release ca-certificates curl gnupg2
            echo "deb http://deb.debian.org/debian bookworm main" > /etc/apt/sources.list.d/bookworm.list
            echo "Package: openjdk-17-jre-headless\nPin: release n=bookworm\nPin-Priority: 1001" > /etc/apt/preferences.d/openjdk-17
            apt update
            apt install -y openjdk-17-jre-headless
            rm /etc/apt/sources.list.d/bookworm.list
            apt update
        fi
        curl -o- https://artifacts.opensearch.org/publickeys/opensearch.pgp | gpg --dearmor --batch --yes -o /usr/share/keyrings/opensearch.gpg
        echo "deb [signed-by=/usr/share/keyrings/opensearch.gpg] https://artifacts.opensearch.org/releases/bundle/opensearch/2.x/apt stable main" | tee /etc/apt/sources.list.d/opensearch-2.x.list
        apt update
        OPENSEARCH_INITIAL_ADMIN_PASSWORD="$MONITOR_PASS" apt install -y --fix-broken opensearch=2.15.0
        apt-mark hold opensearch
    fi
    if ! grep -q "discovery.type: single-node" /etc/opensearch/opensearch.yml; then
        cat <<EOF >> /etc/opensearch/opensearch.yml
network.host: 127.0.0.1
discovery.type: single-node
plugins.security.disabled: true
EOF
        sed -i 's/-Xms1g/-Xms2g/g; s/-Xmx1g/-Xmx2g/g' /etc/opensearch/jvm.options
        export OPENSEARCH_JAVA_HOME=/usr/share/opensearch/jdk
        systemctl restart opensearch
        sleep 10
    fi
    if ! systemctl is-enabled opensearch >/dev/null 2>&1; then
        systemctl enable --now opensearch
    fi
    # Retry OpenSearch connectivity
    for i in {1..3}; do
        if curl -s http://127.0.0.1:9200 >/dev/null; then
            break
        fi
        echo "OpenSearch not ready; retrying ($i/3)..."
        sleep 10
    done
    if ! curl -s http://127.0.0.1:9200 >/dev/null; then
        echo "Error: OpenSearch not responding on 127.0.0.1:9200. Check logs: journalctl -u opensearch -n 50"
        exit 1
    fi
    echo "OpenSearch ready. PoL: java -version; curl -XGET http://127.0.0.1:9200; systemctl status opensearch; journalctl -u opensearch -n 50"
}

function install_graylog() {
    echo "Section 5: Install/Configure Graylog 6.0"
    if ! ping -c 3 -W 5 8.8.8.8 >/dev/null 2>&1; then
        echo "Error: No internet connectivity. Check network and try again."
        exit 1
    fi
    if dpkg -l | grep -q graylog-server; then
        echo "Graylog installed; checking config."
    else
        apt install -y pwgen
        wget --inet4-only --timeout=30 --tries=3 -v https://packages.graylog2.org/repo/packages/graylog-6.0-repository_latest.deb -O /tmp/graylog-repo.deb
        if [ $? -ne 0 ]; then
            echo "Error: Failed to download Graylog repo package."
            exit 1
        fi
        dpkg -i /tmp/graylog-repo.deb
        rm /tmp/graylog-repo.deb
        apt update
        apt install -y --fix-broken graylog-server=6.0.6-1
        apt-mark hold graylog-server
    fi
    # Stop service and clean journal/users
    systemctl stop graylog-server
    rm -rf /var/lib/graylog-server/journal/*
    mongosh --quiet -u graylog -p "$MONITOR_PASS" --authenticationDatabase graylog mongodb://127.0.0.1:27017/graylog <<EOF
db.users.drop()
EOF
    # Write minimal server.conf
    ROOT_PW_SHA2=$(printf %s "$MONITOR_PASS" | sha256sum | cut -d ' ' -f1)
    PASS_SECRET=$(pwgen -N 1 -s 96)
    cat <<EOF > /etc/graylog/server/server.conf
# Graylog 6.0.6 configuration file for single-node setup
# Encoding: ISO 8859-1
# Generated for Debian Trixie (arm64), Nginx proxy, MongoDB, OpenSearch

# Single-node leader configuration
is_leader = true
node_id_file = /etc/graylog/server/node-id

# Password settings
password_secret = $PASS_SECRET
root_password_sha2 = $ROOT_PW_SHA2

# HTTP settings
http_bind_address = 127.0.0.1:9000
http_external_uri = http://$IN_BAND_ADDR/graylog/
http_enable_cors = true

# Data storage directories
bin_dir = /usr/share/graylog-server/bin
data_dir = /var/lib/graylog-server
plugin_dir = /usr/share/graylog-server/plugin
message_journal_dir = /var/lib/graylog-server/journal

# MongoDB connection
mongodb_uri = mongodb://graylog:$MONITOR_PASS@127.0.0.1:27017/graylog

# OpenSearch connection
elasticsearch_hosts = http://127.0.0.1:9200
EOF
    # Create logging dir and set permissions
    mkdir -p /var/log/graylog-server
    chown graylog:graylog /var/log/graylog-server
    chmod 755 /var/log/graylog-server
    # Enable file logging
    cat <<EOF > /etc/graylog/server/log4j2.properties
log4j2.rootLogger.level = INFO
log4j2.rootLogger.appenderRef.file.ref = File
log4j2.appender.file.type = File
log4j2.appender.file.name = File
log4j2.appender.file.fileName = /var/log/graylog-server/server.log
log4j2.appender.file.layout.type = PatternLayout
log4j2.appender.file.layout.pattern = %d{yyyy-MM-dd HH:mm:ss,SSS} %-5p [%c{1}] %m%n
EOF
    chown graylog:graylog /etc/graylog/server/log4j2.properties
    chmod 644 /etc/graylog/server/log4j2.properties
    # Validate config
    if ! grep -q "root_password_sha2 = $ROOT_PW_SHA2" /etc/graylog/server/server.conf; then
        echo "Error: Failed to set root_password_sha2 in server.conf"
        exit 1
    fi
    # Verify MongoDB/OpenSearch before start
    if ! mongosh --quiet -u graylog -p "$MONITOR_PASS" --authenticationDatabase graylog mongodb://127.0.0.1:27017/graylog --eval 'db.version()' >/dev/null; then
        echo "Error: MongoDB connection failed. Check logs: journalctl -u mongod -n 50"
        exit 1
    fi
    if ! curl -s http://127.0.0.1:9200 >/dev/null; then
        echo "Error: OpenSearch not responding on 127.0.0.1:9200. Check logs: journalctl -u opensearch -n 50"
        exit 1
    fi
    if ! systemctl is-enabled graylog-server >/dev/null 2>&1; then
        systemctl enable --now graylog-server
        sleep 30
    fi
    echo "Graylog ready. PoL: curl -v -u admin:$MONITOR_PASS http://127.0.0.1:9000/api/system; curl -v http://127.0.0.1/graylog/api/system; tail -n 50 /var/log/graylog-server/server.log; journalctl -u graylog-server -n 50; browser http://$IN_BAND_ADDR/graylog login admin/$MONITOR_PASS (clear cache), create Syslog UDP input on 514 (bind 0.0.0.0)."
}

function configure_rsyslog() {
    echo "Section 6: Configure rsyslog forward to Graylog (127.0.0.1:514/UDP)"
    if [ -f "/etc/rsyslog.d/10-graylog.conf" ]; then
        echo "rsyslog config exists; skipping."
    else
        cat <<EOF > /etc/rsyslog.d/10-graylog.conf
*.* @127.0.0.1:514;RSYSLOG_SyslogProtocol23Format
# Avoid loop: local7.* ~
EOF
        systemctl restart rsyslog
    fi
    echo "rsyslog configured. PoL: logger 'test log' && tail /var/log/graylog-server/server.log (check ingest)"
}

function update_ufw() {
    echo "Section 7: UFW allow 514/udp from switch (192.168.99.93)"
    if ufw status | grep -q "514/udp.*ALLOW.*192.168.99.93"; then
        echo "UFW rule exists; skipping."
    else
        ufw allow from 192.168.99.93 to any port 514 proto udp
        ufw reload
    fi
    echo "UFW updated. PoL: ufw status"
}

function final_checks() {
    echo "Section 8: Final PoL and cleanup"
    curl -s localhost | grep "Devlab Monitoring" || echo "Site fail; check Nginx"
    curl -s -u admin:$MONITOR_PASS localhost/graylog/api/system || echo "Proxy/Graylog fail; check services"
    tail -n 50 /var/log/graylog-server/server.log
    journalctl -u nginx -n 50
    echo "Phase 3 complete: $(date). Verify UI, logs from switch (manual CLI config per M4300 manual p.228: configure; logging host 192.168.99.91 port 514 level info)."
    echo "Note: OpenSearch security disabled; re-enable with proper certs in Phase 12."
    touch "/home/monitor/[PHASE3_SUCCESS_20250902]"
}

# Execute
if [ "$SECTION" = "all" ]; then
    for i in {1..8}; do
        case $i in
            1) update_inventory ;;
            2) install_nginx ;;
            3) install_mongodb ;;
            4) install_opensearch ;;
            5) install_graylog ;;
            6) configure_rsyslog ;;
            7) update_ufw ;;
            8) final_checks ;;
        esac
    done
else
    case $SECTION in
        1) update_inventory ;;
        2) install_nginx ;;
        3) install_mongodb ;;
        4) install_opensearch ;;
        5) install_graylog ;;
        6) configure_rsyslog ;;
        7) update_ufw ;;
        8) final_checks ;;
        *) echo "Invalid section: $SECTION (1-8 or all)"; exit 1 ;;
    esac
fi

exit 0
