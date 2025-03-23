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
echo "Database name: $DB_NAME"
echo "Enterprise Addons Path: $ADDON_PATH"

# Determine Odoo version - more robust detection
detect_odoo_version() {
    # Try multiple methods to detect Odoo version
    local version
    
    # Method 1: Check env variable in Dockerfile
    if [ -f "$TENANT_DIR/Dockerfile" ]; then
        version=$(grep -o "ENV ODOO_VERSION [0-9.]*" "$TENANT_DIR/Dockerfile" | awk '{print $3}' | tr -d '"' | tr -d '\r')
        if [ -n "$version" ]; then
            echo "$version"
            return 0
        fi
    fi
    
    # Method 2: Check image tag in docker-compose.yml
    if [ -f "$TENANT_DIR/docker-compose.yml" ]; then
        version=$(grep -o "image:.*odoo:[0-9.]*" "$TENANT_DIR/docker-compose.yml" | grep -o "[0-9.]*" | head -1)
        if [ -n "$version" ]; then
            echo "$version"
            return 0
        fi
    fi
    
    # Method 3: Check for version in entrypoint script
    if [ -f "$TENANT_DIR/entrypoint.sh" ]; then
        version=$(grep -o "ODOO_VERSION=[0-9.]*" "$TENANT_DIR/entrypoint.sh" | cut -d'=' -f2 | head -1)
        if [ -n "$version" ]; then
            echo "$version"
            return 0
        fi
    fi
    
    # Fallback to default version
    echo "18.0"
    return 0
}

# Check if enterprise repository exists
if [ ! -d "$ADDON_PATH/.git" ]; then
    echo "Cloning Odoo Enterprise repository..."
    
    # Prompt for GitHub credentials
    echo "Please enter your GitHub credentials for the Odoo Enterprise repository:"
    read -p "GitHub Username: " GITHUB_USER
    read -s -p "GitHub Token/Password: " GITHUB_TOKEN
    echo ""
    
    # Clone the enterprise repository - URL encode the token to handle special characters
    TOKEN_URLENCODED=$(echo -n "$GITHUB_TOKEN" | xxd -plain | tr -d '\n' | sed 's/\(..\)/%\1/g' 2>/dev/null || echo "$GITHUB_TOKEN")
    git clone "https://$GITHUB_USER:$TOKEN_URLENCODED@github.com/odoo/enterprise.git" "$ADDON_PATH"
    
    # Check out the correct branch
    cd "$ADDON_PATH"
    ODOO_VERSION=$(detect_odoo_version)
    echo "Detected Odoo version: $ODOO_VERSION"
    
    # Make sure the branch exists before checking it out
    if git ls-remote --heads origin | grep -q "refs/heads/$ODOO_VERSION"; then
        git checkout "$ODOO_VERSION"
    else
        echo "Warning: Branch $ODOO_VERSION not found, staying on default branch"
    fi
elif [ -d "$ADDON_PATH/.git" ]; then
    echo "Updating existing Odoo Enterprise repository..."
    cd "$ADDON_PATH"
    ODOO_VERSION=$(detect_odoo_version)
    echo "Detected Odoo version: $ODOO_VERSION"
    
    git fetch
    # Make sure the branch exists before checking it out
    if git ls-remote --heads origin | grep -q "refs/heads/$ODOO_VERSION"; then
        git checkout "$ODOO_VERSION"
        git pull
    else
        echo "Warning: Branch $ODOO_VERSION not found, staying on current branch"
        git pull
    fi
fi

# Create or update odoo.conf if it doesn't exist
if [ ! -f "$TENANT_DIR/odoo.conf" ]; then
    if [ -d "$TENANT_DIR/18.0" ] && [ -f "$TENANT_DIR/18.0/odoo.conf" ]; then
        CONF_FILE="$TENANT_DIR/18.0/odoo.conf"
    else
        echo "Creating default odoo.conf..."
        mkdir -p "$TENANT_DIR/18.0"
        CONF_FILE="$TENANT_DIR/18.0/odoo.conf"
        cat > "$CONF_FILE" << EOF
