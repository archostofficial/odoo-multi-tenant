#!/bin/bash

# Script to create a new Odoo tenant with a custom domain
# Usage: ./create-custom-domain-tenant.sh domain_name database_name ssl_email

if [ "$#" -lt 3 ]; then
    echo "Usage: $0 domain_name database_name ssl_email [tenant_name]"
    echo "Example: $0 example.com odoo_example info@example.com example"
    echo "Note: tenant_name is optional. If not provided, the domain name will be used (without TLD)."
    exit 1
fi

DOMAIN=$1
DB_NAME=$2
SSL_EMAIL=$3
TENANT=${4:-$(echo $DOMAIN | cut -d. -f1)}

# Generate random ports for this instance
BASE_PORT=$((8090 + RANDOM % 100))  # Random port between 8090-8190
HTTP_PORT=$BASE_PORT
HTTPS_PORT=$((BASE_PORT+1))
CHAT_PORT=$((BASE_PORT+2))

echo "Creating new tenant with custom domain: $DOMAIN"
echo "Database name: $DB_NAME"
echo "Tenant name: $TENANT"
echo "Ports: HTTP=$HTTP_PORT, HTTPS=$HTTPS_PORT, Chat=$CHAT_PORT"

# Create directories
TENANT_DIR="/opt/odoo-$TENANT"

# Check if directory already exists
if [ -d "$TENANT_DIR" ]; then
    echo "Warning: Tenant directory already exists. Removing it to start fresh."
    rm -rf "$TENANT_DIR"
fi

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
db_name = $DB_NAME
db_sslmode = prefer
db_maxconn = 64
db_thread = True
db_pooler = True
proxy_mode = True
website_name = $DOMAIN
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

# Create docker-compose.yml with optimized settings
cat > "$TENANT_DIR/docker-compose.yml" << EOF
version: '3'
services:
  odoo-$TENANT:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "$HTTP_PORT:8069"
      - "$HTTPS_PORT:8071"
      - "$CHAT_PORT:8072"
    volumes:
      - odoo-$TENANT-data:/var/lib/odoo
      - /opt/odoo-addons/shared:/mnt/shared-addons
      - /opt/odoo-addons/tenant-specific/$TENANT:/mnt/extra-addons
      - ./odoo.conf:/etc/odoo/odoo.conf:ro
    environment:
      - HOST=192.168.60.110
      - PORT=5432
      - USER=odoo
      - PASSWORD=cnV2abjbDpbh64e12987wR4mj5kQ3456Y0Qf
      - DB_NAME=$DB_NAME
      - VIRTUAL_HOST=$DOMAIN
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
    networks:
      - odoo-network
      - nginx-network

volumes:
  odoo-$TENANT-data:
    name: odoo-$TENANT-data

networks:
  odoo-network:
    internal: true
  nginx-network:
    external: true
EOF

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

# Check if SSL certificate exists, if not, obtain one
if [ ! -d "/etc/letsencrypt/live/$DOMAIN" ]; then
    echo "Obtaining SSL certificate for $DOMAIN..."
    
    # Ask if wildcard certificate is needed
    echo "Do you want to generate a wildcard certificate for *.$DOMAIN? [y/N]"
    read -r wildcard
    
    if [[ "$wildcard" == "y" || "$wildcard" == "Y" ]]; then
        certbot certonly --manual --preferred-challenges dns \
          -d $DOMAIN -d *.$DOMAIN \
          --agree-tos -m $SSL_EMAIL
          
        echo "Please follow the instructions from certbot to complete DNS challenge."
    else
        certbot certonly --nginx -d $DOMAIN -d www.$DOMAIN --email $SSL_EMAIL --agree-tos --non-interactive
    fi
    
    if [ $? -ne 0 ]; then
        echo "Warning: Failed to obtain SSL certificate. Creating a self-signed certificate for now."
        # Create directory for certificates if it doesn't exist
        mkdir -p /etc/letsencrypt/live/$DOMAIN
        
        # Generate a self-signed certificate
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
          -keyout /etc/letsencrypt/live/$DOMAIN/privkey.pem \
          -out /etc/letsencrypt/live/$DOMAIN/fullchain.pem \
          -subj "/CN=$DOMAIN/O=Odoo/C=US" \
          -addext "subjectAltName = DNS:$DOMAIN,DNS:www.$DOMAIN"
        
        echo "Self-signed certificate created. This is only for development/testing environments."
        echo "For production, you should replace these with Let's Encrypt certificates later."
    fi
fi

# Create Nginx configuration file with WebSocket optimizations
cat > "/etc/nginx/sites-available/$DOMAIN.conf" << EOF
map \$http_upgrade \$connection_upgrade {
  default upgrade;
  ''      close;
}

# $TENANT Odoo server
upstream odoo_$TENANT {
   server 127.0.0.1:$HTTP_PORT;
}
upstream odoochat_$TENANT {
   server 127.0.0.1:$CHAT_PORT;
}

# HTTP redirect to HTTPS
server {
   listen 80;
   server_name $DOMAIN www.$DOMAIN;
   
   # Redirect to HTTPS
   return 301 https://\$host\$request_uri;
}

