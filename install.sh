#!/bin/bash
# Odoo Multi-Tenant Docker Setup Installer
# This script sets up the complete environment for running multiple Odoo instances

set -e

# Color codes for pretty output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Display banner
echo -e "${BLUE}"
echo "==============================================================="
echo "              Odoo Multi-Tenant Docker Setup                   "
echo "==============================================================="
echo -e "${NC}"

# Check if running as root
if [ "$(id -u)" != "0" ]; then
   echo -e "${RED}This script must be run as root${NC}" 
   exit 1
fi

# Base directory for the setup
BASE_DIR="/opt"
ODOO_DIR="${BASE_DIR}/odoo"
ADDONS_DIR="${BASE_DIR}/odoo-addons"
SCRIPTS_DIR="${BASE_DIR}/scripts"
ENTERPRISE_DIR="${ADDONS_DIR}/enterprise"

# Global variables for SSL
DOMAIN="arcweb.com.au"
USE_WILDCARD=false
SSL_EMAIL=""

# Update Dockerfiles to fix repository and curl issues
update_dockerfiles() {
    echo -e "${GREEN}Updating Dockerfiles to fix repository and curl issues...${NC}"
    
    # Update Dockerfile in main directory
    cat > docker/main/Dockerfile << 'EOF'
FROM ubuntu:noble
MAINTAINER Odoo S.A. <info@odoo.com>

SHELL ["/bin/bash", "-xo", "pipefail", "-c"]

# Generate locale C.UTF-8 for postgres and general locale data
ENV LANG en_US.UTF-8

# Retrieve the target architecture to install the correct wkhtmltopdf package
ARG TARGETARCH

# Fix for Ubuntu Noble time-related issues
RUN echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid
RUN echo 'Acquire::Check-Date "false";' >> /etc/apt/apt.conf.d/99no-check-valid

# Install some deps, lessc and less-plugin-clean-css, and wkhtmltopdf
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates && \
    apt-get install -y --no-install-recommends curl && \
    DEBIAN_FRONTEND=noninteractive \
    apt-get install -y --no-install-recommends \
        dirmngr \
        fonts-noto-cjk \
        gnupg \
        libssl-dev \
        node-less \
        npm \
        python3-magic \
        python3-num2words \
        python3-odf \
        python3-pdfminer \
        python3-pip \
        python3-phonenumbers \
        python3-pyldap \
        python3-qrcode \
        python3-renderpm \
        python3-setuptools \
        python3-slugify \
        python3-vobject \
        python3-watchdog \
        python3-xlrd \
        python3-xlwt \
        xz-utils \
        python3-psycopg2 && \
    if [ -z "${TARGETARCH}" ]; then \
        TARGETARCH="$(dpkg --print-architecture)"; \
    fi; \
    WKHTMLTOPDF_ARCH=${TARGETARCH} && \
    case ${TARGETARCH} in \
    "amd64") WKHTMLTOPDF_ARCH=amd64 && WKHTMLTOPDF_SHA=967390a759707337b46d1c02452e2bb6b2dc6d59  ;; \
    "arm64")  WKHTMLTOPDF_SHA=90f6e69896d51ef77339d3f3a20f8582bdf496cc  ;; \
    "ppc64le" | "ppc64el") WKHTMLTOPDF_ARCH=ppc64el && WKHTMLTOPDF_SHA=5312d7d34a25b321282929df82e3574319aed25c  ;; \
    esac \
    && curl -o wkhtmltox.deb -sSL https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_${WKHTMLTOPDF_ARCH}.deb \
    && echo ${WKHTMLTOPDF_SHA} wkhtmltox.deb | sha1sum -c - \
    && apt-get install -y --no-install-recommends ./wkhtmltox.deb \
    && rm -rf /var/lib/apt/lists/* wkhtmltox.deb

# Install latest postgresql-client
RUN echo 'deb http://apt.postgresql.org/pub/repos/apt/ noble-pgdg main' > /etc/apt/sources.list.d/pgdg.list \
    && GNUPGHOME="$(mktemp -d)" \
    && export GNUPGHOME \
    && repokey='B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8' \
    && gpg --batch --keyserver keyserver.ubuntu.com --recv-keys "${repokey}" \
    && gpg --batch --armor --export "${repokey}" > /etc/apt/trusted.gpg.d/pgdg.gpg.asc \
    && gpgconf --kill all \
    && rm -rf "$GNUPGHOME" \
    && apt-get update  \
    && apt-get install --no-install-recommends -y postgresql-client \
    && rm -f /etc/apt/sources.list.d/pgdg.list \
    && rm -rf /var/lib/apt/lists/*

# Install rtlcss (on Debian buster)
RUN npm install -g rtlcss

# Install gevent for websocket support
RUN apt-get update && apt-get install -y python3-gevent && rm -rf /var/lib/apt/lists/*

# Install Odoo
ENV ODOO_VERSION 18.0
ARG ODOO_RELEASE=20250311
ARG ODOO_SHA=de629e8416caca2475aa59cf73049fc89bf5ea5b
RUN curl -o odoo.deb -sSL http://nightly.odoo.com/${ODOO_VERSION}/nightly/deb/odoo_${ODOO_VERSION}.${ODOO_RELEASE}_all.deb \
    && echo "${ODOO_SHA} odoo.deb" | sha1sum -c - \
    && apt-get update \
    && apt-get -y install --no-install-recommends ./odoo.deb \
    && rm -rf /var/lib/apt/lists/* odoo.deb

# Copy configuration files
COPY ./odoo.conf /etc/odoo/
COPY ./entrypoint.sh /entrypoint.sh
COPY ./wait-for-psql.py /usr/local/bin/wait-for-psql.py

# Set permissions and create directories
RUN chmod +x /entrypoint.sh /usr/local/bin/wait-for-psql.py \
    && chown odoo /etc/odoo/odoo.conf \
    && mkdir -p /mnt/extra-addons /mnt/shared-addons \
    && chown -R odoo /mnt/extra-addons /mnt/shared-addons

# Mount volumes
VOLUME ["/var/lib/odoo", "/mnt/extra-addons", "/mnt/shared-addons"]

# Expose Odoo services
EXPOSE 8069 8071 8072

# Set the default config file
ENV ODOO_RC /etc/odoo/odoo.conf

# Set default user when running the container
USER odoo

ENTRYPOINT ["/entrypoint.sh"]
CMD ["odoo"]
EOF

    # Update Dockerfile in tenant-template directory
    cat > docker/tenant-template/Dockerfile << 'EOF'
FROM ubuntu:noble
MAINTAINER Odoo S.A. <info@odoo.com>

SHELL ["/bin/bash", "-xo", "pipefail", "-c"]

# Generate locale C.UTF-8 for postgres and general locale data
ENV LANG en_US.UTF-8

# Retrieve the target architecture to install the correct wkhtmltopdf package
ARG TARGETARCH

# Fix for Ubuntu Noble time-related issues
RUN echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid
RUN echo 'Acquire::Check-Date "false";' >> /etc/apt/apt.conf.d/99no-check-valid

# Install some deps, lessc and less-plugin-clean-css, and wkhtmltopdf
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates && \
    apt-get install -y --no-install-recommends curl && \
    DEBIAN_FRONTEND=noninteractive \
    apt-get install -y --no-install-recommends \
        dirmngr \
        fonts-noto-cjk \
        gnupg \
        libssl-dev \
        node-less \
        npm \
        python3-magic \
        python3-num2words \
        python3-odf \
        python3-pdfminer \
        python3-pip \
        python3-phonenumbers \
        python3-pyldap \
        python3-qrcode \
        python3-renderpm \
        python3-setuptools \
        python3-slugify \
        python3-vobject \
        python3-watchdog \
        python3-xlrd \
        python3-xlwt \
        xz-utils \
        python3-psycopg2 && \
    if [ -z "${TARGETARCH}" ]; then \
        TARGETARCH="$(dpkg --print-architecture)"; \
    fi; \
    WKHTMLTOPDF_ARCH=${TARGETARCH} && \
    case ${TARGETARCH} in \
    "amd64") WKHTMLTOPDF_ARCH=amd64 && WKHTMLTOPDF_SHA=967390a759707337b46d1c02452e2bb6b2dc6d59  ;; \
    "arm64")  WKHTMLTOPDF_SHA=90f6e69896d51ef77339d3f3a20f8582bdf496cc  ;; \
    "ppc64le" | "ppc64el") WKHTMLTOPDF_ARCH=ppc64el && WKHTMLTOPDF_SHA=5312d7d34a25b321282929df82e3574319aed25c  ;; \
    esac \
    && curl -o wkhtmltox.deb -sSL https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_${WKHTMLTOPDF_ARCH}.deb \
    && echo ${WKHTMLTOPDF_SHA} wkhtmltox.deb | sha1sum -c - \
    && apt-get install -y --no-install-recommends ./wkhtmltox.deb \
    && rm -rf /var/lib/apt/lists/* wkhtmltox.deb

# Install latest postgresql-client
RUN echo 'deb http://apt.postgresql.org/pub/repos/apt/ noble-pgdg main' > /etc/apt/sources.list.d/pgdg.list \
    && GNUPGHOME="$(mktemp -d)" \
    && export GNUPGHOME \
    && repokey='B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8' \
    && gpg --batch --keyserver keyserver.ubuntu.com --recv-keys "${repokey}" \
    && gpg --batch --armor --export "${repokey}" > /etc/apt/trusted.gpg.d/pgdg.gpg.asc \
    && gpgconf --kill all \
    && rm -rf "$GNUPGHOME" \
    && apt-get update  \
    && apt-get install --no-install-recommends -y postgresql-client \
    && rm -f /etc/apt/sources.list.d/pgdg.list \
    && rm -rf /var/lib/apt/lists/*

# Install rtlcss (on Debian buster)
RUN npm install -g rtlcss

# Install gevent for websocket support
RUN apt-get update && apt-get install -y python3-gevent && rm -rf /var/lib/apt/lists/*

# Install Odoo
ENV ODOO_VERSION 18.0
ARG ODOO_RELEASE=20250311
ARG ODOO_SHA=de629e8416caca2475aa59cf73049fc89bf5ea5b
RUN curl -o odoo.deb -sSL http://nightly.odoo.com/${ODOO_VERSION}/nightly/deb/odoo_${ODOO_VERSION}.${ODOO_RELEASE}_all.deb \
    && echo "${ODOO_SHA} odoo.deb" | sha1sum -c - \
    && apt-get update \
    && apt-get -y install --no-install-recommends ./odoo.deb \
    && rm -rf /var/lib/apt/lists/* odoo.deb

# Copy configuration files
COPY ./odoo.conf /etc/odoo/
COPY ./entrypoint.sh /entrypoint.sh
COPY ./wait-for-psql.py /usr/local/bin/wait-for-psql.py

# Set permissions and create directories
RUN chmod +x /entrypoint.sh /usr/local/bin/wait-for-psql.py \
    && chown odoo /etc/odoo/odoo.conf \
    && mkdir -p /mnt/extra-addons /mnt/shared-addons \
    && chown -R odoo /mnt/extra-addons /mnt/shared-addons

# Mount volumes
VOLUME ["/var/lib/odoo", "/mnt/extra-addons", "/mnt/shared-addons"]

# Expose Odoo services
EXPOSE 8069 8071 8072

# Set the default config file
ENV ODOO_RC /etc/odoo/odoo.conf

# Set default user when running the container
USER odoo

ENTRYPOINT ["/entrypoint.sh"]
CMD ["odoo"]
EOF

    echo -e "${GREEN}Dockerfiles updated successfully.${NC}"
}

# Create environment variables template
create_env_template() {
    echo -e "${GREEN}Creating environment variables template...${NC}"
    
    cat > ${ODOO_DIR}/.env.template << 'EOF'
# PostgreSQL Settings
POSTGRES_HOST=192.168.60.110
POSTGRES_PORT=5432
POSTGRES_USER=odoo
POSTGRES_PASSWORD=generate_strong_password_here
POSTGRES_SSL_MODE=prefer

# Odoo Settings
ADMIN_PASSWORD=generate_different_strong_password_here
HTTP_PROXY_MODE=True
WORKERS=2
MAX_CRON_THREADS=1

# Backup Settings
BACKUP_RETENTION_DAYS=7
BACKUP_LOCATION=/opt/backups

# Domain Settings
BASE_DOMAIN=arcweb.com.au
EOF

    echo -e "${GREEN}Environment template created at ${ODOO_DIR}/.env.template${NC}"
    echo -e "${YELLOW}Remember to copy it to .env and update with your secure values${NC}"
}

# Create directory structure
create_directories() {
    echo -e "${GREEN}Creating directory structure...${NC}"
    
    mkdir -p ${ODOO_DIR}
    mkdir -p ${ADDONS_DIR}/shared
    mkdir -p ${ADDONS_DIR}/tenant-specific/main
    mkdir -p ${SCRIPTS_DIR}
    mkdir -p ${BASE_DIR}/backups
    
    echo -e "${GREEN}Directory structure created.${NC}"
}

# Copy configuration files
copy_config_files() {
    echo -e "${GREEN}Copying configuration files...${NC}"
    
    # Check if files already exist
    if [ -f "${ODOO_DIR}/docker-compose.yml" ]; then
        echo -e "${YELLOW}Configuration files already exist. Backup and override? [y/N]${NC}"
        read response
        if [[ "$response" != "y" && "$response" != "Y" ]]; then
            echo -e "${BLUE}Skipping configuration files...${NC}"
            return
        fi
        
        # Backup existing files
        BACKUP_TIME=$(date +%Y%m%d_%H%M%S)
        mkdir -p ${BASE_DIR}/backups/config_${BACKUP_TIME}
        cp -r ${ODOO_DIR}/* ${BASE_DIR}/backups/config_${BACKUP_TIME}/
        echo -e "${GREEN}Existing configuration backed up to ${BASE_DIR}/backups/config_${BACKUP_TIME}/${NC}"
    fi
    
    # Copy files from repository to their destinations
    cp -r docker/main/* ${ODOO_DIR}/
    
    echo -e "${GREEN}Configuration files copied.${NC}"
}

# Install enterprise integration script
install_enterprise_script() {
    echo -e "${GREEN}Setting up enterprise modules integration...${NC}"
    
    cat > ${SCRIPTS_DIR}/install-enterprise.sh << 'EOF'
#!/bin/bash
# Script to install Odoo Enterprise modules for a specific tenant
# Usage: ./install-enterprise.sh tenant_name [addon_path]

set -e

# Check if required parameters are provided
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 tenant_name [addon_path]"
    echo "Example: $0 app /opt/enterprise-addons"
    exit 1
fi

TENANT=$1
ADDON_PATH=${2:-"/opt/odoo-addons/enterprise"}
TENANT_DIR="/opt/odoo-$TENANT"

# Check if tenant directory exists
if [ ! -d "$TENANT_DIR" ]; then
    echo "Error: Tenant directory $TENANT_DIR does not exist."
    exit 1
fi

# Check if enterprise addon path exists, create if not
if [ ! -d "$ADDON_PATH" ]; then
    echo "Enterprise addons directory does not exist. Creating $ADDON_PATH..."
    mkdir -p "$ADDON_PATH"
fi

# Get database name from docker-compose.yml
DB_NAME=$(grep "DB_NAME=" "$TENANT_DIR/docker-compose.yml" | cut -d'=' -f2 | tr -d '"' | tr -d "'" | head -1)

if [ -z "$DB_NAME" ]; then
    echo "Error: Could not determine database name for tenant $TENANT"
    exit 1
fi

echo "Installing Odoo Enterprise modules for tenant: $TENANT"
echo "Database: $DB_NAME"
echo "Enterprise Addons Path: $ADDON_PATH"

# Check if enterprise repository exists
if [ ! -d "$ADDON_PATH/.git" ]; then
    echo "Cloning Odoo Enterprise repository..."
    
    # Prompt for GitHub credentials
    echo "Please enter your GitHub credentials for the Odoo Enterprise repository:"
    read -p "GitHub Username: " GITHUB_USER
    read -s -p "GitHub Token/Password: " GITHUB_TOKEN
    echo ""
    
    # Clone the enterprise repository
    git clone https://$GITHUB_USER:$GITHUB_TOKEN@github.com/odoo/enterprise.git $ADDON_PATH
    
    # Check out the correct branch (assuming same version as Odoo)
    cd $ADDON_PATH
    ODOO_VERSION=$(grep "ODOO_VERSION" "$TENANT_DIR/Dockerfile" | cut -d' ' -f3)
    git checkout $ODOO_VERSION
elif [ -d "$ADDON_PATH/.git" ]; then
    echo "Updating existing Odoo Enterprise repository..."
    cd $ADDON_PATH
    ODOO_VERSION=$(grep "ODOO_VERSION" "$TENANT_DIR/Dockerfile" | cut -d' ' -f3)
    git fetch
    git checkout $ODOO_VERSION
    git pull
fi

# Update addons path in odoo.conf
CONF_FILE="$TENANT_DIR/18.0/odoo.conf"
if [ -f "$CONF_FILE" ]; then
    # Check if enterprise path is already in addons_path
    if grep -q "addons_path" "$CONF_FILE"; then
        if ! grep -q "$ADDON_PATH" "$CONF_FILE"; then
            echo "Updating addons_path in odoo.conf..."
            CURRENT_PATH=$(grep "addons_path" "$CONF_FILE" | cut -d'=' -f2 | tr -d ' ')
            NEW_PATH="$CURRENT_PATH,$ADDON_PATH"
            sed -i "s|addons_path = .*|addons_path = $NEW_PATH|" "$CONF_FILE"
        else
            echo "Enterprise addons path already in odoo.conf"
        fi
    else
        echo "Adding addons_path to odoo.conf..."
        echo "addons_path = /mnt/shared-addons,/mnt/extra-addons,$ADDON_PATH" >> "$CONF_FILE"
    fi
else
    echo "Error: Configuration file $CONF_FILE not found."
    exit 1
fi

# Update container volume to mount enterprise addons
echo "Updating Docker container configuration..."
if ! grep -q "$ADDON_PATH" "$TENANT_DIR/docker-compose.yml"; then
    # Find the volumes section
    VOLUME_LINE=$(grep -n "volumes:" "$TENANT_DIR/docker-compose.yml" | cut -d':' -f1)
    if [ -n "$VOLUME_LINE" ]; then
        # Add enterprise volume after volumes line
        sed -i "$((VOLUME_LINE+3)) i\      - $ADDON_PATH:/mnt/enterprise-addons" "$TENANT_DIR/docker-compose.yml"
    else
        echo "Error: Could not find volumes section in docker-compose.yml"
        exit 1
    fi
else
    echo "Enterprise volume already configured in docker-compose.yml"
fi

# Create a dummy enterprise_code in database to avoid errors
echo "Setting up database to use enterprise modules..."
cd "$TENANT_DIR"

# Create a temporary Python script to prepare the database
cat > /tmp/prepare_enterprise.py << EOT
#!/usr/bin/env python3
import sys
import psycopg2

conn = None
try:
    # Connect to the database
    conn = psycopg2.connect(
        dbname="${DB_NAME}",
        user="odoo",
        password="cnV2abjbDpbh64e12987wR4mj5kQ3456Y0Qf",
        host="192.168.60.110",
        port="5432"
    )
    conn.autocommit = True
    cur = conn.cursor()
    
    # Check if ir_module_module table exists (to verify if this is an initialized database)
    cur.execute("SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name='ir_module_module')")
    table_exists = cur.fetchone()[0]
    
    if table_exists:
        # If database is initialized, update module list to include enterprise
        print("Database already initialized. Preparing for module updates.")
        
        # Make sure base module is marked for update
        cur.execute("UPDATE ir_module_module SET state='to upgrade' WHERE name='base'")
        print("Marked base module for upgrade")
    else:
        print("Database not yet initialized. Enterprise modules will be available after initialization.")
    
except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
finally:
    if conn:
        conn.close()
EOT

# Run the script to prepare the database
python3 /tmp/prepare_enterprise.py
rm /tmp/prepare_enterprise.py

# Restart the container
echo "Restarting the Odoo container..."
docker-compose -f "$TENANT_DIR/docker-compose.yml" down
docker-compose -f "$TENANT_DIR/docker-compose.yml" up -d

echo "Enterprise modules installation process completed."
echo "Please check the Odoo logs for any errors:"
echo "docker-compose -f $TENANT_DIR/docker-compose.yml logs -f"
echo ""
echo "After restart, go to Settings > Activate developer mode,"
echo "then visit Settings > Apps > Update Apps List to see enterprise apps."
echo ""
echo "Note: Some enterprise features may require a valid enterprise subscription."
echo "      You might need to install any desired enterprise modules manually."
EOF

    # Make the script executable
    chmod +x ${SCRIPTS_DIR}/install-enterprise.sh
    
    echo -e "${GREEN}Enterprise integration script installed at ${SCRIPTS_DIR}/install-enterprise.sh${NC}"
}

# Copy tenant management scripts
install_tenant_scripts() {
    echo -e "${GREEN}Installing tenant management scripts...${NC}"
    
    # Copy scripts from repository
    cp scripts/create-tenant.sh ${SCRIPTS_DIR}/
    cp scripts/backup-tenants.sh ${SCRIPTS_DIR}/
    cp scripts/initialize-modules.sh ${SCRIPTS_DIR}/
    cp scripts/update-tenant.sh ${SCRIPTS_DIR}/
    cp scripts/setup-custom-domain.sh ${SCRIPTS_DIR}/
    
    # Make scripts executable
    chmod +x ${SCRIPTS_DIR}/*.sh
    
    echo -e "${GREEN}Tenant management scripts installed.${NC}"
}

# Create self-signed certificates for development
create_self_signed_cert() {
    echo -e "${GREEN}Creating self-signed certificate for $DOMAIN...${NC}"
    
    # Create directory for certificates if it doesn't exist
    mkdir -p /etc/letsencrypt/live/$DOMAIN
    
    # Generate a self-signed certificate
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
      -keyout /etc/letsencrypt/live/$DOMAIN/privkey.pem \
      -out /etc/letsencrypt/live/$DOMAIN/fullchain.pem \
      -subj "/CN=$DOMAIN/O=Odoo/C=US" \
      -addext "subjectAltName = DNS:$DOMAIN,DNS:*.$DOMAIN,DNS:www.$DOMAIN"
    
    echo -e "${YELLOW}Self-signed certificate created. This is only for development/testing environments.${NC}"
    echo -e "${YELLOW}For production, you should replace these with Let's Encrypt certificates later.${NC}"
}

# Set up SSL certificates
setup_ssl() {
    echo -e "${GREEN}Setting up SSL certificates...${NC}"
    
    # Prompt for domain
    echo -e "${BLUE}Please enter your main domain name (e.g., arcweb.com.au):${NC}"
    read domain_input
    
    if [ -n "$domain_input" ]; then
        DOMAIN=$domain_input
    fi
    
    echo -e "${BLUE}Please select SSL setup option:${NC}"
    echo "1. Let's Encrypt certificates (requires domain control and public access)"
    echo "2. Self-signed certificates (for testing/development only)"
    echo "3. Skip SSL setup for now (you'll need to configure SSL later)"
    read -p "Enter your choice [1-3]: " ssl_choice
    
    case $ssl_choice in
        1)
            # Check if certbot is installed
            if ! command -v certbot >/dev/null 2>&1; then
                echo -e "${YELLOW}Certbot not found. Installing...${NC}"
                apt-get update
                apt-get install -y certbot python3-certbot-nginx
            fi
            
            # Ask if wildcard certificate is needed
            echo -e "${BLUE}Do you want to generate a wildcard certificate for *.$DOMAIN? [y/N]${NC}"
            read wildcard
            
            if [[ "$wildcard" == "y" || "$wildcard" == "Y" ]]; then
                USE_WILDCARD=true
                echo -e "${BLUE}Please enter your email for Let's Encrypt notifications:${NC}"
                read email
                
                if [ -z "$email" ]; then
                    echo -e "${RED}Email cannot be empty.${NC}"
                    return 1
                fi
                
                SSL_EMAIL=$email
                
                certbot certonly --manual --preferred-challenges dns \
                  -d $DOMAIN -d *.$DOMAIN \
                  --agree-tos -m $SSL_EMAIL
                  
                echo -e "${YELLOW}Please follow the instructions from certbot to complete DNS challenge.${NC}"
            else
                echo -e "${BLUE}Please enter your email for Let's Encrypt notifications:${NC}"
                read email
                
                if [ -z "$email" ]; then
                    echo -e "${RED}Email cannot be empty.${NC}"
                    return 1
                fi
                
                SSL_EMAIL=$email
                
                certbot certonly --standalone -d $DOMAIN -d www.$DOMAIN \
                  --agree-tos -m $SSL_EMAIL
            fi
            
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}SSL certificates obtained successfully.${NC}"
            else
                echo -e "${RED}Failed to obtain SSL certificates.${NC}"
                echo -e "${YELLOW}Creating self-signed certificates for now...${NC}"
                create_self_signed_cert
            fi
            ;;
        2)
            create_self_signed_cert
            ;;
        3)
            echo -e "${YELLOW}Skipping SSL setup. You'll need to configure SSL later.${NC}"
            echo -e "${YELLOW}Creating temporary self-signed certificate to avoid Nginx errors...${NC}"
            create_self_signed_cert
            ;;
        *)
            echo -e "${RED}Invalid choice. Creating self-signed certificates...${NC}"
            create_self_signed_cert
            ;;
    esac
}

# Configure Nginx
configure_nginx() {
    echo -e "${GREEN}Configuring Nginx...${NC}"
    
    # Check if Nginx is installed
    if ! command -v nginx >/dev/null 2>&1; then
        echo -e "${YELLOW}Nginx not found. Installing...${NC}"
        apt-get update
        apt-get install -y nginx
    fi
    
    # Copy Nginx configurations
    mkdir -p /etc/nginx/sites-available
    mkdir -p /etc/nginx/sites-enabled
    
    # Copy the main Nginx config
    cp nginx/nginx.conf /etc/nginx/
    
    # Prepare site configs - replace domain if needed
    cp nginx/sites-available/arcweb.com.au.conf /tmp/main-site.conf
    cp nginx/sites-available/tenant-template.conf /tmp/tenant-template.conf
    
    # Replace domain if it's not the default
    if [ "$DOMAIN" != "arcweb.com.au" ]; then
        sed -i "s/arcweb.com.au/$DOMAIN/g" /tmp/main-site.conf
        sed -i "s/arcweb.com.au/$DOMAIN/g" /tmp/tenant-template.conf
    fi
    
    # Copy the modified configs to their destinations
    cp /tmp/main-site.conf /etc/nginx/sites-available/$DOMAIN.conf
    cp /tmp/tenant-template.conf /etc/nginx/sites-available/tenant-template.conf
    
    # Create symbolic link for the main site
    ln -sf /etc/nginx/sites-available/$DOMAIN.conf /etc/nginx/sites-enabled/
    
    # Test Nginx configuration
    nginx -t
    
    # Reload Nginx if configuration is valid
    if [ $? -eq 0 ]; then
        systemctl reload nginx
        echo -e "${GREEN}Nginx configured and reloaded.${NC}"
    else
        echo -e "${RED}Nginx configuration test failed. Please check your configuration.${NC}"
        echo -e "${YELLOW}You may need to fix the SSL certificate paths in the Nginx configuration.${NC}"
    fi
}
# Start main Odoo instance
start_main_instance() {
    echo -e "${GREEN}Starting main Odoo instance...${NC}"
    
    cd ${ODOO_DIR}
    
    # Check if docker-compose is installed
    if ! command -v docker-compose >/dev/null 2>&1; then
        echo -e "${YELLOW}Docker-compose not found. Installing...${NC}"
        apt-get update
        apt-get install -y docker-compose
    fi
    
    # Update the domain in docker-compose.yml if needed
    if [ "$DOMAIN" != "arcweb.com.au" ]; then
        sed -i "s/VIRTUAL_HOST=arcweb.com.au/VIRTUAL_HOST=$DOMAIN/g" docker-compose.yml
    fi
    
    # Start container
    docker-compose up -d
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Main Odoo instance started successfully.${NC}"
    else
        echo -e "${RED}Failed to start main Odoo instance.${NC}"
    fi
}

# Main installation function
install_all() {
    echo -e "${GREEN}Starting complete installation...${NC}"
    
    update_dockerfiles     # Add this line to call the new function
    create_directories
    copy_config_files
    create_env_template
    install_enterprise_script
    install_tenant_scripts
    setup_ssl             # Setup SSL certificates BEFORE Nginx
    configure_nginx       # Now configure Nginx
    start_main_instance
    
    echo -e "${GREEN}Installation completed!${NC}"
    echo -e "${BLUE}Here's what you should do next:${NC}"
    echo -e "1. Copy ${ODOO_DIR}/.env.template to ${ODOO_DIR}/.env and update with your secure values"
    echo -e "2. Create your first tenant with: ${SCRIPTS_DIR}/create-tenant.sh tenant_name database_name"
    echo -e "3. To install enterprise modules for a tenant: ${SCRIPTS_DIR}/install-enterprise.sh tenant_name"
    echo -e "4. Access your main Odoo instance at: https://$DOMAIN"
    
    if [[ "$ssl_choice" == "2" || "$ssl_choice" == "3" ]]; then
        echo -e "${YELLOW}NOTE: You're using self-signed certificates. For production use, you should:${NC}"
        echo -e "${YELLOW}  - Set up proper Let's Encrypt certificates${NC}"
        echo -e "${YELLOW}  - Update the certificate paths in Nginx configuration${NC}"
    fi
}

# Display menu
show_menu() {
    echo -e "${BLUE}Please select an action:${NC}"
    echo "1. Complete installation"
    echo "2. Create directory structure only"
    echo "3. Configure Nginx only"
    echo "4. Setup SSL certificates only"
    echo "5. Start main Odoo instance only"
    echo "6. Install enterprise integration script"
    echo "7. Exit"
    
    read -p "Enter your choice [1-7]: " choice
    
    case $choice in
        1) install_all ;;
        2) create_directories ;;
        3) 
           # Ask if SSL is already set up
           echo -e "${BLUE}Is SSL already set up? [y/N]${NC}"
           read ssl_ready
           if [[ "$ssl_ready" != "y" && "$ssl_ready" != "Y" ]]; then
               setup_ssl
           fi
           configure_nginx 
           ;;
        4) setup_ssl ;;
        5) start_main_instance ;;
        6) install_enterprise_script ;;
        7) exit 0 ;;
        *) echo -e "${RED}Invalid choice. Please try again.${NC}" ;;
    esac
}

# Main execution
show_menu