[options]
addons_path = /mnt/shared-addons,/mnt/extra-addons
data_dir = /var/lib/odoo
EOF
    fi
else
    CONF_FILE="$TENANT_DIR/odoo.conf"
fi

# Update addons path in odoo.conf
if [ -f "$CONF_FILE" ]; then
    # Check if enterprise path is already in addons_path
    if grep -q "addons_path" "$CONF_FILE"; then
        if ! grep -q "$ADDON_PATH" "$CONF_FILE" && ! grep -q "/mnt/enterprise-addons" "$CONF_FILE"; then
            echo "Updating addons_path in odoo.conf..."
            CURRENT_PATH=$(grep "addons_path" "$CONF_FILE" | cut -d'=' -f2 | tr -d ' ')
            NEW_PATH="$CURRENT_PATH,/mnt/enterprise-addons"
            sed -i "s|addons_path = .*|addons_path = $NEW_PATH|" "$CONF_FILE"
        else
            echo "Enterprise addons path already in odoo.conf"
        fi
    else
        echo "Adding addons_path to odoo.conf..."
        echo "addons_path = /mnt/shared-addons,/mnt/extra-addons,/mnt/enterprise-addons" >> "$CONF_FILE"
    fi
else
    echo "Error: Configuration file $CONF_FILE not found."
    exit 1
fi

# Update container volume to mount enterprise addons
echo "Updating Docker container configuration..."
if ! grep -q "/mnt/enterprise-addons" "$TENANT_DIR/docker-compose.yml"; then
    # Find the volumes section
    VOLUME_LINE=$(grep -n "volumes:" "$TENANT_DIR/docker-compose.yml" | cut -d':' -f1 | head -1)
    if [ -n "$VOLUME_LINE" ]; then
        # Add enterprise volume after volumes line
        sed -i "$((VOLUME_LINE+3)) i\      - $ADDON_PATH:/mnt/enterprise-addons" "$TENANT_DIR/docker-compose.yml"
    else
        echo "Error: Could not find volumes section in docker-compose.yml"
        echo "Manually add this line to the volumes section:"
        echo "      - $ADDON_PATH:/mnt/enterprise-addons"
    fi
else
    echo "Enterprise volume already configured in docker-compose.yml"
fi

# Create a temporary Python script to prepare the database
echo "Setting up database to use enterprise modules..."
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
        
        # Create a dummy enterprise_code record if it doesn't exist
        cur.execute("SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name='ir_config_parameter')")
        if cur.fetchone()[0]:
            print("Checking for enterprise code setting...")
            cur.execute("SELECT COUNT(*) FROM ir_config_parameter WHERE key='database.enterprise_code'")
            if cur.fetchone()[0] == 0:
                print("Adding dummy enterprise code parameter")
                cur.execute("INSERT INTO ir_config_parameter (key, value) VALUES ('database.enterprise_code', 'demo_enterprise_code')")
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
cd "$TENANT_DIR"
docker-compose down || echo "Warning: docker-compose down failed, continuing anyway..."
docker-compose up -d || {
    echo "Error: Failed to start container. Check the docker-compose.yml file for errors."
    echo "You may need to manually run: docker-compose up -d in $TENANT_DIR"
    exit 1
}

echo "Enterprise modules installation process completed."
echo ""
echo "To check logs for any errors:"
echo "  docker-compose -f $TENANT_DIR/docker-compose.yml logs -f"
echo ""
echo "After restart, go to Settings > Activate developer mode,"
echo "then visit Settings > Apps > Update Apps List to see enterprise apps."
echo ""
echo "Note: Some enterprise features may require a valid enterprise subscription."
echo "      You might need to install any desired enterprise modules manually."
echo ""
echo "Next steps:"
echo "1. Log in to your Odoo instance at https://$TENANT.arcweb.com.au or your custom domain"
echo "2. Go to Settings > Activate developer mode"
echo "3. Go to Apps > Update Apps List"
echo "4. Search for 'Enterprise' to see and install enterprise modules"
