#!/bin/bash

# Script to create a new Odoo tenant with its own database and configuration
# Usage: ./create-tenant.sh tenant_name database_name

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 tenant_name database_name"
    echo "Example: $0 customer1 odoo_customer1"
    exit 1
fi

TENANT=$1
DB_NAME=$2
TENANT_DIR="/opt/odoo-$TENANT"
BASE_PORT=$((8090 + RANDOM % 100))  # Random port between 8090-8190
HTTP_PORT=$BASE_PORT
HTTPS_PORT=$((BASE_PORT+1))
CHAT_PORT=$((BASE_PORT+2))

echo "Creating new tenant: $TENANT"
echo "Database name: $DB_NAME"
echo "Ports: HTTP=$HTTP_PORT, HTTPS=$HTTPS_PORT, Chat=$CHAT_PORT"

# Check if directory already exists
if [ -d "$TENANT_DIR" ]; then
    echo "Warning: Tenant directory already exists. Removing it to start fresh."
    rm -rf "$TENANT_DIR"
fi

# Create directories
mkdir -p "$TENANT_DIR"
mkdir -p "/opt/odoo-addons/tenant-specific/$TENANT"

# Create odoo.conf with optimized configuration
cat > "$TENANT_DIR/odoo.conf" << EOCNF
[options]
addons_path = /mnt/shared-addons,/mnt/extra-addons
data_dir = /var/lib/odoo
db_host = 192.168.60.110
db_port = 5432
db_user = odoo
db_password = cnV2abjbDpbh64e12987wR4mj5kQ3456Y0Qf
db_name = DB_NAME_PLACEHOLDER
db_sslmode = prefer
db_maxconn = 64
db_thread = True
db_pooler = True
proxy_mode = True
website_name = TENANT_PLACEHOLDER.arcweb.com.au
without_demo = all

; server parameters
limit_memory_hard = 2684354560
limit_memory_soft = 2147483648
limit_request = 8192
limit_time_cpu = 600
limit_time_real = 1200
max_cron_threads = 1
workers = 3
transient_age_limit = 1.0
http_interface = 0.0.0.0
list_db = False
EOCNF

# Replace placeholders
sed -i "s/TENANT_PLACEHOLDER/$TENANT/g" "$TENANT_DIR/odoo.conf"
sed -i "s/DB_NAME_PLACEHOLDER/$DB_NAME/g" "$TENANT_DIR/odoo.conf"

# Create docker-compose.yml with optimized settings
cat > "$TENANT_DIR/docker-compose.yml" << 'EODCF'
version: '3'
services:
  odoo-TENANT_PLACEHOLDER:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "HTTP_PORT_PLACEHOLDER:8069"
      - "HTTPS_PORT_PLACEHOLDER:8071"
      - "CHAT_PORT_PLACEHOLDER:8072"
    volumes:
      - odoo-TENANT_PLACEHOLDER-data:/var/lib/odoo
      - /opt/odoo-addons/shared:/mnt/shared-addons
      - /opt/odoo-addons/tenant-specific/TENANT_PLACEHOLDER:/mnt/extra-addons
      - ./odoo.conf:/etc/odoo/odoo.conf:ro
    environment:
      - HOST=192.168.60.110
      - PORT=5432
      - USER=odoo
      - PASSWORD=cnV2abjbDpbh64e12987wR4mj5kQ3456Y0Qf
      - DB_NAME=DB_NAME_PLACEHOLDER
      - VIRTUAL_HOST=TENANT_PLACEHOLDER.arcweb.com.au
      - VIRTUAL_PORT=8069
      - PGSSLMODE=prefer
      - DB_MAXCONN=64
      - DB_POOL_SIZE=20
      - LIMIT_MEMORY_HARD=2684354560
      - LIMIT_MEMORY_SOFT=2147483648
      - LIMIT_TIME_CPU=600
      - LIMIT_TIME_REAL=1200
      - MAX_CRON_THREADS=1
      - WORKERS=3
      - TZ=UTC
    command: ["odoo", "--without-demo=all"]
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8069/web/webclient/version_info", "||", "exit", "1"]
      interval: 2m
      timeout: 10s
      retries: 3
      start_period: 30s

