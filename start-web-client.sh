#!/bin/bash

# YesVNC Web Client Startup Script
# Starts the noVNC web client with websockify proxy

set -e

# Function to check if a port is privileged (requires root)
# Sets SUDO_CMD variable to 'sudo ' if needed, empty otherwise
check_privileged_port() {
    local port=$1
    SUDO_CMD=""
    if [ "$port" -lt 1024 ] && [ "$(id -u)" -ne 0 ]; then
        echo "🔒 Port $port is a privileged port (below 1024) and requires root access"
        # Check if we can use sudo
        if command -v sudo &> /dev/null; then
            echo "🔑 Attempting to use sudo to bind to privileged port"
            [ "$UID" -eq 0 ] || exec sudo bash "$0" "$@"
        else
            echo "❌ sudo is not available. Cannot bind to privileged port $port"
            return 1
        fi
    fi
    return 0
}

# Get script directory for absolute paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the config loader to ensure config exists and load functions
source "$SCRIPT_DIR/config/load-config.sh"

# Set paths
LOG_DIR="$SCRIPT_DIR/logs"

# Get configuration with defaults
WEB_PORT=$(get_config "web.port" "8080")
VNC_HOST=$(get_config "server.vnc.host" "localhost")
VNC_PORT=$(get_config "server.vnc.port" "5903")
WEBSOCKET_PORT=$(get_config "web.websocketPort" "6080")
TITLE=$(get_config "web.title" "YesVNC - Remote Desktop")
AUTO_CONNECT=$(get_config "web.autoConnect" "false")
ENCRYPTION=$(get_config "web.encryption" "false")
RESIZE_SESSION=$(get_config "web.resizeSession" "true")
SHOW_DOT_CURSOR=$(get_config "web.showDotCursor" "false")
LOGGING_LEVEL=$(get_config "web.logging" "warn")

echo "🌐 Starting YesVNC Web Client..."

# Create logs directory
mkdir -p "$LOG_DIR"

# Function to cleanup on exit
cleanup() {
    echo "🧹 Cleaning up web client..."
    # Kill processes only if they're still running
    if [ ! -z "$WEBSOCKIFY_PID" ] && ps -p "$WEBSOCKIFY_PID" > /dev/null 2>&1; then
        echo "  Stopping websockify (PID: $WEBSOCKIFY_PID)..."
        kill -TERM "$WEBSOCKIFY_PID" 2>/dev/null || true
        # Give it a moment to shut down cleanly
    fi
    
    if [ ! -z "$HTTP_SERVER_PID" ] && ps -p "$HTTP_SERVER_PID" > /dev/null 2>&1; then
        echo "  Stopping HTTP server (PID: $HTTP_SERVER_PID)..."
        kill -TERM "$HTTP_SERVER_PID" 2>/dev/null || true
        
    fi
    
    # Clean up any remaining websockify processes we might have started
    pkill -f "websockify.*$WEBSOCKET_PORT" 2>/dev/null || true
}

trap cleanup EXIT

# Check if noVNC exists
if [ ! -d "noVNC" ]; then
    echo "❌ noVNC not found. Please run ./install-deps.sh first"
    exit 1
fi

# Configuration already loaded via load-config.sh

echo "📊 Web Client Configuration:"
echo "  Web Port: $WEB_PORT"
echo "  WebSocket Port: $WEBSOCKET_PORT"
echo "  VNC Target: $VNC_HOST:$VNC_PORT"


# Function to check if a websockify process is running on a port
is_websockify_running() {
    local port=$1
    # Use ss to check for websockify process listening on the port
    if sudo ss -ltnup | grep -q ":$port.*websockify"; then
        local pid=$(sudo ss -ltnup | grep ":$port" | grep -o 'pid=[0-9]*' | cut -d= -f2 | head -1)
        echo "✅ Found existing websockify process (PID: $pid) on port $port"
        return 0
    fi
    return 1
}

# Function to check if a port is available or running websockify
check_port_available() {
    local port=$1
    
    # First check if websockify is already running on this port
    if is_websockify_running "$port"; then
        # If it's websockify, we can use this port
        return 0
    fi
    
    # If not websockify, check if the port is in use by something else
    if command -v ss &> /dev/null; then
        if ss -tuln | grep -q ":$port "; then
            return 1  # Port is in use by something else
        fi
    elif command -v netstat &> /dev/null; then
        if netstat -tuln | grep -q ":$port "; then
            return 1  # Port is in use by something else
        fi
    fi
    
    return 0  # Port is available
}

