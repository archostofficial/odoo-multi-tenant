#!/bin/bash

# This script sets up a custom domain with its own Odoo instance

if [ "$#" -lt 3 ]; then
    echo "Usage: $0 domain_name database_name ssl_email [container_name]"
    echo "Example: $0 example.com odoo_example info@example.com example"
    echo "Note: container_name is optional. If not provided, the domain name will be used."
    exit 1
fi

DOMAIN=$1
DB_NAME=$2
SSL_EMAIL=$3
CONTAINER_NAME=${4:-$(echo $DOMAIN | cut -d. -f1)}

echo "Setting up Odoo for custom domain: $DOMAIN"
echo "Database name: $DB_NAME"
echo "Container name: $CONTAINER_NAME"
echo "SSL Email: $SSL_EMAIL"

# Generate random ports for this instance
BASE_PORT=$((8200 + RANDOM % 300))  # Random port between 8200-8500
HTTP_PORT=$BASE_PORT
HTTPS_PORT=$((BASE_PORT+1))
CHAT_PORT=$((BASE_PORT+2))

echo "Ports: HTTP=$HTTP_PORT, HTTPS=$HTTPS_PORT, Chat=$CHAT_PORT"

# Create directory structure
TENANT_DIR="/opt/odoo-$CONTAINER_NAME"

# Check if directory already exists
if [ -d "$TENANT_DIR" ]; then
    echo "Warning: Directory already exists. Removing it to start fresh."
    rm -rf "$TENANT_DIR"
fi

mkdir -p "$TENANT_DIR/18.0" "$TENANT_DIR/addons"

# Create docker-compose.yml
cat > "$TENANT_DIR/docker-compose.yml" << EOF
version: '3'
services:
  odoo-$CONTAINER_NAME:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "$HTTP_PORT:8069"
      - "$HTTPS_PORT:8071"
      - "$CHAT_PORT:8072"
    volumes:
      - odoo-$CONTAINER_NAME-data:/var/lib/odoo
      - ./addons:/mnt/extra-addons
    environment:
      - HOST=192.168.60.110
      - PORT=5432
      - USER=odoo
      - PASSWORD=cnV2abjbDpbh64e12987wR4mj5kQ3456Y0Qf
      - DB_NAME=$DB_NAME
      - VIRTUAL_HOST=$DOMAIN
      - VIRTUAL_PORT=8069
      - PGSSLMODE=prefer
      - DB_MAXCONN=2
    command: ["odoo", "--without-demo=all", "--max-cron-threads=0"]
    restart: always

volumes:
  odoo-$CONTAINER_NAME-data:
EOF

# Create odoo.conf
cat > "$TENANT_DIR/18.0/odoo.conf" << EOF
[options]
addons_path = /mnt/extra-addons
data_dir = /var/lib/odoo
db_host = 192.168.60.110
db_port = 5432
db_user = odoo
db_password = cnV2abjbDpbh64e12987wR4mj5kQ3456Y0Qf
db_name = $DB_NAME
db_sslmode = prefer
db_maxconn = 2
proxy_mode = True
website_name = $DOMAIN
without_demo = all

; server parameters
limit_memory_hard = 2684354560
limit_memory_soft = 2147483648
limit_request = 8192
limit_time_cpu = 120
limit_time_real = 240
max_cron_threads = 0
workers = 2
EOF

# Copy required files
cp /opt/odoo/Dockerfile "$TENANT_DIR/"
cp /opt/odoo/18.0/entrypoint.sh "$TENANT_DIR/18.0/"
cp /opt/odoo/18.0/wait-for-psql.py "$TENANT_DIR/18.0/"

# Create or replace the database
echo "Creating database $DB_NAME..."
PGPASSWORD=cnV2abjbDpbh64e12987wR4mj5kQ3456Y0Qf psql -h 192.168.60.110 -U odoo -c "DROP DATABASE IF EXISTS $DB_NAME;"
PGPASSWORD=cnV2abjbDpbh64e12987wR4mj5kQ3456Y0Qf psql -h 192.168.60.110 -U odoo -c "CREATE DATABASE $DB_NAME OWNER odoo;"

