# DHCP Server Docker Setup

This directory contains a complete Docker Compose setup for running the udhcpd DHCP server with MySQL backend.

## Quick Start

### 1. Build the DHCP Server

```bash
# Build the udhcpd binary
./build.sh
```

### 2. Start MySQL and DHCP Server

#### For Development/Testing (Bridge Network)

```bash
# Start MySQL and DHCP server in bridge network mode
docker-compose -f docker-compose.dhcp.yml --profile bridge up -d

# View logs
docker-compose -f docker-compose.dhcp.yml logs -f udhcpd-bridge
```

#### For Production (Host Network)

```bash
# Start MySQL and DHCP server in host network mode
docker-compose -f docker-compose.dhcp.yml --profile host up -d

# View logs  
docker-compose -f docker-compose.dhcp.yml logs -f udhcpd-host
```

### 3. Access Services

- **PHPMyAdmin**: <http://localhost:8080>
  - Username: `dhcp`
  - Password: `dhcp`
- **MySQL**: localhost:3306
  - Database: `dhcp`
  - Username: `dhcp`
  - Password: `dhcp`

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   DHCP Client   │    │   udhcpd        │    │     MySQL       │
│   (Your Hosts)  │◄──►│   Container     │◄──►│   Container     │
│                 │    │                 │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
        │                       │                       │
        │                       │                       │
        ▼                       ▼                       ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Docker Network                              │
│                    172.20.0.0/16                              │
└─────────────────────────────────────────────────────────────────┘
```

## Services

### MySQL Database

- **Image**: mysql:8.0
- **Container**: dhcp-mysql
- **Port**: 3306
- **Database**: dhcp
- **User**: dhcp/dhcp

#### Database Schema

The MySQL database contains three main tables:

- `options`: DHCP options (DNS, gateway, etc.)
- `staticleases`: Static IP assignments (binary format)
- `staticleases_readable`: Static IP assignments (human-readable)
- `metaoptions`: DHCP option definitions

### DHCP Server (udhcpd)

- **Container**: dhcp-server-bridge (bridge mode) or dhcp-server-host (host mode)
- **Port**: 67/udp
- **Config**: `/etc/udhcpd.conf`

#### Network Modes

**Bridge Mode** (`--profile bridge`):

- Good for development and testing
- DHCP server runs in isolated network
- May have limitations with broadcast packets

**Host Mode** (`--profile host`):

- Recommended for production
- DHCP server uses host networking directly
- Full access to network interfaces
- Required for proper DHCP functionality

### PHPMyAdmin

- **Container**: dhcp-phpmyadmin
- **Port**: 8080
- Web interface for MySQL management

## Configuration Files

### udhcpd-docker.conf

DHCP server configuration for bridge network mode:

- MySQL server: `172.20.0.2`
- Interface: `eth0`
- IP range: `192.168.1.20-192.168.1.254`

### udhcpd-host.conf  

DHCP server configuration for host network mode:

- MySQL server: `127.0.0.1`
- Interface: `eth0` (adjust to your host interface)
- IP range: `192.168.1.20-192.168.1.254`

## Sample Data

The setup includes sample data:

- **Static leases**: Example MAC/IP assignments
- **DHCP options**: DNS servers, gateway, domain name
- **Option classes**: Different configurations for workstations vs servers

## Management Commands

### View Database Contents

```bash
# Connect to MySQL
docker-compose -f docker-compose.dhcp.yml exec mysql mysql -u dhcp -pdhcp dhcp

# View static leases
SELECT * FROM staticleases_readable;

# View DHCP options
SELECT o.class, m.name, o.code, o.data 
FROM options o 
LEFT JOIN metaoptions m ON o.code = m.id 
ORDER BY o.class, o.code;
```

### Add Static Lease

```bash
# Via database
INSERT INTO staticleases_readable (mac, ip, class) VALUES ('001122334458', '192.168.1.103', 1);

# Via config file (add to udhcpd.conf)
static_lease    00:11:22:33:44:58    192.168.1.103
```

### View DHCP Logs

```bash
# Bridge mode
docker-compose -f docker-compose.dhcp.yml logs -f udhcpd-bridge

# Host mode  
docker-compose -f docker-compose.dhcp.yml logs -f udhcpd-host
```

### Backup Database

```bash
docker-compose -f docker-compose.dhcp.yml exec mysql mysqldump -u dhcp -pdhcp dhcp > dhcp-backup.sql
```

## Troubleshooting

### DHCP Server Not Responding

1. Check if running in host mode: `docker-compose -f docker-compose.dhcp.yml --profile host up -d`
2. Verify network interface in config matches host interface
3. Check firewall rules allow UDP port 67
4. Ensure no other DHCP server is running

### MySQL Connection Issues

1. Wait for MySQL to fully start (check health status)
2. Verify MySQL credentials in udhcpd config
3. Check MySQL container logs: `docker-compose -f docker-compose.dhcp.yml logs mysql`

### Permission Issues

1. Ensure Docker has proper permissions
2. For host mode, may need `--privileged` flag
3. Check `cap_add: NET_ADMIN, NET_RAW` permissions

## Customization

### Network Configuration

Edit the configuration files to match your network:

- IP ranges (`start`/`end`)
- Network interface (`interface`)
- Gateway and DNS servers (`opt` directives)

### Database Options

Add custom DHCP options via SQL:

```sql
INSERT INTO options (class, code, data) VALUES (0, 42, INET_ATON('192.168.1.10'));
```

### Advanced Options

- Enable PXE boot by uncommenting TFTP options
- Configure multiple IP classes for different device types
- Set up vendor-specific options for specialized equipment

## Production Deployment

For production deployment:

1. Use host network mode (`--profile host`)
2. Configure proper network interface in `udhcpd-host.conf`
3. Set up proper backup procedures for MySQL data
4. Monitor DHCP lease usage and logs
5. Configure log rotation for container logs
6. Use Docker secrets for database passwords
