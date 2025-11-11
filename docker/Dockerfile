FROM ubuntu:24.04

# Avoid prompts from apt
ENV DEBIAN_FRONTEND=noninteractive

# Update package list and install build essentials and MySQL client library
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    gcc \
    make \
    cmake \
    libmysqlclient-dev \
    pkg-config \
    mysql-client \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy all source files
COPY . .

# Set proper permissions
RUN chmod +x .

# Default command to build the project
CMD ["/bin/bash", "-c", "echo 'Building DHCP SQL Server...' && make clean && make all && echo 'Build complete. Checking binaries:' && ls -la *.1 2>/dev/null || ls -la udhcp* dumpleases 2>/dev/null || echo 'No binaries found' && mkdir -p /app/docker/output && cp udhcp* dumpleases /app/docker/output/ 2>/dev/null || echo 'Failed to copy binaries'"]
