#!/bin/bash

# YesVNC Dependency Installation Script
# Installs all required dependencies for the VNC web client

set -e

echo "🚀 Installing YesVNC dependencies..."

# Detect package manager
if command -v apt-get &> /dev/null; then
    PKG_MANAGER="apt"
elif command -v dnf &> /dev/null; then
    PKG_MANAGER="dnf"
elif command -v pacman &> /dev/null; then
    PKG_MANAGER="pacman"
else
    echo "❌ Unsupported package manager. Please install dependencies manually."
    exit 1
fi

echo "📦 Detected package manager: $PKG_MANAGER"

# Install system dependencies
echo "📥 Installing system dependencies..."

case $PKG_MANAGER in
    "apt")
        sudo apt-get update
        sudo apt-get install -y \
            git \
            python3 \
            python3-pip \
            nodejs \
            npm \
            xvfb \
            wayfire \
            wayvnc \
            openssh-client \
            curl \
            wget \
            build-essential
        ;;
    "dnf")
        sudo dnf install -y \
            git \
            python3 \
            python3-pip \
            nodejs \
            npm \
            xorg-x11-server-Xvfb \
            wayfire \
            wayvnc \
            openssh-clients \
            curl \
            wget \
            gcc \
            gcc-c++ \
            make
        ;;
    "pacman")
        sudo pacman -Sy --noconfirm \
            git \
            python \
            python-pip \
            nodejs \
            npm \
            xorg-server-xvfb \
            hyprland \
            wayvnc \
            openssh \
            curl \
            wget \
            base-devel \
            python-pipx
        ;;
esac

# Install Python dependencies
echo "🐍 Installing Python dependencies..."
pipx install numpy

# Build and install websockify from source
echo "🔧 Building websockify from source..."
if [ ! -d "websockify" ]; then
    git clone https://github.com/novnc/websockify.git
fi
cd websockify
sudo python3 setup.py install
cd ..

# Install Node.js dependencies globally
echo "📦 Installing Node.js dependencies..."
sudo npm install -g ws websocket http-server

# Clone and setup noVNC
echo "🖥️ Setting up noVNC..."
if [ ! -d "noVNC" ]; then
    git clone https://github.com/novnc/noVNC.git
    cd noVNC
    # Use a stable version
    git checkout v1.4.0
    cd ..
else
    echo "noVNC already exists, skipping clone..."
fi

# Make scripts executable
echo "🔧 Setting up permissions..."
chmod +x *.sh

# Create log directory if it doesn't exist
mkdir -p logs

echo "✅ Installation complete!"
echo ""
echo "Next steps:"
echo "1. Configure your settings in config/ directory"
echo "2. Run ./start-vnc-server.sh to start the VNC server"
echo "3. Run ./start-web-client.sh to start the web client"
echo ""
echo "For remote connections, use ./connect-ssh.sh <host> <username>"

# Install wayvnc if not already available
echo "🔧 Installing wayvnc..."
if ! command -v wayvnc &> /dev/null; then
    if command -v pacman &> /dev/null; then
        echo "📦 Installing wayvnc on Arch Linux..."
        # Try AUR helpers first
        if command -v yay &> /dev/null; then
            yay -S --noconfirm wayvnc
        elif command -v paru &> /dev/null; then
            paru -S --noconfirm wayvnc
        else
            echo "⚠️  No AUR helper found. Installing manually from AUR..."
            # Install dependencies for building
            sudo pacman -S --needed --noconfirm base-devel git
            # Clone and build wayvnc from AUR
            cd /tmp
            git clone https://aur.archlinux.org/wayvnc.git
            cd wayvnc
            makepkg -si --noconfirm
            cd ..
            rm -rf wayvnc
            cd "$OLDPWD"
        fi
    elif command -v apt-get &> /dev/null; then
        echo "📦 Installing wayvnc on Debian/Ubuntu..."
        if apt-cache show wayvnc &> /dev/null; then
            sudo apt-get update
            sudo apt-get install -y wayvnc
        else
            echo "⚠️  Building wayvnc from source..."
            sudo apt-get update
            sudo apt-get install -y build-essential meson ninja-build pkg-config \
                libwayland-dev libxkbcommon-dev libpixman-1-dev libaml-dev \
                libneatvnc-dev libdrm-dev git
            cd /tmp
            git clone https://github.com/any1/wayvnc.git
            cd wayvnc
            meson build
            ninja -C build
            sudo ninja -C build install
            cd ..
            rm -rf wayvnc
            cd "$OLDPWD"
        fi
    elif command -v dnf &> /dev/null; then
        echo "📦 Installing wayvnc on Fedora/RHEL..."
        if dnf list wayvnc &> /dev/null; then
            sudo dnf install -y wayvnc
        else
            echo "⚠️  Building wayvnc from source..."
            sudo dnf install -y gcc meson ninja-build pkgconfig wayland-devel \
                libxkbcommon-devel pixman-devel libdrm-devel git
            cd /tmp
            git clone https://github.com/any1/wayvnc.git
            cd wayvnc
            meson build
            ninja -C build
            sudo ninja -C build install
            cd ..
            rm -rf wayvnc
            cd "$OLDPWD"
        fi
    fi
else
    echo "✅ wayvnc is already installed"
fi

echo "✅ YesVNC dependencies installation completed!"
echo "📋 Next steps:"
echo "  1. Run ./start-yesVNC.sh to start both VNC server and web client"
echo "  2. Open http://localhost:8080 in your browser"
echo "  3. Or run components separately:"
echo "     - ./start-vnc-server.sh (VNC server only)"
echo "     - ./start-web-client.sh (web client only)"