volumes:
  odoo-TENANT_PLACEHOLDER-data:
    name: odoo-TENANT_PLACEHOLDER-data
EODCF

# Replace placeholders
sed -i "s/TENANT_PLACEHOLDER/$TENANT/g" "$TENANT_DIR/docker-compose.yml"
sed -i "s/HTTP_PORT_PLACEHOLDER/$HTTP_PORT/g" "$TENANT_DIR/docker-compose.yml"
sed -i "s/HTTPS_PORT_PLACEHOLDER/$HTTPS_PORT/g" "$TENANT_DIR/docker-compose.yml"
sed -i "s/CHAT_PORT_PLACEHOLDER/$CHAT_PORT/g" "$TENANT_DIR/docker-compose.yml"
sed -i "s/DB_NAME_PLACEHOLDER/$DB_NAME/g" "$TENANT_DIR/docker-compose.yml"

# Copy Dockerfile from main instance
cp /opt/odoo/Dockerfile "$TENANT_DIR/"

# Create entrypoint.sh script
cat > "$TENANT_DIR/entrypoint.sh" << 'EOENT'
#!/bin/bash

set -e

if [ -v PASSWORD_FILE ]; then
    PASSWORD="$(< $PASSWORD_FILE)"
fi

# set the postgres database host, port, user and password according to the environment
# and pass them as arguments to the odoo process if not present in the config file
: ${HOST:=${DB_PORT_5432_TCP_ADDR:='db'}}
: ${PORT:=${DB_PORT_5432_TCP_PORT:=5432}}
: ${USER:=${DB_ENV_POSTGRES_USER:=${POSTGRES_USER:='odoo'}}}
: ${PASSWORD:=${DB_ENV_POSTGRES_PASSWORD:=${POSTGRES_PASSWORD:='odoo'}}}

DB_ARGS=()
function check_config() {
    param="$1"
    value="$2"
    if grep -q -E "^\s*\b${param}\b\s*=" "$ODOO_RC" ; then       
        value=$(grep -E "^\s*\b${param}\b\s*=" "$ODOO_RC" |cut -d " " -f3|sed 's/["\n\r]//g')
    fi;
    DB_ARGS+=("--${param}")
    DB_ARGS+=("${value}")
}
check_config "db_host" "$HOST"
check_config "db_port" "$PORT"
check_config "db_user" "$USER"
check_config "db_password" "$PASSWORD"

case "$1" in
    -- | odoo)
        shift
        if [[ "$1" == "scaffold" ]] ; then
            exec odoo "$@"
        else
            wait-for-psql.py ${DB_ARGS[@]} --timeout=30
            exec odoo "$@" "${DB_ARGS[@]}"
        fi
        ;;
    -*)
        wait-for-psql.py ${DB_ARGS[@]} --timeout=30
        exec odoo "$@" "${DB_ARGS[@]}"
        ;;
    *)
        exec "$@"
esac

exit 1
EOENT

# Make entrypoint.sh executable
chmod +x "$TENANT_DIR/entrypoint.sh"

# Create wait-for-psql.py script
cat > "$TENANT_DIR/wait-for-psql.py" << 'EOWAIT'
#!/usr/bin/env python3
import argparse
import psycopg2
import sys
import time


if __name__ == '__main__':
    arg_parser = argparse.ArgumentParser()
    arg_parser.add_argument('--db_host', required=True)
    arg_parser.add_argument('--db_port', required=True)
    arg_parser.add_argument('--db_user', required=True)
    arg_parser.add_argument('--db_password', required=True)
    arg_parser.add_argument('--timeout', type=int, default=5)

    args = arg_parser.parse_args()

    start_time = time.time()
    while (time.time() - start_time) < args.timeout:
        try:
            conn = psycopg2.connect(user=args.db_user, host=args.db_host, port=args.db_port, password=args.db_password, dbname='postgres')
            error = ''
            break
        except psycopg2.OperationalError as e:
            error = e
        else:
            conn.close()
        time.sleep(1)

    if error:
        print("Database connection failure: %s" % error, file=sys.stderr)
        sys.exit(1)
