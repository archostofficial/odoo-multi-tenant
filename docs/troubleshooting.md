# Troubleshooting Guide for Odoo Multi-Tenant Setup

This document provides solutions for common issues you might encounter with your multi-tenant Odoo setup.

## Database Connection Issues

### Symptom: "Database connection failure" Error

```
Database connection failure: connection to server at "192.168.60.110", port 5432 failed: could not read root certificate file "/dev/null": no certificate or crl found
```

**Solution**:
1. Update the SSL mode settings:
   ```bash
   /opt/update-tenant.sh tenant_name
   ```
   This script changes `db_sslmode` from `require` to `prefer`, which allows SSL to fall back to non-SSL.

### Symptom: "FATAL: no pg_hba.conf entry" Error

```
FATAL: no pg_hba.conf entry for host "192.168.60.100", user "odoo", database "postgres", no encryption
```

**Solution**:
1. Add an entry to the PostgreSQL server's pg_hba.conf file:
   ```
   host    all     odoo    192.168.60.100/32    md5
   ```
2. Restart PostgreSQL:
   ```bash
   systemctl restart postgresql
   ```

## WebSocket/Real-time Features Not Working

### Symptom: Live Chat, Notifications Not Working

**Solution**:
1. Check if the longpolling service is running:
   ```bash
   docker-compose logs | grep "longpolling"
   ```
   You should see: `INFO ? odoo.service.server: Evented Service (longpolling) running on 0.0.0.0:8072`

2. If not found, ensure the `workers` parameter is set:
   ```bash
   /opt/update-tenant.sh tenant_name workers 2
   ```

3. Verify your Nginx configuration has proper WebSocket handling:
   ```bash
   grep -r "websocket" /etc/nginx/sites-available/
   ```
   It should include:
   ```nginx
   location /websocket {
      proxy_pass http://odoochat_tenant;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection $connection_upgrade;
      # ...
   }
   ```

## Missing Modules

### Symptom: KeyError: 'activity'

```
KeyError: 'activity'
```

**Solution**:
This error occurs when the 'mail' module is not installed. Run:
```bash
/opt/initialize-modules.sh tenant_name base,web,mail
```

### Symptom: Module Not Found

```
Module not found: [module_name]
```

**Solution**:
1. Check if the module exists in the add-ons paths:
   ```bash
   find /opt/odoo-addons -name module_name
   ```

2. If not found, install it:
   ```bash
   cd /opt/odoo-addons/shared
   git clone https://github.com/OCA/module_repository
   ```

3. Update the module list:
   ```bash
   /opt/initialize-modules.sh tenant_name base
   ```

## Performance Issues

### Symptom: Odoo Slow or Unresponsive

**Solution**:
1. Check server resource usage:
   ```bash
   top
   ```

2. Adjust worker count based on CPU cores (general rule: 2 × number of cores):
   ```bash
   /opt/update-tenant.sh tenant_name workers 4
   ```

3. Optimize PostgreSQL settings in postgresql.conf:
   ```
   shared_buffers = 1GB
   work_mem = 16MB
   maintenance_work_mem = 256MB
   effective_cache_size = 2GB
   ```

## SSL Certificate Issues

### Symptom: SSL Certificate Not Found

```
nginx: [emerg] cannot load certificate "/etc/letsencrypt/live/arcweb.com.au/fullchain.pem"
```

**Solution**:
1. Check if the certificate exists:
   ```bash
   ls -la /etc/letsencrypt/live/arcweb.com.au/
   ```

2. If not, obtain a new certificate:
   ```bash
   certbot --nginx -d arcweb.com.au -d www.arcweb.com.au
   ```

3. For wildcard certificates:
   ```bash
   certbot certonly --manual --preferred-challenges dns \
     -d arcweb.com.au -d *.arcweb.com.au \
     --agree-tos -m your-email@example.com
   ```

## Docker-Related Issues

### Symptom: "ContainerConfig" Error

```
ERROR: for tenant_container  'ContainerConfig'
```

**Solution**:
1. Remove the container and volume:
   ```bash
   docker-compose down -v
   ```

2. Clean up any old volumes:
   ```bash
   docker volume prune
   ```

3. Recreate the tenant:
   ```bash
   /opt/create-tenant.sh tenant_name db_name
   ```

### Symptom: Port Already in Use

```
Error starting userland proxy: listen tcp 0.0.0.0:8069: bind: address already in use
```

**Solution**:
1. Find what's using the port:
   ```bash
   netstat -tulpn | grep 8069
   ```

2. Stop the conflicting service or use different ports:
   ```bash
   /opt/create-tenant.sh tenant_name db_name
   ```
   The script automatically selects random ports to avoid conflicts.

## Backup and Restore

### Symptom: Backup Fails

**Solution**:
1. Ensure the PostgreSQL server is accessible:
   ```bash
   PGPASSWORD=password psql -h 192.168.60.110 -U odoo -d odoo -c "SELECT 1;"
   ```

2. Check disk space:
   ```bash
   df -h
   ```

3. Run the backup manually:
   ```bash
   PGPASSWORD=password pg_dump -h 192.168.60.110 -U odoo -F c -b -v -f backup.dump db_name
   ```

### Restoring from Backup

To restore a tenant from backup:

```bash
# Create a new tenant first
/opt/create-tenant.sh tenant_name db_name

# Then restore the database
PGPASSWORD=password pg_restore -h 192.168.60.110 -U odoo -d db_name -v backup.dump
```

## Nginx Configuration

### Symptom: 502 Bad Gateway

**Solution**:
1. Check if the Odoo container is running:
   ```bash
   docker ps | grep odoo
   ```

2. Verify the port mapping:
   ```bash
   docker-compose ps
   ```

3. Check Nginx error logs:
   ```bash
   tail -f /var/log/nginx/error.log
   ```

4. Ensure the upstream server configuration is correct:
   ```bash
   grep -A 5 "upstream odoo_tenant" /etc/nginx/sites-available/tenant.arcweb.com.au.conf
   ```

## Add-on Visibility Issues

### Symptom: Added Module Not Visible

**Solution**:
1. Verify the add-on path is correctly set:
   ```bash
   grep "addons_path" /opt/odoo-tenant_name/18.0/odoo.conf
   ```

2. Check permissions:
   ```bash
   ls -la /opt/odoo-addons/shared/
   ls -la /opt/odoo-addons/tenant-specific/tenant_name/
   ```

3. Update the module list:
   ```bash
   /opt/initialize-modules.sh tenant_name base
   ```

4. Restart the container:
   ```bash
   cd /opt/odoo-tenant_name
   docker-compose restart
   ```

If you encounter issues not covered in this guide, please check the [Odoo documentation](https://www.odoo.com/documentation/18.0/) or open an issue on this repository.
