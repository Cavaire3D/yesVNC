#!/bin/bash

# Load and validate configuration from unified config.json
# This script should be sourced by other scripts to access config values

# Default values
declare -A CONFIG

# Create default config if it doesn't exist
CONFIG_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/config.json"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "📝 Creating default configuration..."
    cat > "$CONFIG_FILE" << 'EOF'
{
    "server": {
        "display": 3,
        "port": 8081,
        "headless": true,
        "compositor": "hyprland",
        "resolution": {
            "width": 1920,
            "height": 1080,
            "depth": 24
        },
        "vnc": {
            "host": "localhost",
            "port": 5903
        }
    },
    "web": {
        "port": 8080,
        "websocketPort": 6080,
        "title": "YesVNC - Remote Desktop",
        "autoConnect": false,
        "encryption": false,
        "resizeSession": true,
        "showDotCursor": false,
        "logging": "warn"
    }
}
EOF
fi

# Function to get config value with default
get_config() {
    local path="$1"
    local default="$2"
    
    # Try to get the value using jq
    local value=$(jq -r ".${path} | if type == \"string\" then . else tostring end" "$CONFIG_FILE" 2>/dev/null)
    
    # If jq failed or returned null, return the default
    if [ $? -ne 0 ] || [ "$value" = "null" ] || [ -z "$value" ]; then
        echo "$default"
    else
        echo "$value"
    fi
}

export -f get_config