# $TENANT tenant ($DOMAIN)
server {
   listen 443 ssl http2;
   server_name $DOMAIN www.$DOMAIN;

   ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
   ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

   # log
   access_log /var/log/nginx/$DOMAIN.access.log;
   error_log /var/log/nginx/$DOMAIN.error.log;

   # Increased timeouts for WebSocket connections
   proxy_read_timeout 720s;
   proxy_connect_timeout 720s;
   proxy_send_timeout 720s;
   
   # Improved buffer settings for WebSocket
   proxy_buffers 16 64k;
   proxy_buffer_size 128k;

   # Redirect websocket requests
   location /websocket {
      proxy_pass http://odoochat_$TENANT;
      proxy_http_version 1.1;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection \$connection_upgrade;
      proxy_set_header X-Forwarded-Host \$host;
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto \$scheme;
      proxy_set_header X-Real-IP \$remote_addr;
      proxy_read_timeout 600s;
      proxy_connect_timeout 600s;
      proxy_buffering off;
   }

   # Redirect longpoll requests
   location /longpolling {
      proxy_pass http://odoochat_$TENANT;
      proxy_http_version 1.1;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection \$connection_upgrade;
      proxy_set_header X-Forwarded-Host \$host;
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto \$scheme;
      proxy_set_header X-Real-IP \$remote_addr;
      proxy_read_timeout 600s;
      proxy_connect_timeout 600s;
      proxy_buffering off;
   }

   # Redirect requests to odoo backend server
   location / {
      # Add Headers for odoo proxy mode
      proxy_set_header X-Forwarded-Host \$host;
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto \$scheme;
      proxy_set_header X-Real-IP \$remote_addr;
      proxy_redirect off;
      proxy_pass http://odoo_$TENANT;
      proxy_http_version 1.1;
      client_max_body_size 512M;
   }

   location ~* /web/static/ {
      proxy_cache_valid 200 90m;
      proxy_buffering on;
      expires 864000;
      proxy_pass http://odoo_$TENANT;
   }

   # Restrict access to database manager for security
   location ~* /web/database/manager {
      # Allow only specific IPs to access this path
      # allow 192.168.1.0/24;
      # deny all;
      proxy_pass http://odoo_$TENANT;
   }

   # common gzip
   gzip_types text/css text/scss text/plain text/xml application/xml application/json application/javascript;
   gzip on;
}
EOF

# Enable the site
ln -sf "/etc/nginx/sites-available/$DOMAIN.conf" /etc/nginx/sites-enabled/

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
mkdir -p "/opt/scripts"
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
# Monitor Odoo tenant: $TENANT (domain: $DOMAIN)
# Will restart service if not responding or has too many SSL errors

# Configuration
TENANT="$TENANT"
TENANT_DIR="$TENANT_DIR"
HTTP_PORT="$HTTP_PORT"
DOMAIN="$DOMAIN"

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
SSL_ERRORS=\$(docker logs --since 5m odoo-\${TENANT} 2>&1 | grep -c "SSL SYSCALL error" || echo "0")
if [ "\$SSL_ERRORS" -gt 10 ]; then
  echo "Excessive SSL errors (\$SSL_ERRORS). Restarting..."
  cd "\$TENANT_DIR"
  docker-compose restart
  exit 0
fi

# Check for connection pool issues
POOL_ERRORS=\$(docker logs --since 5m odoo-\${TENANT} 2>&1 | grep -c "The Connection Pool Is Full" || echo "0")
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

echo "==================================================================================="
echo "Tenant $TENANT with custom domain $DOMAIN has been created successfully!"
echo "==================================================================================="
echo ""
echo "You can access it at:"
echo "  https://$DOMAIN"
echo ""
echo "Important details:"
echo "  - Database: $DB_NAME"
echo "  - Ports: HTTP=$HTTP_PORT, HTTPS=$HTTPS_PORT, Chat=$CHAT_PORT"
echo "  - Tenant directory: $TENANT_DIR"
echo "  - Tenant-specific addons path: /opt/odoo-addons/tenant-specific/$TENANT"
echo "  - Shared addons path: /opt/odoo-addons/shared"
echo ""
echo "DNS Requirements:"
echo "  Make sure your DNS records point to this server:"
echo "  - $DOMAIN -> YOUR_SERVER_IP"
echo "  - www.$DOMAIN -> YOUR_SERVER_IP"
echo ""
echo "Maintenance commands:"
echo "  - View logs: docker-compose -f $TENANT_DIR/docker-compose.yml logs -f"
echo "  - Restart: docker-compose -f $TENANT_DIR/docker-compose.yml restart"
echo ""
echo "Maintenance scripts:"
echo "  - Connection pool monitoring has been set up at:"
echo "    * Cleanup script: /opt/scripts/cleanup-postgres-$TENANT.sh (runs hourly)"
echo "    * Monitoring script: /opt/scripts/monitor-$TENANT.sh (runs every 10 minutes)"
echo ""
echo "To install Odoo Enterprise modules for this tenant:"
echo "  /opt/scripts/install-enterprise.sh $TENANT"
echo ""
