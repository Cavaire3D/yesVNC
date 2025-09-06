#!/bin/bash

# YesVNC Production Runner
# Automatically installs dependencies and starts both VNC server and web client

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"

echo -e "${BLUE}🚀 YesVNC Production Runner${NC}"
echo "==============================="

# Create logs directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Function to cleanup on exit
cleanup() {
    echo -e "\n${YELLOW}🧹 Cleaning up...${NC}"
    # Kill VNC server and web client processes
    pkill -f "start-vnc-server\|start-web-client\|wayvnc\|websockify" 2>/dev/null || true
    echo -e "${GREEN}✅ Cleanup completed${NC}"
}

trap cleanup EXIT INT TERM

# Check if dependencies are installed
echo -e "${BLUE}🔍 Checking dependencies...${NC}"

DEPS_NEEDED=false

# Check for basic dependencies
if ! command -v wayvnc &> /dev/null; then
    echo -e "${YELLOW}⚠️  wayvnc not found${NC}"
    DEPS_NEEDED=true
fi

if ! command -v websockify &> /dev/null; then
    echo -e "${YELLOW}⚠️  websockify not found${NC}"
    DEPS_NEEDED=true
fi

if [ ! -d "noVNC" ]; then
    echo -e "${YELLOW}⚠️  noVNC not found${NC}"
    DEPS_NEEDED=true
fi

# Install dependencies if needed
if [ "$DEPS_NEEDED" = true ]; then
    echo -e "${BLUE}📦 Installing dependencies...${NC}"
    if [ -f "$SCRIPT_DIR/install-deps.sh" ]; then
        bash "$SCRIPT_DIR/install-deps.sh"
    else
        echo -e "${RED}❌ install-deps.sh not found!${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✅ All dependencies are installed${NC}"
fi

# Start VNC server
echo -e "\n${BLUE}🖥️  Starting VNC server...${NC}"
if [ -f "$SCRIPT_DIR/start-vnc-server.sh" ]; then
    bash "$SCRIPT_DIR/start-vnc-server.sh" &
    VNC_PID=$!
    sleep 3
    
    # Check if VNC server started successfully
    if kill -0 $VNC_PID 2>/dev/null; then
        echo -e "${GREEN}✅ VNC server started (PID: $VNC_PID)${NC}"
    else
        echo -e "${RED}❌ VNC server failed to start${NC}"
        exit 1
    fi
else
    echo -e "${RED}❌ start-vnc-server.sh not found!${NC}"
    exit 1
fi

# Wait a bit for VNC server to fully initialize
sleep 2

# Start web client
echo -e "\n${BLUE}🌐 Starting web client...${NC}"
if [ -f "$SCRIPT_DIR/start-web-client.sh" ]; then
    bash "$SCRIPT_DIR/start-web-client.sh" &
    WEB_PID=$!
    sleep 3
    
    # Check if web client started successfully
    if kill -0 $WEB_PID 2>/dev/null; then
        echo -e "${GREEN}✅ Web client started (PID: $WEB_PID)${NC}"
    else
        echo -e "${RED}❌ Web client failed to start${NC}"
        exit 1
    fi
else
    echo -e "${RED}❌ start-web-client.sh not found!${NC}"
    exit 1
fi

# Display connection information
echo -e "\n${GREEN}🎉 YesVNC is now running!${NC}"
echo "==============================="
echo -e "${BLUE}📊 Connection Information:${NC}"
echo "  🌐 Web Interface: http://localhost:8080"
echo "  🖥️  VNC Server: localhost:5903"
echo "  🔌 WebSocket Proxy: localhost:6080"
echo ""
echo -e "${YELLOW}📋 Usage:${NC}"
echo "  1. Open http://localhost:8080 in your web browser"
echo "  2. Click 'Connect' to access your desktop"
echo "  3. Press Ctrl+C to stop all services"
echo ""
echo -e "${BLUE}📝 Logs are available in: $LOG_DIR${NC}"

# Keep the script running and monitor processes
echo -e "\n${BLUE}🔄 Monitoring services... (Press Ctrl+C to stop)${NC}"
while true; do
    # Check if VNC server is still running
    if ! kill -0 $VNC_PID 2>/dev/null; then
        echo -e "${RED}❌ VNC server stopped unexpectedly${NC}"
        exit 1
    fi
    
    # Check if web client is still running
    if ! kill -0 $WEB_PID 2>/dev/null; then
        echo -e "${RED}❌ Web client stopped unexpectedly${NC}"
        exit 1
    fi
    
    sleep 5
done
