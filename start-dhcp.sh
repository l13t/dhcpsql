#!/bin/bash

# Quick start script for DHCP Docker setup
# Usage: ./start-dhcp.sh [bridge|host|stop|logs]

set -e

COMPOSE_FILE="docker-compose.dhcp.yml"
DEFAULT_PROFILE="bridge"

show_usage() {
    echo "🚀 DHCP Server Docker Management Script"
    echo ""
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  bridge    Start DHCP server in bridge network mode (default)"
    echo "  host      Start DHCP server in host network mode (production)"
    echo "  stop      Stop all DHCP services"
    echo "  logs      Show logs from running services"
    echo "  status    Show status of all services"
    echo "  db        Connect to MySQL database"
    echo "  help      Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 bridge    # Start in development mode"
    echo "  $0 host      # Start in production mode"
    echo "  $0 logs      # View logs"
    echo "  $0 stop      # Stop everything"
    echo ""
    echo "Services will be available at:"
    echo "  📊 PHPMyAdmin: http://localhost:8080 (dhcp/dhcp)"
    echo "  🗄️  MySQL: localhost:3306 (dhcp/dhcp)"
}

ensure_built() {
    if [ ! -f "udhcpd" ]; then
        echo "⚠️  udhcpd binary not found. Building..."
        ./build.sh
    fi
}

start_bridge() {
    echo "🌉 Starting DHCP server in bridge network mode..."
    ensure_built
    docker-compose -f $COMPOSE_FILE --profile bridge up -d
    echo ""
    echo "✅ DHCP server started in bridge mode!"
    echo "📋 View logs: $0 logs"
    echo "🌐 PHPMyAdmin: http://localhost:8080"
}

start_host() {
    echo "🖥️  Starting DHCP server in host network mode..."
    ensure_built
    docker-compose -f $COMPOSE_FILE --profile host up -d
    echo ""
    echo "✅ DHCP server started in host mode!"
    echo "📋 View logs: $0 logs"
    echo "🌐 PHPMyAdmin: http://localhost:8080"
    echo ""
    echo "⚠️  Note: Make sure to configure the correct network interface"
    echo "   in config/udhcpd-host.conf for your system!"
}

stop_services() {
    echo "🛑 Stopping all DHCP services..."
    docker-compose -f $COMPOSE_FILE --profile bridge down
    docker-compose -f $COMPOSE_FILE --profile host down
    echo "✅ All services stopped!"
}

show_logs() {
    echo "📋 Showing logs for running services..."
    if docker-compose -f $COMPOSE_FILE ps --services --filter="status=running" | grep -q "udhcpd-bridge"; then
        echo "🌉 Bridge mode logs:"
        docker-compose -f $COMPOSE_FILE logs --tail=50 -f udhcpd-bridge mysql
    elif docker-compose -f $COMPOSE_FILE ps --services --filter="status=running" | grep -q "udhcpd-host"; then
        echo "🖥️  Host mode logs:"
        docker-compose -f $COMPOSE_FILE logs --tail=50 -f udhcpd-host mysql
    else
        echo "ℹ️  No DHCP services running. Showing all service logs:"
        docker-compose -f $COMPOSE_FILE logs --tail=50
    fi
}

show_status() {
    echo "📊 Service Status:"
    docker-compose -f $COMPOSE_FILE ps
    echo ""
    echo "🐳 Docker containers:"
    docker ps --filter="name=dhcp-" --format="table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

connect_db() {
    echo "🗄️  Connecting to MySQL database..."
    if ! docker-compose -f $COMPOSE_FILE exec mysql mysql -u dhcp -pdhcp dhcp; then
        echo "❌ Failed to connect to MySQL. Is it running?"
        echo "   Start services first: $0 bridge"
    fi
}

# Main script logic
case "${1:-$DEFAULT_PROFILE}" in
    "bridge"|"dev"|"development")
        start_bridge
        ;;
    "host"|"prod"|"production")
        start_host
        ;;
    "stop"|"down")
        stop_services
        ;;
    "logs"|"log")
        show_logs
        ;;
    "status"|"ps")
        show_status
        ;;
    "db"|"mysql"|"database")
        connect_db
        ;;
    "help"|"-h"|"--help")
        show_usage
        ;;
    *)
        echo "❌ Unknown command: $1"
        echo ""
        show_usage
        exit 1
        ;;
esac
