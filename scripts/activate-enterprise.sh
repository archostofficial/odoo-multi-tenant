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
cat > /tmp/prepare_enterprise.py << EOF
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
EOF

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
