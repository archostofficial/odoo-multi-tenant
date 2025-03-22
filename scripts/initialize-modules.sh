#!/bin/bash

# Script to initialize or update modules for an Odoo tenant
# Usage: ./initialize-modules.sh tenant_name [module_list]

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 tenant_name [module_list]"
    echo "Example: $0 app base,web,mail,contacts,crm"
    echo "If module_list is not provided, it defaults to base,web,mail"
    exit 1
fi

TENANT=$1
MODULE_LIST=${2:-"base,web,mail"}
TENANT_DIR="/opt/odoo-$TENANT"

if [ ! -d "$TENANT_DIR" ]; then
    echo "Error: Tenant directory $TENANT_DIR does not exist."
    exit 1
fi

# Get database name from docker-compose.yml
DB_NAME=$(grep "DB_NAME=" "$TENANT_DIR/docker-compose.yml" | cut -d'=' -f2 | tr -d '"' | tr -d "'" | head -1)

if [ -z "$DB_NAME" ]; then
    echo "Error: Could not determine database name for tenant $TENANT"
    exit 1
fi

echo "Initializing modules for tenant: $TENANT"
echo "Database: $DB_NAME"
echo "Modules: $MODULE_LIST"

# Run the initialization command
cd "$TENANT_DIR"
docker-compose run --rm odoo-$TENANT odoo \
  --init=$MODULE_LIST \
  --database $DB_NAME \
  --db_host 192.168.60.110 \
  --db_port 5432 \
  --db_user odoo \
  --db_password cnV2abjbDpbh64e12987wR4mj5kQ3456Y0Qf \
  --without-demo=all

echo "Module initialization completed."
echo "Restarting the container..."
docker-compose restart

echo "Done! You can access the tenant at https://$TENANT.arcweb.com.au"
