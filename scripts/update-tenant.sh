#!/bin/bash

# Script to update configuration of an existing Odoo tenant
# Usage: ./update-tenant.sh tenant_name [parameter] [value]

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 tenant_name [parameter] [value]"
    echo "Example: $0 app workers 4"
    echo "If parameter and value are not provided, it will update SSL settings"
    exit 1
fi

TENANT=$1
PARAM=$2
VALUE=$3
TENANT_DIR="/opt/odoo-$TENANT"

if [ ! -d "$TENANT_DIR" ]; then
    echo "Error: Tenant directory $TENANT_DIR does not exist."
    exit 1
fi

echo "Updating tenant: $TENANT"

if [ -z "$PARAM" ] || [ -z "$VALUE" ]; then
    # Default update: fix SSL settings
    echo "Updating SSL settings..."
    
    # Update docker-compose.yml
    if grep -q "PGSSLMODE" "$TENANT_DIR/docker-compose.yml"; then
        sed -i 's/PGSSLMODE=.*/PGSSLMODE=prefer/' "$TENANT_DIR/docker-compose.yml"
    else
        sed -i '/PASSWORD=/ a\      - PGSSLMODE=prefer' "$TENANT_DIR/docker-compose.yml"
    fi
    
    # Update odoo.conf
    if [ -f "$TENANT_DIR/18.0/odoo.conf" ]; then
        if grep -q "db_sslmode" "$TENANT_DIR/18.0/odoo.conf"; then
            sed -i 's/db_sslmode = .*/db_sslmode = prefer/' "$TENANT_DIR/18.0/odoo.conf"
        else
            echo "db_sslmode = prefer" >> "$TENANT_DIR/18.0/odoo.conf"
        fi
    fi
else
    # Custom parameter update
    echo "Updating parameter $PARAM to $VALUE..."
    
    # Update docker-compose.yml for common parameters
    case $PARAM in
        workers|max_cron_threads)
            # Update command line arguments
            if grep -q "$PARAM" "$TENANT_DIR/docker-compose.yml"; then
                sed -i "s/--$PARAM=[0-9]*/--$PARAM=$VALUE/" "$TENANT_DIR/docker-compose.yml"
            else
                sed -i "s/command: \[\"odoo\"/command: [\"odoo\", \"--$PARAM=$VALUE\"/" "$TENANT_DIR/docker-compose.yml"
            fi
            ;;
        db_maxconn)
            # Update DB_MAXCONN environment variable
            if grep -q "DB_MAXCONN" "$TENANT_DIR/docker-compose.yml"; then
                sed -i "s/DB_MAXCONN=.*/DB_MAXCONN=$VALUE/" "$TENANT_DIR/docker-compose.yml"
            else
                sed -i "/PASSWORD=/ a\      - DB_MAXCONN=$VALUE" "$TENANT_DIR/docker-compose.yml"
            fi
            ;;
    esac
    
    # Update odoo.conf
    if [ -f "$TENANT_DIR/18.0/odoo.conf" ]; then
        if grep -q "$PARAM" "$TENANT_DIR/18.0/odoo.conf"; then
            sed -i "s/$PARAM = .*/$PARAM = $VALUE/" "$TENANT_DIR/18.0/odoo.conf"
        else
            echo "$PARAM = $VALUE" >> "$TENANT_DIR/18.0/odoo.conf"
        fi
    fi
fi

# Restart the container
echo "Restarting the container..."
cd "$TENANT_DIR"
docker-compose down
docker-compose up -d

echo "Update completed for tenant $TENANT"
