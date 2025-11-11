#!/bin/bash
# Modern deployment script for DHCP SQL Server

set -euo pipefail

# Configuration
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-rootpassword}"
MYSQL_DATABASE="${MYSQL_DATABASE:-dhcp}"
MYSQL_USER="${MYSQL_USER:-dhcp}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-dhcp}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# Check if running as root
check_privileges() {
    if [[ $EUID -eq 0 ]]; then
        warn "Running as root. Consider using a dedicated user for production."
    fi
}

# Install dependencies
install_dependencies() {
    log "Installing dependencies..."
    
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get install -y mysql-server libmysqlclient-dev build-essential cmake
    elif command -v yum >/dev/null 2>&1; then
        yum install -y mysql-server mysql-devel gcc cmake make
    elif command -v pacman >/dev/null 2>&1; then
        pacman -S --noconfirm mysql gcc cmake make
    else
        error "Unsupported package manager. Please install dependencies manually."
    fi
}

# Setup MySQL database
setup_database() {
    log "Setting up MySQL database..."
    
    # Start MySQL service
    if systemctl is-active --quiet mysql; then
        log "MySQL is already running"
    else
        systemctl start mysql
        systemctl enable mysql
    fi
    
    # Create database and user
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" <<EOF
CREATE DATABASE IF NOT EXISTS ${MYSQL_DATABASE};
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'localhost' IDENTIFIED BY '${MYSQL_PASSWORD}';
GRANT ALL PRIVILEGES ON ${MYSQL_DATABASE}.* TO '${MYSQL_USER}'@'localhost';
FLUSH PRIVILEGES;

USE ${MYSQL_DATABASE};

-- Create static leases table
CREATE TABLE IF NOT EXISTS staticleases (
    mac BIGINT(6) NOT NULL,
    ip BIGINT(11) DEFAULT NULL,
    class INT(11) DEFAULT NULL,
    hostname VARCHAR(255) DEFAULT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (mac),
    UNIQUE KEY ip (ip),
    INDEX idx_class (class)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Create options table
CREATE TABLE IF NOT EXISTS options (
    id INT(11) NOT NULL AUTO_INCREMENT,
    class INT(11) NOT NULL,
    code TINYINT(5) NOT NULL,
    data VARCHAR(255) NOT NULL,
    description VARCHAR(255) DEFAULT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    INDEX idx_class_code (class, code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Create lease log table for audit
CREATE TABLE IF NOT EXISTS lease_log (
    id BIGINT AUTO_INCREMENT,
    mac BIGINT(6) NOT NULL,
    ip BIGINT(11) NOT NULL,
    action ENUM('ASSIGN', 'RENEW', 'RELEASE', 'EXPIRE') NOT NULL,
    lease_start TIMESTAMP NOT NULL,
    lease_end TIMESTAMP NOT NULL,
    hostname VARCHAR(255) DEFAULT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    INDEX idx_mac (mac),
    INDEX idx_ip (ip),
    INDEX idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
EOF

    log "Database setup completed"
}

# Build the application
build_application() {
    log "Building DHCP SQL Server..."
    
    # Create build directory
    mkdir -p build
    cd build
    
    # Configure with CMake
    cmake .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DENABLE_MYSQL=ON \
        -DENABLE_DEBUG=OFF \
        -DCOMBINED_BINARY=ON
    
    # Build
    make -j"$(nproc)"
    
    log "Build completed successfully"
}

# Install the application
install_application() {
    log "Installing DHCP SQL Server..."
    
    cd build
    make install
    
    # Create system user
    if ! id "dhcp" &>/dev/null; then
        useradd -r -s /bin/false -d /var/lib/dhcp dhcp
    fi
    
    # Create directories
    mkdir -p /var/lib/dhcp /var/log/dhcp /etc/dhcp
    chown dhcp:dhcp /var/lib/dhcp /var/log/dhcp
    
    # Install configuration
    if [[ ! -f /etc/dhcp/udhcpd.conf ]]; then
        cp ../config/modern_udhcpd.conf /etc/dhcp/udhcpd.conf
        log "Sample configuration installed to /etc/dhcp/udhcpd.conf"
    fi
    
    log "Installation completed"
}

# Create systemd service
create_service() {
    log "Creating systemd service..."
    
    cat > /etc/systemd/system/udhcpd.service <<EOF
[Unit]
Description=Lightweight DHCP Server with MySQL Support
Documentation=man:udhcpd(8)
After=network.target mysql.service
Wants=network.target
Requires=mysql.service

[Service]
Type=forking
PIDFile=/var/run/udhcpd.pid
ExecStart=/usr/local/sbin/udhcpd /etc/dhcp/udhcpd.conf
ExecReload=/bin/kill -HUP \$MAINPID
User=dhcp
Group=dhcp
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/dhcp /var/log/dhcp /var/run
NoNewPrivileges=true
CapabilityBoundingSet=CAP_NET_BIND_SERVICE CAP_NET_RAW

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable udhcpd
    
    log "Systemd service created and enabled"
}

# Main deployment function
main() {
    log "Starting DHCP SQL Server deployment..."
    
    check_privileges
    install_dependencies
    setup_database
    build_application
    install_application
    create_service
    
    log "Deployment completed successfully!"
    log "Configuration file: /etc/dhcp/udhcpd.conf"
    log "Start service: systemctl start udhcpd"
    log "Check status: systemctl status udhcpd"
    log "View logs: journalctl -u udhcpd -f"
}

# Run main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