EOWAIT

# Make wait-for-psql.py executable
chmod +x "$TENANT_DIR/wait-for-psql.py"

# Check if PostgreSQL client is installed
if ! command -v psql &> /dev/null; then
    echo "PostgreSQL client not found. Using Docker for database operations..."
    # Create the database using docker
    docker run --rm postgres:latest psql "postgresql://odoo:cnV2abjbDpbh64e12987wR4mj5kQ3456Y0Qf@192.168.60.110:5432/postgres" -c "DROP DATABASE IF EXISTS $DB_NAME;" || echo "Failed to drop database, it may not exist."
    docker run --rm postgres:latest psql "postgresql://odoo:cnV2abjbDpbh64e12987wR4mj5kQ3456Y0Qf@192.168.60.110:5432/postgres" -c "CREATE DATABASE $DB_NAME OWNER odoo;" || echo "Failed to create database. Check PostgreSQL connection."
else
    # Create or replace the database using psql
    echo "Initializing database..."
    PGPASSWORD=cnV2abjbDpbh64e12987wR4mj5kQ3456Y0Qf psql -h 192.168.60.110 -U odoo -c "DROP DATABASE IF EXISTS $DB_NAME;" || echo "Failed to drop database, it may not exist."
    PGPASSWORD=cnV2abjbDpbh64e12987wR4mj5kQ3456Y0Qf psql -h 192.168.60.110 -U odoo -c "CREATE DATABASE $DB_NAME OWNER odoo;" || echo "Failed to create database. Check PostgreSQL connection."
fi

# Create Nginx configuration file with WebSocket optimizations
cat > "/etc/nginx/sites-available/$TENANT.arcweb.com.au.conf" << 'EONGINX'
map $http_upgrade $connection_upgrade {
  default upgrade;
  ''      close;
}

# TENANT_PLACEHOLDER Odoo server
upstream odoo_TENANT_PLACEHOLDER {
   server 127.0.0.1:HTTP_PORT_PLACEHOLDER;
}
upstream odoochat_TENANT_PLACEHOLDER {
   server 127.0.0.1:CHAT_PORT_PLACEHOLDER;
}

# HTTP redirect to HTTPS
server {
   listen 80;
   server_name TENANT_PLACEHOLDER.arcweb.com.au;
   
   # Redirect to HTTPS
   return 301 https://$host$request_uri;
}

# TENANT_PLACEHOLDER tenant (TENANT_PLACEHOLDER.arcweb.com.au)
server {
   listen 443 ssl http2;
   server_name TENANT_PLACEHOLDER.arcweb.com.au;

   ssl_certificate /etc/letsencrypt/live/arcweb.com.au/fullchain.pem;
   ssl_certificate_key /etc/letsencrypt/live/arcweb.com.au/privkey.pem;

   # log
   access_log /var/log/nginx/TENANT_PLACEHOLDER.arcweb.com.au.access.log;
   error_log /var/log/nginx/TENANT_PLACEHOLDER.arcweb.com.au.error.log;

   # Increased timeouts for WebSocket connections
   proxy_read_timeout 720s;
   proxy_connect_timeout 720s;
   proxy_send_timeout 720s;
   
   # Improved buffer settings for WebSocket
   proxy_buffers 16 64k;
   proxy_buffer_size 128k;

   # Redirect websocket requests
   location /websocket {
      proxy_pass http://odoochat_TENANT_PLACEHOLDER;
      proxy_http_version 1.1;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection $connection_upgrade;
      proxy_set_header X-Forwarded-Host $host;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_read_timeout 600s;
      proxy_connect_timeout 600s;
      proxy_buffering off;
   }

   # Redirect longpoll requests
   location /longpolling {
      proxy_pass http://odoochat_TENANT_PLACEHOLDER;
      proxy_http_version 1.1;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection $connection_upgrade;
      proxy_set_header X-Forwarded-Host $host;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_read_timeout 600s;
      proxy_connect_timeout 600s;
      proxy_buffering off;
   }

   # Redirect requests to odoo backend server
   location / {
      # Add Headers for odoo proxy mode
      proxy_set_header X-Forwarded-Host $host;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_redirect off;
      proxy_pass http://odoo_TENANT_PLACEHOLDER;
      proxy_http_version 1.1;
      client_max_body_size 512M;
   }

   location ~* /web/static/ {
      proxy_cache_valid 200 90m;
      proxy_buffering on;
      expires 864000;
      proxy_pass http://odoo_TENANT_PLACEHOLDER;
   }

   # common gzip
   gzip_types text/css text/scss text/plain text/xml application/xml application/json application/javascript;
   gzip on;
}
EONGINX

