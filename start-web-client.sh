#!/bin/bash

# YesVNC Web Client Startup Script
# Starts the noVNC web client with websockify proxy

set -e

# Configuration
CONFIG_FILE="config/web-config.json"
LOG_DIR="logs"
WEB_PORT=${WEB_PORT:-8080}
VNC_HOST=${VNC_HOST:-localhost}
VNC_PORT=${VNC_PORT:-5903}
WEBSOCKET_PORT=${WEBSOCKET_PORT:-6080}

echo "🌐 Starting YesVNC Web Client..."

# Create logs directory
mkdir -p "$LOG_DIR"

# Function to cleanup on exit
cleanup() {
    echo "🧹 Cleaning up web client..."
    if [ ! -z "$WEBSOCKIFY_PID" ]; then
        kill $WEBSOCKIFY_PID 2>/dev/null || true
    fi
    if [ ! -z "$HTTP_SERVER_PID" ]; then
        kill $HTTP_SERVER_PID 2>/dev/null || true
    fi
}

trap cleanup EXIT

# Check if noVNC exists
if [ ! -d "noVNC" ]; then
    echo "❌ noVNC not found. Please run ./install-deps.sh first"
    exit 1
fi

# Create default web configuration if it doesn't exist
if [ ! -f "$CONFIG_FILE" ]; then
    echo "📝 Creating default web client configuration..."
    cat > "$CONFIG_FILE" << EOF
{
    "webPort": $WEB_PORT,
    "websocketPort": $WEBSOCKET_PORT,
    "vncHost": "$VNC_HOST",
    "vncPort": $VNC_PORT,
    "title": "YesVNC - Remote Desktop",
    "autoConnect": false,
    "encryption": false,
    "resizeSession": true,
    "showDotCursor": false,
    "logging": "warn"
}
EOF
fi

# Read configuration
WEB_PORT=$(jq -r '.webPort // 8080' "$CONFIG_FILE")
WEBSOCKET_PORT=$(jq -r '.websocketPort // 6080' "$CONFIG_FILE")
VNC_HOST=$(jq -r '.vncHost // "localhost"' "$CONFIG_FILE")
VNC_PORT=$(jq -r '.vncPort // 5903' "$CONFIG_FILE")

echo "📊 Web Client Configuration:"
echo "  Web Port: $WEB_PORT"
echo "  WebSocket Port: $WEBSOCKET_PORT"
echo "  VNC Target: $VNC_HOST:$VNC_PORT"

# Start websockify proxy
echo "🔌 Starting WebSocket proxy..."
websockify \
    --web noVNC \
    --cert="" \
    $WEBSOCKET_PORT \
    $VNC_HOST:$VNC_PORT \
    > "$LOG_DIR/websockify.log" 2>&1 &

WEBSOCKIFY_PID=$!

# Wait for websockify to start
sleep 2

# Check if websockify started successfully
if ! kill -0 $WEBSOCKIFY_PID 2>/dev/null; then
    echo "❌ Failed to start WebSocket proxy"
    exit 1
fi

echo "✅ WebSocket proxy started with PID $WEBSOCKIFY_PID"

# Start HTTP server for our custom web interface
echo "🌍 Starting HTTP server..."
cd web
python3 -m http.server $WEB_PORT > "../$LOG_DIR/http-server.log" 2>&1 &
HTTP_SERVER_PID=$!
cd ..

# Wait for HTTP server to start
sleep 2

# Check if HTTP server started successfully
if ! kill -0 $HTTP_SERVER_PID 2>/dev/null; then
    echo "❌ Failed to start HTTP server"
    exit 1
fi

echo "✅ HTTP server started with PID $HTTP_SERVER_PID"

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

# Keep the script running
wait $WEBSOCKIFY_PID
