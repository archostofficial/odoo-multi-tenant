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
mkdir -p "$TENANT_DIR/18.0"
mkdir -p "/opt/odoo-addons/tenant-specific/$TENANT"

# Create docker-compose.yml
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
    environment:
      - HOST=192.168.60.110
      - PORT=5432
      - USER=odoo
      - PASSWORD=cnV2abjbDpbh64e12987wR4mj5kQ3456Y0Qf
      - DB_NAME=DB_NAME_PLACEHOLDER
      - VIRTUAL_HOST=TENANT_PLACEHOLDER.arcweb.com.au
      - VIRTUAL_PORT=8069
      - PGSSLMODE=prefer
      - DB_MAXCONN=2
    command: ["odoo", "--without-demo=all", "--workers=2", "--proxy-mode", "--max-cron-threads=1"]
    restart: always

volumes:
  odoo-TENANT_PLACEHOLDER-data:
EODCF

# Replace placeholders
sed -i "s/TENANT_PLACEHOLDER/$TENANT/g" "$TENANT_DIR/docker-compose.yml"
sed -i "s/HTTP_PORT_PLACEHOLDER/$HTTP_PORT/g" "$TENANT_DIR/docker-compose.yml"
sed -i "s/HTTPS_PORT_PLACEHOLDER/$HTTPS_PORT/g" "$TENANT_DIR/docker-compose.yml"
sed -i "s/CHAT_PORT_PLACEHOLDER/$CHAT_PORT/g" "$TENANT_DIR/docker-compose.yml"
sed -i "s/DB_NAME_PLACEHOLDER/$DB_NAME/g" "$TENANT_DIR/docker-compose.yml"

# Create odoo.conf
cat > "$TENANT_DIR/18.0/odoo.conf" << 'EOCNF'
[options]
addons_path = /mnt/shared-addons,/mnt/extra-addons
data_dir = /var/lib/odoo
db_host = 192.168.60.110
db_port = 5432
db_user = odoo
db_password = cnV2abjbDpbh64e12987wR4mj5kQ3456Y0Qf
db_name = DB_NAME_PLACEHOLDER
db_sslmode = prefer
db_maxconn = 2
proxy_mode = True
website_name = TENANT_PLACEHOLDER.arcweb.com.au
without_demo = all

; server parameters
limit_memory_hard = 2684354560
limit_memory_soft = 2147483648
limit_request = 8192
limit_time_cpu = 120
limit_time_real = 240
max_cron_threads = 1
workers = 2
EOCNF

# Replace placeholders
sed -i "s/TENANT_PLACEHOLDER/$TENANT/g" "$TENANT_DIR/18.0/odoo.conf"
sed -i "s/DB_NAME_PLACEHOLDER/$DB_NAME/g" "$TENANT_DIR/18.0/odoo.conf"

# Copy configuration file to build context root (needed for Docker build)
cp "$TENANT_DIR/18.0/odoo.conf" "$TENANT_DIR/odoo.conf"

# Copy Dockerfile from main instance
cp /opt/odoo/Dockerfile "$TENANT_DIR/"

# Copy and prepare entrypoint script
cp /opt/odoo/entrypoint.sh "$TENANT_DIR/entrypoint.sh"
chmod +x "$TENANT_DIR/entrypoint.sh"

# Copy wait-for-psql.py
cp /opt/odoo/wait-for-psql.py "$TENANT_DIR/wait-for-psql.py"
chmod +x "$TENANT_DIR/wait-for-psql.py"

# Check if PostgreSQL client is installed
if ! command -v psql &> /dev/null; then
    echo "PostgreSQL client not found, installing..."
    apt-get update
    apt-get install -y postgresql-client
fi

# Create or replace the database
echo "Initializing database..."
# Use docker to run PostgreSQL commands to ensure we have the client available
docker run --rm postgres:latest psql "postgresql://odoo:cnV2abjbDpbh64e12987wR4mj5kQ3456Y0Qf@192.168.60.110:5432/postgres" -c "DROP DATABASE IF EXISTS $DB_NAME;" || echo "Failed to drop database, it may not exist."
docker run --rm postgres:latest psql "postgresql://odoo:cnV2abjbDpbh64e12987wR4mj5kQ3456Y0Qf@192.168.60.110:5432/postgres" -c "CREATE DATABASE $DB_NAME OWNER odoo;" || echo "Failed to create database. Check PostgreSQL connection."

# Create Nginx configuration file
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

   proxy_read_timeout 720s;
   proxy_connect_timeout 720s;
   proxy_send_timeout 720s;

   # Redirect websocket requests
   location /websocket {
      proxy_pass http://odoochat_TENANT_PLACEHOLDER;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection $connection_upgrade;
      proxy_set_header X-Forwarded-Host $host;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
      proxy_set_header X-Real-IP $remote_addr;
   }

   # Redirect longpoll requests
   location /longpolling {
      proxy_pass http://odoochat_TENANT_PLACEHOLDER;
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

# Validate Nginx configuration
nginx -t

# Start the container
echo "Starting the new tenant..."
cd "$TENANT_DIR"
docker-compose down || true  # Make sure any existing container is stopped
docker-compose up -d

# Verify container is running
echo "Verifying container is running..."
sleep 5
CONTAINER_RUNNING=$(docker-compose ps --services --filter "status=running" | grep "odoo-$TENANT")
if [ -z "$CONTAINER_RUNNING" ]; then
    echo "Warning: Container may not be running properly. Checking logs..."
    docker-compose logs --tail=50
    
    echo "Attempting to restart container..."
    docker-compose restart
    
    sleep 5
    CONTAINER_RUNNING=$(docker-compose ps --services --filter "status=running" | grep "odoo-$TENANT")
    if [ -z "$CONTAINER_RUNNING" ]; then
        echo "Error: Container still not running. Please check logs for detailed error information."
    else
        echo "Container successfully restarted."
    fi
else
    echo "Container is running properly."
fi

echo "Initializing the database with essential modules..."
# Add -i flag to initialize with full database creation instead of using existing database
docker-compose run --rm odoo-$TENANT odoo -i base,web,mail -d $DB_NAME --db_host 192.168.60.110 --db_port 5432 --db_user odoo --db_password cnV2abjbDpbh64e12987wR4mj5kQ3456Y0Qf --without-demo=all --stop-after-init

# Restart Nginx if configuration is valid
if nginx -t; then
    systemctl restart nginx
    echo "Nginx configuration updated and restarted."
else
    echo "Warning: Nginx configuration test failed. Please check your configuration."
fi

echo "Tenant $TENANT has been created successfully!"
echo "You can access it at https://$TENANT.arcweb.com.au"
echo ""
echo "Shared addons path: /opt/odoo-addons/shared"
echo "Tenant-specific addons path: /opt/odoo-addons/tenant-specific/$TENANT"