# Replace placeholders
sed -i "s/TENANT_PLACEHOLDER/$TENANT/g" "/etc/nginx/sites-available/$TENANT.arcweb.com.au.conf"
sed -i "s/HTTP_PORT_PLACEHOLDER/$HTTP_PORT/g" "/etc/nginx/sites-available/$TENANT.arcweb.com.au.conf"
sed -i "s/CHAT_PORT_PLACEHOLDER/$CHAT_PORT/g" "/etc/nginx/sites-available/$TENANT.arcweb.com.au.conf"

# Enable the site
ln -sf "/etc/nginx/sites-available/$TENANT.arcweb.com.au.conf" /etc/nginx/sites-enabled/

# Test Nginx configuration
nginx -t

# Clean up any existing volumes that might cause issues
echo "Cleaning up any old Docker volumes..."
docker volume rm -f "odoo-${TENANT}-data" || true
docker volume rm -f "odoo-${TENANT}_odoo-${TENANT}-data" || true

# Start the container
echo "Starting the new tenant..."
cd "$TENANT_DIR"
# Start with fresh build to avoid ContainerConfig issues
docker-compose down --volumes || true
docker-compose build --no-cache
docker-compose up -d

# Wait for Odoo to start
echo "Waiting for Odoo to initialize..."
sleep 10

# Initialize database with essential modules
echo "Initializing the database with essential modules..."
docker-compose exec -T odoo-$TENANT odoo -i base,web,mail -d $DB_NAME --stop-after-init || \
# Alternative method if exec fails
docker-compose run --rm odoo-$TENANT odoo -i base,web,mail -d $DB_NAME --stop-after-init

# Create cleanup script for the tenant
cat > "/opt/scripts/cleanup-postgres-$TENANT.sh" << EOCLEAN
#!/bin/bash
# Script to clean up idle PostgreSQL connections for $TENANT
# Add to crontab to run every hour

# Configuration
PG_HOST="192.168.60.110"
PG_PORT="5432"
PG_USER="odoo"
PG_PWD="cnV2abjbDpbh64e12987wR4mj5kQ3456Y0Qf"
DB_NAME="$DB_NAME"
IDLE_THRESHOLD="30 minutes"  # Connections idle more than this will be terminated

# Export password for use with psql
export PGPASSWORD="\$PG_PWD"