# Check if the requested port is available
if ! check_port_available "$WEBSOCKET_PORT"; then
    echo "⚠️  Port $WEBSOCKET_PORT is already in use."
    
    # Try to find an available port between 8080-8090
    new_port=""
    for new_port in {8080..8090}; do
        if check_port_available "$new_port"; then
            echo "🔍 Found available port: $new_port"
            read -p "Would you like to use port $new_port instead? [Y/n] " -r
            if [[ $REPLY =~ ^[Yy]?$ ]]; then
                WEBSOCKET_PORT=$new_port
                echo "✅ Using port $WEBSOCKET_PORT"
                break
            else
                echo "❌ Port $WEBSOCKET_PORT is in use. Please choose a different port and try again."
                exit 1
            fi
        fi
    done
    
    if [ "$WEBSOCKET_PORT" -ne "$new_port" ]; then
        echo "❌ Could not find an available port. Please free up port $WEBSOCKET_PORT or specify a different port."
        exit 1
    fi
fi

# Function to check if a port is privileged (below 1024)
is_privileged_port() {
    [ "$1" -lt 1024 ]
}

# Start websockify proxy if not already running
if is_websockify_running "$WEBSOCKET_PORT"; then
    echo "🔌 Using existing websockify instance on port $WEBSOCKET_PORT"
    # Try without sudo first, then with sudo if needed
    WEBSOCKIFY_PID=$(ss -ltnup 2>/dev/null | grep ":$WEBSOCKET_PORT" | grep -o 'pid=[0-9]*' | cut -d= -f2 | head -1)
    if [ -z "$WEBSOCKIFY_PID" ] && [ -x "$(command -v sudo)" ]; then
        WEBSOCKIFY_PID=$(sudo ss -ltnup 2>/dev/null | grep ":$WEBSOCKET_PORT" | grep -o 'pid=[0-9]*' | cut -d= -f2 | head -1)
    fi
else
    echo "🔌 Starting WebSocket proxy on port $WEBSOCKET_PORT..."
    
    # Ensure log directory exists and is writable
    mkdir -p "$LOG_DIR"
    touch "$LOG_DIR/websockify.log"
    chmod 666 "$LOG_DIR/websockify.log" 2>/dev/null || true
    
    # Start websockify with increased buffer sizes and better error handling
    # Note: Removed --ssl-target as wayvnc doesn't use SSL by default
    WEBSOCKIFY_CMD="websockify \
        --web noVNC \
        --cert="" \
        --record "$LOG_DIR/websockify_record.log" \
        $WEBSOCKET_PORT \
        $VNC_HOST:$VNC_PORT"
    
    if is_privileged_port "$WEBSOCKET_PORT"; then
        # For privileged ports, we need sudo
        if ! sudo -n true 2>/dev/null; then
            echo "🔑 sudo access is required for privileged port $WEBSOCKET_PORT"
        fi
        sudo $WEBSOCKIFY_CMD >> "$LOG_DIR/websockify.log" 2>&1 &
    else
        # For non-privileged ports, try without sudo first
        $WEBSOCKIFY_CMD >> "$LOG_DIR/websockify.log" 2>&1 &
    fi
    
    WEBSOCKIFY_PID=$!
    echo "✅ WebSocket proxy started with PID $WEBSOCKIFY_PID"
    
    # Wait a moment for websockify to start
    sleep 1
    
    # Verify websockify started successfully
    if ! ps -p "$WEBSOCKIFY_PID" > /dev/null 2>&1; then
        echo "❌ Failed to start WebSocket proxy. Check $LOG_DIR/websockify.log for details."
        exit 1
    fi
fi



echo "✅ WebSocket proxy started with PID $WEBSOCKIFY_PID"

# Check if we need sudo for HTTP port
SUDO_HTTP=""
if ! check_privileged_port "$WEB_PORT"; then
    exit 1
fi

# Start HTTP server for our custom web interface
echo "🌍 Starting HTTP server on port $WEB_PORT..."