# Check if SSL certificate exists, if not, obtain one
if [ ! -d "/etc/letsencrypt/live/$DOMAIN" ]; then
    echo "Obtaining SSL certificate for $DOMAIN..."
    certbot certonly --nginx -d $DOMAIN -d www.$DOMAIN --email $SSL_EMAIL --agree-tos --non-interactive
fi

# Create Nginx configuration file
cat > "/etc/nginx/sites-available/$DOMAIN.conf" << EOF
map \$http_upgrade \$connection_upgrade {
  default upgrade;
  ''      close;
}

# $CONTAINER_NAME Odoo server
upstream odoo_$CONTAINER_NAME {
   server 127.0.0.1:$HTTP_PORT;
}
upstream odoochat_$CONTAINER_NAME {
   server 127.0.0.1:$CHAT_PORT;
}

# HTTP redirect to HTTPS
server {
   listen 80;
   server_name $DOMAIN www.$DOMAIN;
   
   # Redirect to HTTPS
   return 301 https://\$host\$request_uri;
}

# $CONTAINER_NAME tenant ($DOMAIN)
server {
   listen 443 ssl http2;
   server_name $DOMAIN www.$DOMAIN;

   ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
   ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

   # log
   access_log /var/log/nginx/$DOMAIN.access.log;
   error_log /var/log/nginx/$DOMAIN.error.log;

   proxy_read_timeout 720s;
   proxy_connect_timeout 720s;
   proxy_send_timeout 720s;

   # Redirect websocket requests
   location /websocket {
      proxy_pass http://odoochat_$CONTAINER_NAME;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection \$connection_upgrade;
      proxy_set_header X-Forwarded-Host \$host;
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto \$scheme;
      proxy_set_header X-Real-IP \$remote_addr;
   }

   # Redirect longpoll requests
   location /longpolling {
      proxy_pass http://odoochat_$CONTAINER_NAME;
   }

   # Redirect requests to odoo backend server
   location / {
      # Add Headers for odoo proxy mode
      proxy_set_header X-Forwarded-Host \$host;
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto \$scheme;
      proxy_set_header X-Real-IP \$remote_addr;
      proxy_redirect off;
      proxy_pass http://odoo_$CONTAINER_NAME;
      client_max_body_size 512M;
   }

   location ~* /web/static/ {
      proxy_cache_valid 200 90m;
      proxy_buffering on;
      expires 864000;
      proxy_pass http://odoo_$CONTAINER_NAME;
   }

   # common gzip
   gzip_types text/css text/scss text/plain text/xml application/xml application/json application/javascript;
   gzip on;
}
EOF

# Enable the Nginx configuration
ln -sf "/etc/nginx/sites-available/$DOMAIN.conf" /etc/nginx/sites-enabled/

echo "Starting the new Odoo instance for $DOMAIN..."
cd "$TENANT_DIR"
docker-compose up -d

echo "Initializing the database without demo data..."
docker-compose run --rm odoo-$CONTAINER_NAME odoo --init base --database $DB_NAME --db_host 192.168.60.110 --db_port 5432 --db_user odoo --db_password cnV2abjbDpbh64e12987wR4mj5kQ3456Y0Qf --without-demo=all

# Test and restart Nginx
nginx -t && systemctl restart nginx

echo ""
echo "==================================================="
echo "Custom domain Odoo setup completed!"
echo "==================================================="
echo ""
echo "Domain: $DOMAIN"
echo "Database: $DB_NAME"
echo "Ports: HTTP=$HTTP_PORT, HTTPS=$HTTPS_PORT, Chat=$CHAT_PORT"
echo ""
echo "1. Make sure your DNS records point to this server:"
echo "   - $DOMAIN -> YOUR_SERVER_IP"
echo "   - www.$DOMAIN -> YOUR_SERVER_IP"
echo ""
echo "2. Access your Odoo instance at:"
echo "   https://$DOMAIN"
echo ""
echo "3. Container directory:"
echo "   $TENANT_DIR"
echo ""
echo "4. For troubleshooting, check the logs with:"
echo "   docker-compose -f $TENANT_DIR/docker-compose.yml logs -f"
echo "   tail -f /var/log/nginx/$DOMAIN.error.log"
echo ""
