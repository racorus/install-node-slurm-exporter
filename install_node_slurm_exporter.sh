#!/bin/bash
# Standard installation script for Prometheus Node Exporter and Slurm Exporter
# This script follows Linux FHS standards by placing binaries in /usr/local/bin
# Node Exporter is installed from prebuilt binaries
# Slurm Exporter is built from source

set -e  # Exit immediately if a command exits with a non-zero status

# Define versions
NODE_EXPORTER_VERSION="1.7.0"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting installation of Prometheus exporters...${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run this script as root or with sudo privileges${NC}"
    exit 1
fi

# Install dependencies
echo -e "${YELLOW}Installing dependencies...${NC}"
if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y wget tar curl golang git
elif command -v yum >/dev/null 2>&1; then
    yum install -y wget tar curl golang git
else
    echo -e "${RED}Unsupported package manager. Please install wget, tar, curl, golang, and git manually.${NC}"
    exit 1
fi

# Create temporary directory
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

#--------------------------------
# Install Node Exporter
#--------------------------------
echo -e "${YELLOW}Installing Node Exporter v${NODE_EXPORTER_VERSION}...${NC}"

# Check if Node Exporter is already installed
if systemctl is-active --quiet node_exporter.service; then
    echo -e "${YELLOW}Node Exporter is already running. Stopping service...${NC}"
    systemctl stop node_exporter.service
fi

# Download and extract Node Exporter
wget -q https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
tar xvfz node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz >/dev/null

# Create users if they don't exist
if ! id -u node_exporter >/dev/null 2>&1; then
    useradd --no-create-home --shell /bin/false node_exporter
    echo "Created node_exporter user"
fi

# Copy binary to standard location
cp node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/
chown node_exporter:node_exporter /usr/local/bin/node_exporter
chmod 755 /usr/local/bin/node_exporter

# Create textfile collector directory
mkdir -p /var/lib/node_exporter/textfile_collector
chown -R node_exporter:node_exporter /var/lib/node_exporter

# Create systemd service file
cat > /etc/systemd/system/node_exporter.service << EOF
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
Type=simple
User=node_exporter
Group=node_exporter
ExecStart=/usr/local/bin/node_exporter --collector.filesystem.mount-points-exclude=^/(dev|proc|sys|var/lib/docker/.+)(\$|/) --collector.textfile.directory="/var/lib/node_exporter/textfile_collector" --collector.cpu --collector.meminfo --collector.thermal_zone

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd, enable and start the service
systemctl daemon-reload
systemctl enable node_exporter
systemctl start node_exporter

# Check if Node Exporter is running
if systemctl is-active --quiet node_exporter.service; then
    echo -e "${GREEN}Node Exporter installed and running successfully${NC}"
else
    echo -e "${RED}Failed to start Node Exporter${NC}"
    exit 1
fi

#--------------------------------
# Install Slurm Exporter (from source)
#--------------------------------
echo -e "${YELLOW}Installing Slurm Exporter from source...${NC}"

# Check if Slurm client commands are available
if ! command -v sinfo >/dev/null 2>&1; then
    echo -e "${YELLOW}Warning: Slurm commands not found. Slurm Exporter may not function properly.${NC}"
    echo -e "${YELLOW}Make sure Slurm is installed and configured on this machine.${NC}"
fi

# Check if Slurm Exporter is already installed
if systemctl is-active --quiet slurm_exporter.service; then
    echo -e "${YELLOW}Slurm Exporter is already running. Stopping service...${NC}"
    systemctl stop slurm_exporter.service
fi

# Clone the repository
cd "$TEMP_DIR"
git clone https://github.com/vpenso/prometheus-slurm-exporter.git
cd prometheus-slurm-exporter

# Build the exporter
echo -e "${YELLOW}Building Slurm Exporter from source...${NC}"
go build

# Create user if it doesn't exist
if ! id -u slurm_exporter >/dev/null 2>&1; then
    useradd --no-create-home --shell /bin/false slurm_exporter
    echo "Created slurm_exporter user"
fi

# Copy binary to standard location
cp prometheus-slurm-exporter /usr/local/bin/
chown slurm_exporter:slurm_exporter /usr/local/bin/prometheus-slurm-exporter
chmod 755 /usr/local/bin/prometheus-slurm-exporter

# Create systemd service file
cat > /etc/systemd/system/slurm_exporter.service << EOF
[Unit]
Description=Prometheus Slurm Exporter
After=network.target

[Service]
Type=simple
User=slurm_exporter
Group=slurm_exporter
ExecStart=/usr/local/bin/prometheus-slurm-exporter

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd, enable and start the service
systemctl daemon-reload
systemctl enable slurm_exporter.service
systemctl start slurm_exporter.service

# Check if Slurm Exporter is running
if systemctl is-active --quiet slurm_exporter.service; then
    echo -e "${GREEN}Slurm Exporter installed and running successfully${NC}"
else
    echo -e "${RED}Failed to start Slurm Exporter. Check logs with: journalctl -u slurm_exporter.service${NC}"
    systemctl status slurm_exporter.service
    # We don't exit here to still provide a summary
fi

#--------------------------------
# Clean up
#--------------------------------
cd /
rm -rf "$TEMP_DIR"

#--------------------------------
# Verify installations
#--------------------------------
echo -e "${YELLOW}Verifying installations...${NC}"

# Check Node Exporter metrics
NODE_EXPORTER_RESPONSE=$(curl -s http://localhost:9100/metrics | wc -l)
if [ "$NODE_EXPORTER_RESPONSE" -gt 0 ]; then
    echo -e "${GREEN}Node Exporter is serving metrics at http://localhost:9100/metrics${NC}"
else
    echo -e "${RED}Node Exporter is not serving metrics properly${NC}"
fi

# Check Slurm Exporter metrics
SLURM_EXPORTER_RESPONSE=$(curl -s http://localhost:8080/metrics | wc -l)
if [ "$SLURM_EXPORTER_RESPONSE" -gt 0 ]; then
    echo -e "${GREEN}Slurm Exporter is serving metrics at http://localhost:8080/metrics${NC}"
else
    echo -e "${YELLOW}Slurm Exporter might not be serving metrics. Check if Slurm is properly configured.${NC}"
    echo -e "${YELLOW}View logs with: journalctl -u slurm_exporter.service${NC}"
fi

#--------------------------------
# Installation summary
#--------------------------------
echo ""
echo -e "${GREEN}=======================================================${NC}"
echo -e "${GREEN}Installation Summary:${NC}"
echo -e "${GREEN}=======================================================${NC}"
echo -e "${YELLOW}Node Exporter:${NC}"
echo -e "  - Version: ${NODE_EXPORTER_VERSION}"
echo -e "  - Service status: $(systemctl is-active node_exporter.service)"
echo -e "  - Binary location: /usr/local/bin/node_exporter"
echo -e "  - Metrics endpoint: http://localhost:9100/metrics"
echo -e "  - Run as user: node_exporter"
echo ""
echo -e "${YELLOW}Slurm Exporter:${NC}"
echo -e "  - Version: Built from source"
echo -e "  - Service status: $(systemctl is-active slurm_exporter.service 2>/dev/null || echo 'inactive')"
echo -e "  - Binary location: /usr/local/bin/prometheus-slurm-exporter"
echo -e "  - Metrics endpoint: http://localhost:8080/metrics"
echo -e "  - Run as user: slurm_exporter"
echo -e "${GREEN}=======================================================${NC}"
echo ""
echo -e "${GREEN}Installation completed!${NC}"
echo -e "${GREEN}To verify, you can run: curl http://localhost:9100/metrics${NC}"
echo -e "${GREEN}Or for Slurm Exporter: curl http://localhost:8080/metrics${NC}"

# Note about Slurm requirements
if ! command -v sinfo >/dev/null 2>&1; then
    echo ""
    echo -e "${YELLOW}NOTE: Slurm commands (sinfo, squeue, etc.) are required for the Slurm Exporter to work properly.${NC}"
    echo -e "${YELLOW}If you need to install Slurm client tools, please refer to your distribution's documentation.${NC}"
fi