# Ensure log directory exists and is writable
touch "$LOG_DIR/http-server.log"
chmod 666 "$LOG_DIR/http-server.log" 2>/dev/null || true

# Start HTTP server with better error handling
cd web
if ! check_privileged_port "$WEB_PORT"; then
    python3 -m http.server $WEB_PORT >> "$LOG_DIR/http-server.log" 2>&1 &
    HTTP_SERVER_PID=$!
else
    if ! sudo -n true 2>/dev/null; then
        echo "🔑 sudo access is required for port $WEB_PORT. Please enter your password when prompted."
    fi
    sudo python3 -m http.server $WEB_PORT >> "$LOG_DIR/http-server.log" 2>&1 &
    HTTP_SERVER_PID=$!
fi
cd ..

# Wait a moment for HTTP server to start
sleep 2

# Verify HTTP server started successfully
if ! ps -p "$HTTP_SERVER_PID" > /dev/null 2>&1; then
    echo "❌ Failed to start HTTP server. Check $LOG_DIR/http-server.log for details."
    exit 1
fi


# Check if HTTP server started successfully
if ! kill -0 $HTTP_SERVER_PID 2>/dev/null; then
    echo "❌ Failed to start HTTP server"
    exit 1
fi

echo "✅ HTTP server started with PID $HTTP_SERVER_PID"

# Function to handle script termination
terminate() {
    echo -e "\n🛑 Received termination signal. Shutting down..."
    cleanup
    exit 0
}

# Set up trap for termination signals
trap terminate SIGINT SIGTERM

echo ""
echo "🎉 YesVNC Web Client is ready!"
echo "📱 Open your browser and navigate to:"
echo "   http://localhost:$WEB_PORT"
echo ""
echo "🔗 Direct noVNC access:"
echo "   http://localhost:$WEBSOCKET_PORT/vnc.html?host=localhost&port=$WEBSOCKET_PORT"
echo ""
echo "📝 Logs available in $LOG_DIR/"
echo "🔄 Web client is running. Press Ctrl+C to stop."

# Function to check if a process is running and get its status
is_process_running() {
    local pid=$1
    local process_name=$2
    
    # Check if process exists
    if ! ps -p "$pid" > /dev/null 2>&1; then
        return 1  # Process not found
    fi
    
    # If process name is provided, verify it matches
    if [ -n "$process_name" ]; then
        local cmd=$(ps -p "$pid" -o cmd= 2>/dev/null)
        if [[ ! "$cmd" =~ $process_name ]]; then
            echo "⚠️  Process $pid is not a $process_name process"
            return 1
        fi
    fi
    
    return 0  # Process is running and matches name (if provided)
}

# Function to get process status with resource usage
get_process_status() {
    local pid=$1
    local name=$2
    
    if is_process_running "$pid" "$name"; then
        local stats=$(ps -o %cpu,%mem,rss,vsz,etime,cmd -p "$pid" 2>/dev/null | tail -n +2)
        echo "✅ $name (PID: $pid) - $stats"
        return 0
    else
        echo "❌ $name (PID: $pid) is not running"
        return 1
    fi
}

# Main monitoring loop - simplified
while true; do
    # Check websockify
    if ! is_process_running "$WEBSOCKIFY_PID" "websockify"; then
        # Try to restart if it's been less than 5 minutes
        if [ $SECONDS -lt 300 ] && is_websockify_running "$WEBSOCKET_PORT"; then
            WEBSOCKIFY_PID=$(sudo ss -ltnup | grep ":$WEBSOCKET_PORT" | grep -o 'pid=[0-9]*' | cut -d= -f2 | head -1)
        fi
    fi
    
    # Check HTTP server
    if ! is_process_running "$HTTP_SERVER_PID" "http.server"; then
        if [ $SECONDS -lt 300 ]; then  # Only try to restart in first 5 minutes
            cd web
            python3 -m http.server $WEB_PORT >> "../$LOG_DIR/http-server.log" 2>&1 &
            HTTP_SERVER_PID=$!
            cd ..
            sleep 1
        fi
    fi
    
    # Sleep before next check
    sleep 5
done

# If we get here, one of the processes stopped and couldn't be recovered
cleanup
echo "❌ Web client has stopped. Check the logs in $LOG_DIR/ for more information."
exit 1

