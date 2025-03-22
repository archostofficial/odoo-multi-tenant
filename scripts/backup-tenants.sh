#!/bin/bash

# Script to back up all Odoo tenant databases and configurations
# Usage: ./backup-tenants.sh [backup_dir]

# Default backup directory
BACKUP_DIR=${1:-"/opt/backups/$(date +%Y-%m-%d)"}
mkdir -p $BACKUP_DIR

echo "Creating backups in $BACKUP_DIR"

# Backup each database
for dir in /opt/odoo /opt/odoo-*; do
  if [ -d "$dir" ] && [ -f "$dir/docker-compose.yml" ]; then
    # Get tenant name from directory
    TENANT=$(basename $dir | sed 's/odoo-//')
    if [ "$TENANT" = "odoo" ]; then
      TENANT="main"
    fi
    
    echo "Backing up tenant: $TENANT"
    
    # Create tenant directory
    mkdir -p "$BACKUP_DIR/$TENANT"
    
    # Extract the database name
    DB_NAME=$(grep "DB_NAME=" "$dir/docker-compose.yml" | cut -d'=' -f2 | tr -d '"' | tr -d "'" | head -1)
    
    if [ -z "$DB_NAME" ]; then
      echo "  Warning: Could not determine database name for $TENANT, skipping database backup"
    else
      echo "  Backing up database: $DB_NAME"
      PGPASSWORD=cnV2abjbDpbh64e12987wR4mj5kQ3456Y0Qf pg_dump -h 192.168.60.110 -U odoo -F c -b -v -f "$BACKUP_DIR/$TENANT/$DB_NAME.backup" "$DB_NAME"
    fi
    
    # Backup configuration files
    echo "  Backing up configuration files"
    cp -r "$dir/18.0" "$BACKUP_DIR/$TENANT/"
    cp "$dir/docker-compose.yml" "$BACKUP_DIR/$TENANT/"
    
    # Backup addons
    if [ -d "/opt/odoo-addons/tenant-specific/$TENANT" ]; then
      echo "  Backing up tenant-specific addons"
      mkdir -p "$BACKUP_DIR/$TENANT/addons"
      cp -r "/opt/odoo-addons/tenant-specific/$TENANT" "$BACKUP_DIR/$TENANT/addons/"
    fi
  fi
done

# Backup Nginx configurations
echo "Backing up Nginx configurations"
mkdir -p "$BACKUP_DIR/nginx"
cp /etc/nginx/sites-available/*.arcweb.com.au.conf "$BACKUP_DIR/nginx/"

# Backup shared addons
echo "Backing up shared addons"
mkdir -p "$BACKUP_DIR/shared-addons"
if [ -d "/opt/odoo-addons/shared" ]; then
  cp -r /opt/odoo-addons/shared/* "$BACKUP_DIR/shared-addons/"
fi

# Backup SSL certificates
echo "Backing up SSL certificates"
mkdir -p "$BACKUP_DIR/ssl"
cp -r /etc/letsencrypt/live/arcweb.com.au "$BACKUP_DIR/ssl/"
cp -r /etc/letsencrypt/archive/arcweb.com.au "$BACKUP_DIR/ssl/"

# Create a compressed archive of the backup
echo "Creating compressed archive"
tar -czf "$BACKUP_DIR.tar.gz" "$BACKUP_DIR"

echo "Backup completed at $BACKUP_DIR"
echo "Compressed archive available at $BACKUP_DIR.tar.gz"
