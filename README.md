# YesVNC - Self-Hosted VNC Web Client

A production-ready, self-hosted VNC web client based on noVNC that supports wlroots compositors (Wayfire/Hyprland) via wayvnc, with automatic dependency installation and unified startup.

## Features

- **Wayland Support**: Native wlroots compositor support via wayvnc
- **Existing Session**: Connects to your current Hyprland/Wayfire session
- **Web Interface**: Modern, responsive web client based on noVNC
- **Multi-Platform**: Supports Ubuntu, Debian, Fedora, and Arch Linux
- **One-Click Setup**: Single script handles installation and startup
- **Production Ready**: Automatic dependency management and error handling

## Quick Start

**Single Command Setup & Launch:**
```bash
./run.sh
```

That's it! This will:
1. Check and install all dependencies automatically
2. Start the VNC server (connects to your existing Hyprland session)
3. Start the web client with WebSocket proxy
4. Display connection information

**Manual Setup (if needed):**
```bash
# Install dependencies only
./install-deps.sh

# Start components separately
./start-vnc-server.sh    # VNC server only
./start-web-client.sh    # Web client only
```

## Directory Structure

```
yesVNC/
├── README.md                 # This file
├── run.sh                   # Production runner (install + start everything)
├── install-deps.sh          # Dependency installation script
├── start-vnc-server.sh      # VNC server startup script
├── start-web-client.sh      # Web client startup script
├── config/                  # Configuration files
│   ├── vnc-config.json     # VNC server configuration
│   └── web-config.json     # Web client configuration
├── web/                     # Web client files
│   ├── index.html          # Main web interface
│   ├── app.js              # Application logic
│   └── style.css           # Styling
├── noVNC/                   # noVNC library (auto-downloaded)
└── logs/                    # Runtime logs
```

## Connection Information

After running `./run.sh`, you can access your desktop via:

- **Web Interface**: http://localhost:8080
- **Direct VNC**: localhost:5903 (for VNC clients)
- **WebSocket Proxy**: localhost:6080

## Configuration

### VNC Server (`config/vnc-config.json`)

```json
{
    "display": 3,
    "port": 5903,
    "headless": true,
    "compositor": "hyprland",
    "width": 1920,
    "height": 1080,
    "depth": 24
}
```

### Web Client (`config/web-config.json`)

```json
{
    "webPort": 8080,
    "websocketPort": 6080,
    "vncHost": "localhost",
    "vncPort": 5903,
    "title": "YesVNC - Remote Desktop",
    "autoConnect": false,
    "encryption": false,
    "resizeSession": true,
    "showDotCursor": false,
    "logging": "warn"
}
```
- VNC server settings (port, display, etc.)
- Web client settings (websocket proxy, authentication, etc.)
- SSH tunnel settings (ports, hosts, etc.)

## Requirements

- Linux system with Wayland support
- Node.js (for websockify proxy)
- Python 3 (for noVNC)
- wayvnc
- Xvfb (for headless X11 displays)
- Hyprland or other wlroots compatible Wayland compositor
- SSH client

## License

MIT License
