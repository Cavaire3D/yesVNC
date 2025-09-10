#!/bin/bash

# YesVNC Server Startup Script
# Starts waylandvnc server with headless display support

set -e

# Get script directory for absolute paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the config loader to ensure config exists and load functions
source "$SCRIPT_DIR/config/load-config.sh"

# Set paths
LOG_DIR="$SCRIPT_DIR/logs"

# Read configuration with defaults
VNC_DISPLAY=$(get_config "server.display" "3")
VNC_PORT=$(get_config "server.port" "5903")
HEADLESS=$(get_config "server.headless" "true")
WIDTH=$(get_config "server.resolution.width" "1920")
HEIGHT=$(get_config "server.resolution.height" "1080")
DEPTH=$(get_config "server.resolution.depth" "24")
VNC_HOST=$(get_config "server.vnc.host" "localhost")
VNC_TARGET_PORT=$(get_config "server.vnc.port" "5903")

# Set compositor
COMPOSITOR=$(get_config "server.compositor" "$(command -v pacman &> /dev/null && echo "hyprland" || echo "wayfire")")

echo "🚀 Starting YesVNC Server..."

# Create logs directory
mkdir -p "$LOG_DIR"

# Function to find and kill existing processes
kill_existing_instances() {
    echo "🔍 Looking for existing VNC server processes..."
    
    # Kill any existing wayvnc processes
    local wayvnc_pids=$(pgrep -f "wayvnc" || true)
    if [ ! -z "$wayvnc_pids" ]; then
        echo "🛑 Found existing wayvnc processes (PIDs: $wayvnc_pids), killing them..."
        kill $wayvnc_pids 2>/dev/null || true
    fi
    
    # Kill any existing Xvfb processes on our display
    local xvfb_pids=$(pgrep -f "Xvfb.*:$VNC_DISPLAY " || true)
    if [ ! -z "$xvfb_pids" ]; then
        echo "🛑 Found existing Xvfb processes on display :$VNC_DISPLAY (PIDs: $xvfb_pids), killing them..."
        kill $xvfb_pids 2>/dev/null || true
    fi
    
    # Give processes a moment to shut down
    sleep 1
}
# Kill any existing instances before starting
kill_existing_instances


# Function to cleanup on exit
cleanup() {
    echo "🧹 Cleaning up..."
    # Only kill compositor if we started it ourselves (not using existing session)
    if [ ! -z "$COMPOSITOR_PID" ] && [ "$EXISTING_SESSION" != "true" ]; then
        echo "🛑 Stopping compositor we started (PID: $COMPOSITOR_PID)"
        kill $COMPOSITOR_PID 2>/dev/null || true
    elif [ "$EXISTING_SESSION" = "true" ]; then
        echo "ℹ️  Leaving existing Hyprland session running"
    fi
    # Clean up temporary weston config
    rm -f "/tmp/weston-$VNC_DISPLAY.ini" 2>/dev/null || true
    if [ ! -z "$XVFB_PID" ]; then
        kill $XVFB_PID 2>/dev/null || true
    fi
    if [ ! -z "$WAYVNC_PID" ]; then
        kill $WAYVNC_PID 2>/dev/null || true
    fi
}

trap cleanup EXIT

# Configuration already loaded at the top of the script

echo "📊 Configuration:"
echo "  Display: :$VNC_DISPLAY"
echo "  Port: $VNC_PORT"
echo "  Headless: $HEADLESS"
echo "  Compositor: $COMPOSITOR"
echo "  Resolution: ${WIDTH}x${HEIGHT}@${DEPTH}"

