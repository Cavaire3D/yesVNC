#!/bin/bash

# YesVNC Production Runner
# Automatically installs dependencies and starts both VNC server and web client

# Load configuration
source "$(dirname "$0")/config/load-config.sh"

# Get config values
WEB_PORT=$(get_config "web_port" "8080")
VNC_PORT=$(get_config "vnc_port" "5903")
VNC_HOST=$(get_config "vnc_host" "localhost")
WEBSOCKET_PORT=$(get_config "websocket_port" "80")

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

# Function to cleanup all project-related processes
cleanup() {
    echo -e "\n${YELLOW}🧹 Cleaning up YesVNC processes...${NC}"
    
    # Kill main processes
    pkill -f "start-vnc-server\|start-web-client\|run.sh" 2>/dev/null || true
    
    # Kill VNC and related processes
    pkill -f "wayvnc\|websockify\|Xvfb\|Xwayland" 2>/dev/null || true
    
    # Kill any remaining Python HTTP servers
    pkill -f "python3 -m http.server $WEB_PORT" 2>/dev/null || true
    
    # Kill any remaining websockify processes on our ports
    for port in $WEB_PORT $WEBSOCKET_PORT $VNC_PORT; do
        if ss -tuln | grep -q ":$port "; then
            echo -e "  ${YELLOW}Killing process on port $port${NC}"
            fuser -k "$port/tcp" 2>/dev/null || true
            # Identify sudo process and kill it
            sudo kill -9 $(sudo lsof -t -i :$port) 2>/dev/null || true
        fi
    done
    
    # Give processes a moment to terminate
    sleep 1
    
    # Verify cleanup
    RUNNING_PROCESSES=$(pgrep -f "start-vnc-server\|start-web-client\|wayvnc\|websockify\|Xvfb\|Xwayland" || true)
    if [ -n "$RUNNING_PROCESSES" ]; then
        echo -e "  ${YELLOW}Some processes did not terminate cleanly, forcing...${NC}"
        pkill -9 -f "start-vnc-server\|start-web-client\|wayvnc\|websockify\|Xvfb\|Xwayland" 2>/dev/null || true
    fi
    
    echo -e "${GREEN}✅ Cleanup completed${NC}"
}

trap cleanup EXIT

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
sleep 3

# Start web client
echo -e "\n${BLUE}🌐 Starting web client...${NC}"
if [ -f "$SCRIPT_DIR/start-web-client.sh" ]; then
    # Start the web client in the background
    bash "$SCRIPT_DIR/start-web-client.sh" > "$LOG_DIR/web-client.log" 2>&1 &
    WEB_PID=$!
    
    # Initial wait for the process to start
    sleep 1
    
    # Check if the process is still running after initial wait
    if ! kill -0 $WEB_PID 2>/dev/null; then
        echo -e "${RED}❌ Web client process failed to start${NC}"
        exit 1
    fi
    
    # Give more time for the web client to start, especially if it needs sudo
    echo -e "${YELLOW}⏳ Waiting for web client to start (may take a few seconds)...${NC}"
    
    # Wait up to 30 seconds for the web client to start
    WEB_STARTED=false
    for i in {1..30}; do
        # Check if the process is still running
        if ! kill -0 $WEB_PID 2>/dev/null; then
            echo -e "${RED}❌ Web client process stopped unexpectedly${NC}"
            exit 1
        fi
        
        # Check if the web server is responding
        if curl -s -o /dev/null --connect-timeout 1 "http://localhost:${WEB_PORT}"; then
            WEB_STARTED=true
            break
        fi
        
        sleep 1
    done
    
    if [ "$WEB_STARTED" = true ]; then
        echo -e "${GREEN}✅ Web client started successfully${NC}"
    else
        echo -e "${YELLOW}⚠️  Web client is taking longer than expected to start${NC}"
        echo -e "${YELLOW}   Check $LOG_DIR/web-client.log for details${NC}"
        # Don't exit here, as the process might still be starting
    fi
else
    echo -e "${RED}❌ start-web-client.sh not found!${NC}"
    exit 1
fi

# Display connection information
echo -e "\n${GREEN}🎉 YesVNC is now running!${NC}"
echo "==============================="
echo -e "${BLUE}📊 Connection Information:${NC}"
echo -e "  🌐 Web Interface: http://localhost:${WEB_PORT}"
echo "  🖥️  VNC Server: ${VNC_HOST}:${VNC_PORT}"
echo "  🔌 WebSocket Proxy: localhost:${WEBSOCKET_PORT}"
echo ""
echo -e "${YELLOW}📋 Usage:${NC}"
echo "  1. Open http://localhost:${WEB_PORT} in your web browser"
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
