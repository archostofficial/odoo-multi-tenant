# Odoo Multi-Tenant Docker Setup

This repository contains all the necessary configurations and scripts to set up and manage a multi-tenant Odoo environment using Docker and Nginx. It supports hosting multiple Odoo instances on the same server, each with its own domain/subdomain and database.

## Features

- **Multi-tenant architecture**: Run multiple isolated Odoo instances on a single server
- **Domain separation**: Each tenant gets its own domain or subdomain
- **Database isolation**: Separate PostgreSQL database for each tenant
- **Shared add-ons**: Support for shared and tenant-specific add-ons
- **SSL support**: HTTPS configuration with Let's Encrypt
- **Easy tenant management**: Scripts for creating, updating, and backing up tenants
- **Optimized configuration**: Proper settings for real-time features and performance

## Prerequisites

- Ubuntu server (20.04+)
- Docker and Docker Compose installed
- Nginx installed
- Access to a PostgreSQL server
- Domain name with DNS control

## Quick Start

1. Clone this repository:
   ```bash
   git clone https://github.com/archostofficial/odoo-multi-tenant.git
   cd odoo-multi-tenant
   ```

2. Set up the main Odoo instance:
   ```bash
   cp -r docker/main /opt/odoo
   cd /opt/odoo
   docker-compose up -d
   ```

3. Create a new tenant:
   ```bash
   ./scripts/create-tenant.sh app odoo_app
   ```

4. Access your Odoo instances:
   - Main instance: https://yourdomain.com
   - Tenant instance: https://app.yourdomain.com

## Directory Structure

- `docker/`: Docker configuration files
  - `main/`: Configuration for the main Odoo instance
  - `tenant-template/`: Template for new tenant configurations
- `scripts/`: Utility scripts for managing tenants
- `nginx/`: Nginx configuration files
- `docs/`: Documentation

## Tenant Management

### Creating a New Tenant

```bash
./scripts/create-tenant.sh tenant_name database_name
```

### Backing Up All Tenants

```bash
./scripts/backup-tenants.sh
```

### Initializing Modules for a Tenant

```bash
./scripts/initialize-modules.sh tenant_name
```

## Add-ons Management

The setup supports both shared add-ons (available to all tenants) and tenant-specific add-ons:

- Shared add-ons: `/opt/odoo-addons/shared/`
- Tenant-specific add-ons: `/opt/odoo-addons/tenant-specific/tenant_name/`

## Documentation

For more detailed information, check:

- [Setup Guide](docs/setup-guide.md)
- [Troubleshooting](docs/troubleshooting.md)

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Odoo Community
- Docker
- Nginx
