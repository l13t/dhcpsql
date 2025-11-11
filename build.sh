#!/bin/bash

# DHCP SQL Server Build Script
# Builds the refactored uDHCP server with MySQL support

echo "🚀 Building DHCP SQL Server..."
echo "================================"

# Check if we're in the right directory
if [ ! -f "Makefile" ] || [ ! -d "src" ]; then
    echo "❌ Error: Please run this script from the project root directory"
    exit 1
fi

# Build using Docker for consistent Linux environment
echo "📦 Building in Docker container..."
docker run --rm -v $(pwd):/app -w /app docker-dhcpsql-build /bin/bash -c "
    echo '🧹 Cleaning previous build...'
    make clean
    
    echo '🔨 Building all targets...'
    make all
    
    echo '📋 Build results:'
    if [ -f udhcpd ] && [ -f dumpleases ]; then
        echo '✅ Build successful!'
        ls -la udhcpd dumpleases udhcpc 2>/dev/null || ls -la udhcpd dumpleases
        
        echo ''
        echo '🏷️  Binary information:'
        echo '  - udhcpd: DHCP server (combined binary - can also act as client when symlinked to udhcpc)'
        echo '  - dumpleases: Utility to display current DHCP leases'
        echo '  - udhcpc: Symlink to udhcpd for client functionality'
        
        echo ''
        echo '📁 Copying binaries to docker/output/ for easy access...'
        mkdir -p docker/output
        cp udhcpd dumpleases docker/output/
        [ -L udhcpc ] && cp udhcpc docker/output/
        
        echo '✅ Build complete! Binaries available in docker/output/'
    else
        echo '❌ Build failed - binaries not found'
        exit 1
    fi
"

# Check if build was successful
if [ $? -eq 0 ]; then
    echo ""
    echo "🎉 Build completed successfully!"
    echo "📁 Binaries are available in:"
    echo "   - Project root: $(pwd)"
    echo "   - Docker output: $(pwd)/docker/output/"
    echo ""
    echo "🔧 Usage examples:"
    echo "   ./udhcpd config/udhcpd.conf       # Run DHCP server"
    echo "   ./udhcpc -i eth0                  # Run DHCP client"
    echo "   ./dumpleases -f /var/lib/dhcp/udhcpd.leases -a  # Show leases"
else
    echo "❌ Build failed! Please check the error messages above."
    exit 1
fi