# Get a list of connections idle for more than the threshold
IDLE_CONNECTIONS=\$(psql -h "\$PG_HOST" -p "\$PG_PORT" -U "\$PG_USER" -t -c "
SELECT pid 
FROM pg_stat_activity 
WHERE state = 'idle' 
  AND application_name LIKE 'odoo%' 
  AND datname = '\$DB_NAME'
  AND current_timestamp - state_change > interval '\$IDLE_THRESHOLD'
")

# Terminate each idle connection
for PID in \$IDLE_CONNECTIONS; do
  if [ ! -z "\$PID" ]; then
    echo "Terminating idle connection with PID: \$PID"
    psql -h "\$PG_HOST" -p "\$PG_PORT" -U "\$PG_USER" -c "SELECT pg_terminate_backend(\$PID)"
  fi
done

# Count remaining connections
CONN_COUNT=\$(psql -h "\$PG_HOST" -p "\$PG_PORT" -U "\$PG_USER" -t -c "
SELECT count(*) 
FROM pg_stat_activity 
WHERE datname = '\$DB_NAME'
")

echo "Remaining connections for \$DB_NAME: \$CONN_COUNT"
EOCLEAN

# Make cleanup script executable
chmod +x "/opt/scripts/cleanup-postgres-$TENANT.sh"

# Add cron job for cleanup
(crontab -l 2>/dev/null || echo "") | grep -v "cleanup-postgres-$TENANT.sh" | { cat; echo "0 * * * * /opt/scripts/cleanup-postgres-$TENANT.sh > /var/log/cleanup-postgres-$TENANT.log 2>&1"; } | crontab -

# Create monitoring script for the tenant
cat > "/opt/scripts/monitor-$TENANT.sh" << EOMON
#!/bin/bash
# Monitor Odoo tenant: $TENANT
# Will restart service if not responding or has too many SSL errors

# Configuration
TENANT="$TENANT"
TENANT_DIR="$TENANT_DIR"
HTTP_PORT="$HTTP_PORT"

# Check if container is running
CONTAINER_RUNNING=\$(docker ps --filter name=odoo-\${TENANT} --filter status=running -q)
if [ -z "\$CONTAINER_RUNNING" ]; then
  echo "Container not running. Restarting..."
  cd "\$TENANT_DIR"
  docker-compose down
  sleep 5
  docker-compose up -d
  exit 0
fi

# Check for responsiveness
if ! curl -s -o /dev/null -w "%{http_code}" http://localhost:\$HTTP_PORT/web/webclient/version_info | grep -q "200"; then
  echo "Odoo not responding. Restarting..."
  cd "\$TENANT_DIR"
  docker-compose restart
  exit 0
fi

# Check for excessive SSL errors
SSL_ERRORS=\$(docker logs --since 5m odoo-\${TENANT}_odoo-\${TENANT}_1 2>&1 | grep -c "SSL SYSCALL error" || echo "0")
if [ "\$SSL_ERRORS" -gt 10 ]; then
  echo "Excessive SSL errors (\$SSL_ERRORS). Restarting..."
  cd "\$TENANT_DIR"
  docker-compose restart
  exit 0
fi

# Check for connection pool issues
POOL_ERRORS=\$(docker logs --since 5m odoo-\${TENANT}_odoo-\${TENANT}_1 2>&1 | grep -c "The Connection Pool Is Full" || echo "0")
if [ "\$POOL_ERRORS" -gt 5 ]; then
  echo "Connection pool issues (\$POOL_ERRORS). Restarting..."
  cd "\$TENANT_DIR"
  docker-compose restart
  
  # Run the database cleanup script to free connections
  /opt/scripts/cleanup-postgres-\$TENANT.sh
  exit 0
fi

echo "Tenant \$TENANT check completed. Service is healthy."
EOMON

# Make monitoring script executable
chmod +x "/opt/scripts/monitor-$TENANT.sh"

# Add cron job for monitoring
(crontab -l 2>/dev/null || echo "") | grep -v "monitor-$TENANT.sh" | { cat; echo "*/10 * * * * /opt/scripts/monitor-$TENANT.sh > /var/log/monitor-$TENANT.log 2>&1"; } | crontab -

# Restart Nginx
systemctl restart nginx

echo "Tenant $TENANT has been created successfully!"
echo "You can access it at https://$TENANT.arcweb.com.au"
echo ""
echo "Shared addons path: /opt/odoo-addons/shared"
echo "Tenant-specific addons path: /opt/odoo-addons/tenant-specific/$TENANT"
echo ""
echo "Connection pool monitoring has been set up at:"
echo "  - Cleanup script: /opt/scripts/cleanup-postgres-$TENANT.sh (runs hourly)"
echo "  - Monitoring script: /opt/scripts/monitor-$TENANT.sh (runs every 10 minutes)"
