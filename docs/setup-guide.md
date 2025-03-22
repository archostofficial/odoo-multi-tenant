# Odoo Multi-Tenant Setup Guide

This guide provides detailed instructions for setting up a multi-tenant Odoo environment with Docker and Nginx.

## Prerequisites

- Ubuntu server (20.04+)
- Docker and Docker Compose installed
- Nginx installed
- Access to a PostgreSQL server
- Domain name with DNS control

## System Architecture

The architecture consists of:

1. A main Odoo instance running on the primary domain
2. Multiple tenant instances running on subdomains
3. Nginx as a reverse proxy to route traffic to the appropriate Odoo instance
4. PostgreSQL server for database storage
5. Shared and tenant-specific addon directories

## Initial Setup

### 1. Directory Structure

Create the necessary directories:

```bash
# Main directories
mkdir -p /opt/odoo
mkdir -p /opt/odoo/18.0
mkdir -p /opt/odoo/addons

# Addons directories
mkdir -p /opt/odoo-addons/shared
mkdir -p /opt/odoo-addons/tenant-specific/main
```

### 2. Configure the Main Instance

Copy the configuration files from this repository:

```bash
# Copy files
cp docker/main/Dockerfile /opt/odoo/
cp docker/main/docker-compose.yml /opt/odoo/
cp docker/main/odoo.conf /opt/odoo/18.0/
cp docker/main/entrypoint.sh /opt/odoo/
cp docker/main/wait-for-psql.py /opt/odoo/
```

Make the scripts executable:

```bash
chmod +x /opt/odoo/entrypoint.sh
chmod +x /opt/odoo/wait-for-psql.py
```

### 3. Start the Main Instance

```bash
cd /opt/odoo
docker-compose up -d
```

### 4. Initialize the Database

```bash
docker-compose run --rm odoo odoo --init base,web,mail --database odoo --db_host 192.168.60.110 --db_port 5432 --db_user odoo --db_password cnV2abjbDpbh64e12987wR4mj5kQ3456Y0Qf --without-demo=all
```

### 5. Configure Nginx

Create a configuration file for the main domain:

```bash
cp nginx/sites-available/arcweb.com.au.conf /etc/nginx/sites-available/
ln -sf /etc/nginx/sites-available/arcweb.com.au.conf /etc/nginx/sites-enabled/
```

### 6. Set Up SSL

```bash
apt-get update
apt-get install -y certbot python3-certbot-nginx
certbot --nginx -d arcweb.com.au -d www.arcweb.com.au
```

For wildcard certificates:

```bash
certbot certonly --manual --preferred-challenges dns \
  -d arcweb.com.au -d *.arcweb.com.au \
  --agree-tos -m your-email@example.com
```

## Creating New Tenants

### 1. Copy the Create Tenant Script

```bash
cp scripts/create-tenant.sh /opt/
chmod +x /opt/create-tenant.sh
```

### 2. Create a New Tenant

```bash
/opt/create-tenant.sh app odoo_app
```

This will:
- Create a new directory for the tenant
- Set up the Docker configuration
- Create a new database
- Configure Nginx for the subdomain
- Initialize the database with essential modules

### 3. Access the New Tenant

Once the script completes, you can access the new tenant at:
```
https://app.arcweb.com.au
```

## Managing Add-ons

### 1. Shared Add-ons

Shared add-ons are available to all tenants:

```bash
cd /opt/odoo-addons/shared
git clone https://github.com/OCA/web
```

### 2. Tenant-specific Add-ons

Each tenant can have its own add-ons:

```bash
cd /opt/odoo-addons/tenant-specific/app
git clone https://github.com/custom/my-addon
```

## Maintaining the System

### 1. Backing Up All Tenants

```bash
cp scripts/backup-tenants.sh /opt/
chmod +x /opt/backup-tenants.sh
/opt/backup-tenants.sh
```

### 2. Initializing Modules

```bash
cp scripts/initialize-modules.sh /opt/
chmod +x /opt/initialize-modules.sh
/opt/initialize-modules.sh app crm,sale,purchase
```

### 3. Updating Tenant Configurations

```bash
cp scripts/update-tenant.sh /opt/
chmod +x /opt/update-tenant.sh
/opt/update-tenant.sh app workers 4
```

## Security Considerations

### 1. Restrict Database Manager Access

Edit your Nginx configurations to restrict access to the database manager:

```nginx
location ~* /web/database/manager {
    allow 192.168.1.0/24;
    deny all;
    proxy_pass http://odoo_tenant;
}
```

### 2. Set Strong Admin Passwords

Generate and set strong passwords for the Odoo master password:

```bash
MASTER_PASSWORD=$(openssl rand -base64 32)
echo "admin_passwd = $MASTER_PASSWORD" >> /opt/odoo/18.0/odoo.conf
```

### 3. Regular Backups

Set up a cron job to run backups regularly:

```bash
echo "0 2 * * * root /opt/backup-tenants.sh" > /etc/cron.d/odoo-backup
```

## Troubleshooting

### 1. SSL Connection Issues

If you encounter SSL connection issues with the PostgreSQL database, try:

```bash
/opt/update-tenant.sh tenant_name
```

### 2. WebSocket/Chat Not Working

Check your Nginx configuration to ensure proper WebSocket routing:

```bash
grep -r "websocket" /etc/nginx/sites-available/
```

### 3. Performance Issues

Adjust the worker count based on your server's resources:

```bash
/opt/update-tenant.sh tenant_name workers 4
```

## Next Steps

- Set up monitoring with Prometheus/Grafana
- Configure automated backups to cloud storage
- Implement log rotation
- Set up a CI/CD pipeline for addon deployments
