#!/bin/bash
# install.sh - Complete dependency installer

set -e  # Exit on error

echo "========================================"
echo "AASTMT System Monitor - Stage 1 Installer"
echo "========================================"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root: sudo ./install.sh${NC}"
    exit 1
fi

echo -e "${YELLOW}Updating package lists...${NC}"
apt update

echo -e "\n${YELLOW}Installing core monitoring tools...${NC}"

# Essential tools
apt install -y \
    lm-sensors \
    smartmontools \
    htop \
    iotop \
    iproute2 \
    net-tools \
    bc \
    curl \
    wget \
    pciutils \
    usbutils \
    dmidecode \
    sysstat

echo -e "\n${YELLOW}Installing GUI components for Stage 3...${NC}"
apt install -y \
    dialog \
    whiptail \
    zenity

echo -e "\n${YELLOW}Installing Python for optional features...${NC}"
apt install -y \
    python3 \
    python3-pip \
    python3-psutil

echo -e "\n${YELLOW}Configuring sensors...${NC}"
if command -v sensors-detect >/dev/null 2>&1; then
    echo "Running sensors-detect (choose YES to defaults)..."
    yes | sensors-detect --auto || true
fi

echo -e "\n${YELLOW}Setting up permissions...${NC}"
# Allow non-root users to read some system info (optional)
chmod +x scripts/monitor.sh 2>/dev/null || true

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}To test your installation:${NC}"
echo "1. Run the monitor: ${GREEN}./scripts/monitor.sh${NC}"
echo "2. Generate HTML report: ${GREEN}./scripts/monitor.sh --html${NC}"
echo "3. Test all functions: ${GREEN}./test-stage1.sh${NC}"
echo ""
echo -e "${YELLOW}Project Structure:${NC}"
echo "  scripts/monitor.sh    - Main monitoring script"
echo "  reports/              - Generated reports"
echo "  install.sh           - This installer"
echo ""
echo -e "${YELLOW}Next: Stage 2 - Docker Containerization${NC}"