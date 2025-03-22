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
    
    cp nginx/nginx.conf /etc/nginx/
    cp nginx/sites-available/arcweb.com.au.conf /etc/nginx/sites-available/
    cp nginx/sites-available/tenant-template.conf /etc/nginx/sites-available/
    
    # Create symbolic link
    ln -sf /etc/nginx/sites-available/arcweb.com.au.conf /etc/nginx/sites-enabled/
    
    # Test Nginx configuration
    nginx -t
    
    # Reload Nginx if configuration is valid
    if [ $? -eq 0 ]; then
        systemctl reload nginx
        echo -e "${GREEN}Nginx configured and reloaded.${NC}"
    else
        echo -e "${RED}Nginx configuration test failed. Please check your configuration.${NC}"
    fi
}

# Set up SSL certificates
setup_ssl() {
    echo -e "${GREEN}Setting up SSL certificates...${NC}"
    
    # Check if certbot is installed
    if ! command -v certbot >/dev/null 2>&1; then
        echo -e "${YELLOW}Certbot not found. Installing...${NC}"
        apt-get update
        apt-get install -y certbot python3-certbot-nginx
    fi
    
    # Prompt for domain
    echo -e "${BLUE}Please enter your main domain name (e.g., arcweb.com.au):${NC}"
    read domain
    
    if [ -z "$domain" ]; then
        echo -e "${RED}Domain name cannot be empty. Using default 'arcweb.com.au'${NC}"
        domain="arcweb.com.au"
    fi
    
    # Ask if wildcard certificate is needed
    echo -e "${BLUE}Do you want to generate a wildcard certificate for *.$domain? [y/N]${NC}"
    read wildcard
    
    if [[ "$wildcard" == "y" || "$wildcard" == "Y" ]]; then
        echo -e "${BLUE}Please enter your email for Let's Encrypt notifications:${NC}"
        read email
        
        if [ -z "$email" ]; then
            echo -e "${RED}Email cannot be empty.${NC}"
            return 1
        fi
        
        certbot certonly --manual --preferred-challenges dns \
          -d $domain -d *.$domain \
          --agree-tos -m $email
          
        echo -e "${YELLOW}Please follow the instructions from certbot to complete DNS challenge.${NC}"
    else
        certbot --nginx -d $domain -d www.$domain
    fi
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}SSL certificates obtained successfully.${NC}"
    else
        echo -e "${RED}Failed to obtain SSL certificates.${NC}"
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
    
    create_directories
    copy_config_files
    create_env_template
    install_enterprise_script
    install_tenant_scripts
    configure_nginx
    setup_ssl
    start_main_instance
    
    echo -e "${GREEN}Installation completed!${NC}"
    echo -e "${BLUE}Here's what you should do next:${NC}"
    echo -e "1. Copy ${ODOO_DIR}/.env.template to ${ODOO_DIR}/.env and update with your secure values"
    echo -e "2. Create your first tenant with: ${SCRIPTS_DIR}/create-tenant.sh tenant_name database_name"
    echo -e "3. To install enterprise modules for a tenant: ${SCRIPTS_DIR}/install-enterprise.sh tenant_name"
    echo -e "4. Access your main Odoo instance at: https://your-domain.com"
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
        3) configure_nginx ;;
        4) setup_ssl ;;
        5) start_main_instance ;;
        6) install_enterprise_script ;;
        7) exit 0 ;;
        *) echo -e "${RED}Invalid choice. Please try again.${NC}" ;;
    esac
}

# Main execution
show_menu