# Setup display connection
if [ "$HEADLESS" = "true" ]; then
    echo "🖥️ Setting up display connection..."
    
    # Check if we need X11 or Wayland
    if [ "$COMPOSITOR" = "wayfire" ] || [ "$COMPOSITOR" = "hyprland" ]; then
        # First, check if there's already a running Hyprland session we can use
        if [ "$COMPOSITOR" = "hyprland" ] && pgrep -x "Hyprland" > /dev/null; then
            echo "🔍 Found existing Hyprland session"
            # Use the existing Hyprland session - check for WAYLAND_DISPLAY
            if [ -n "$WAYLAND_DISPLAY" ]; then
                echo "✅ Using existing Hyprland session on $WAYLAND_DISPLAY"
                EXISTING_SESSION=true
            else
                # Try common Wayland display names
                for display in wayland-0 wayland-1; do
                    if [ -e "/run/user/$(id -u)/$display" ]; then
                        export WAYLAND_DISPLAY="$display"
                        echo "✅ Using existing Hyprland session on $display"
                        EXISTING_SESSION=true
                        break
                    fi
                done
            fi
        fi
        
        # If no existing session found, create a new headless one
        if [ "$EXISTING_SESSION" != "true" ]; then
            echo "🚀 Creating new headless compositor session..."
            # For Wayland/wlroots, we need a unique virtual display socket
            # Use a unique socket name to avoid conflicts with existing compositors
            WAYLAND_SOCKET="wayland-yesVNC-$VNC_DISPLAY"
            export WAYLAND_DISPLAY="$WAYLAND_SOCKET"
        
        # Check for existing compositor processes using this socket
        echo "🔍 Checking for existing compositor processes..."
        if pgrep -f "$COMPOSITOR.*$WAYLAND_SOCKET" > /dev/null; then
            echo "⚠️  Found existing $COMPOSITOR process using socket $WAYLAND_SOCKET, killing it..."
            pkill -f "$COMPOSITOR.*$WAYLAND_SOCKET" || true
            sleep 2
        fi
        
        # Clean up any existing socket files
        SOCKET_PATH="/run/user/$(id -u)/$WAYLAND_SOCKET"
        if [ -e "$SOCKET_PATH" ]; then
            echo "🧹 Cleaning up existing socket: $SOCKET_PATH"
            rm -f "$SOCKET_PATH" || true
        fi
        
        # Also clean up lock files
        LOCK_PATH="/run/user/$(id -u)/$WAYLAND_SOCKET.lock"
        if [ -e "$LOCK_PATH" ]; then
            echo "🧹 Cleaning up existing lock file: $LOCK_PATH"
            rm -f "$LOCK_PATH" || true
        fi
        
        # Start wlroots-based compositor only if we don't have an existing session
        if [ "$EXISTING_SESSION" != "true" ]; then
            echo "🌊 Starting $COMPOSITOR compositor (headless mode)..."
            
            # Unset WAYLAND_DISPLAY temporarily to prevent nested mode
            ORIGINAL_WAYLAND_DISPLAY="$WAYLAND_DISPLAY"
            unset WAYLAND_DISPLAY
            
            # Start the appropriate wlroots compositor
            if [ "$COMPOSITOR" = "wayfire" ]; then
                # Wayfire headless mode
                echo "🎯 Starting Wayfire in headless mode..."
                wayfire --socket="$WAYLAND_SOCKET" > "$LOG_DIR/wayfire.log" 2>&1 &
                COMPOSITOR_PID=$!
            elif [ "$COMPOSITOR" = "hyprland" ]; then
                # Hyprland headless mode using WLR_BACKENDS=headless
                echo "🎯 Starting Hyprland in headless mode..."
                
                # Set up environment for Hyprland headless mode
                export WLR_BACKENDS=headless
                export WLR_LIBINPUT_NO_DEVICES=1
                export HYPRLAND_LOG_WLR=1
                
                # Start Hyprland with headless backend
                Hyprland > "$LOG_DIR/hyprland.log" 2>&1 &
                COMPOSITOR_PID=$!
            else
                echo "⚠️  Unknown compositor: $COMPOSITOR, falling back to X11 mode"
                COMPOSITOR="x11"
            fi
            
            # Restore WAYLAND_DISPLAY for wayvnc
            export WAYLAND_DISPLAY="$ORIGINAL_WAYLAND_DISPLAY"
        else
            echo "🎯 Using existing $COMPOSITOR session - no need to start new compositor"
        fi
        
        if [ ! -z "$COMPOSITOR_PID" ]; then
            # Wait for compositor to start
            sleep 3
            
            # Check if compositor started successfully
            if ! kill -0 $COMPOSITOR_PID 2>/dev/null; then
                echo "⚠️  $COMPOSITOR compositor failed to start, falling back to X11"
                COMPOSITOR="x11"
                COMPOSITOR_PID=""
            else
                echo "✅ $COMPOSITOR started with PID $COMPOSITOR_PID"
            fi
        fi
        
    else
        # For X11-based compositors, use Xvfb
        echo "🖼️ Starting Xvfb..."
        Xvfb ":$VNC_DISPLAY" \
             -screen 0 "${WIDTH}x${HEIGHT}x${DEPTH}" \
             -ac \
             -nolisten tcp \
             > "$LOG_DIR/xvfb.log" 2>&1 &
        XVFB_PID=$!
        
        export DISPLAY=":$VNC_DISPLAY"
        
        # Wait for X server to start
        sleep 2
        
        # Check if Xvfb started successfully
        if ! kill -0 $XVFB_PID 2>/dev/null; then
            echo "❌ Failed to start Xvfb"
            exit 1
        fi
        
        echo "✅ Xvfb started with PID $XVFB_PID on display :$VNC_DISPLAY"
    fi
fi
fi
# Start wayvnc server
echo "🔗 Starting wayvnc server..."

if [ "$COMPOSITOR" = "wayfire" ] || [ "$COMPOSITOR" = "hyprland" ]; then
    # For Wayland - start wayvnc with correct syntax
    echo "📄 Starting wayvnc server..."
    
    # wayvnc syntax: wayvnc [address [port]]
    # Use 0.0.0.0 to listen on all interfaces
    wayvnc 0.0.0.0 $VNC_PORT > "$LOG_DIR/wayvnc.log" 2>&1 &
else
    # For X11, we might need x11vnc instead
    if command -v x11vnc &> /dev/null; then
        x11vnc \
            -display ":$VNC_DISPLAY" \
            -rfbport $VNC_PORT \
            -listen 0.0.0.0 \
            -forever \
            -shared \
            > "$LOG_DIR/x11vnc.log" 2>&1 &
    else
        echo "❌ x11vnc not found. Installing..."
        case $(lsb_release -si 2>/dev/null || echo "Unknown") in
            "Ubuntu"|"Debian")
                sudo apt-get install -y x11vnc
                ;;
            "Fedora"|"CentOS"|"RedHat")
                sudo dnf install -y x11vnc
                ;;
            "Arch")
                sudo pacman -S --noconfirm x11vnc
                ;;
        esac
        
        x11vnc \
            -display ":$VNC_DISPLAY" \
            -rfbport $VNC_PORT \
            -listen 0.0.0.0 \
            -forever \
            -shared \
            > "$LOG_DIR/x11vnc.log" 2>&1 &
    fi
fi

WAYVNC_PID=$!

# Wait for VNC server to start
sleep 3

# Check if VNC server started successfully
if ! kill -0 $WAYVNC_PID 2>/dev/null; then
    echo "❌ Failed to start VNC server"
    exit 1
fi

echo "✅ VNC server started with PID $WAYVNC_PID"
echo "🌐 VNC server listening on port $VNC_PORT"
echo "📝 Logs available in $LOG_DIR/"

# Keep the script running
echo "🔄 VNC server is running. Press Ctrl+C to stop."
wait $WAYVNC_PID
