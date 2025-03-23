# Odoo Multi-Tenant Docker Setup

This repository contains all the necessary configurations and scripts to set up and manage a multi-tenant Odoo environment using Docker and Nginx. It supports hosting multiple Odoo instances on the same server, each with its own domain/subdomain and database.

## Features

- **Multi-tenant architecture**: Run multiple isolated Odoo instances on a single server
- **Domain separation**: Each tenant gets its own domain or subdomain
- **Database isolation**: Separate PostgreSQL database for each tenant
- **Shared add-ons**: Support for shared and tenant-specific add-ons
- **Enterprise support**: Easy integration of Odoo Enterprise modules
- **SSL support**: HTTPS configuration with Let's Encrypt
- **Easy tenant management**: Scripts for creating, updating, and backing up tenants
- **Optimized configuration**: Proper settings for real-time features and performance

## Prerequisites

- Ubuntu server (20.04+ or Noble 24.04)
- Docker and Docker Compose installed
- Nginx installed
- Access to a PostgreSQL server
- Domain name with DNS control

## Quick Start

### Automated Setup

We provide a comprehensive setup script that handles the entire installation process:

```bash
git clone https://github.com/archostofficial/odoo-multi-tenant.git
cd odoo-multi-tenant
chmod +x install.sh
sudo ./install.sh
```

The setup script will guide you through:
- Creating the directory structure
- Configuring environment variables
- Setting up Nginx
- Obtaining SSL certificates
- Starting the main Odoo instance
- Installing enterprise integration capabilities

### Manual Setup

If you prefer a manual installation:

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
- `setup/`: Installation and setup scripts

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

## Enterprise Integration

This setup includes support for Odoo Enterprise modules. To install enterprise modules for a tenant:

```bash
./scripts/install-enterprise.sh tenant_name
```

This will:
1. Clone the Odoo Enterprise repository (you'll need GitHub credentials)
2. Configure the tenant to use the enterprise modules
3. Restart the tenant's container to apply changes

After running the script, you can find and install enterprise modules from the Odoo Apps menu.

## Add-ons Management

The setup supports both shared add-ons (available to all tenants) and tenant-specific add-ons:

- Shared add-ons: `/opt/odoo-addons/shared/`
- Tenant-specific add-ons: `/opt/odoo-addons/tenant-specific/tenant_name/`
- Enterprise add-ons: `/opt/odoo-addons/enterprise/`

## Security Considerations

### Environment Variables

For improved security, the setup uses environment variables for sensitive information:

1. Copy the template file to create your environment file:
   ```bash
   cp /opt/odoo/.env.template /opt/odoo/.env
   ```

2. Edit the file to set secure values:
   ```bash
   nano /opt/odoo/.env
   ```

### Database Access Security

- Restrict database manager access in Nginx configurations
- Set strong admin passwords
- Implement regular backups

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
