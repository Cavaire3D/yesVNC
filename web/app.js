/**
 * YesVNC Web Client Application
 * Handles VNC connection, UI interactions, and noVNC integration
 */

class YesVNCClient {
    constructor() {
        this.rfb = null;
        this.connected = false;
        this.connecting = false;
        this.config = {};
        
        this.initializeElements();
        this.bindEvents();
        this.loadConfiguration();
        this.updateStatus('disconnected', 'Disconnected');
    }

    initializeElements() {
        // Status elements
        this.statusIndicator = document.getElementById('statusIndicator');
        this.statusText = document.getElementById('statusText');
        
        // Form elements
        this.connectionForm = document.getElementById('connectionForm');
        this.hostInput = document.getElementById('host');
        this.portInput = document.getElementById('port');
        this.passwordInput = document.getElementById('password');
        this.encryptInput = document.getElementById('encrypt');
        this.resizeInput = document.getElementById('resize');
        this.viewOnlyInput = document.getElementById('viewOnly');
        
        // Button elements
        this.connectBtn = document.getElementById('connectBtn');
        this.disconnectBtn = document.getElementById('disconnectBtn');
        this.fullscreenBtn = document.getElementById('fullscreenBtn');
        this.ctrlAltDelBtn = document.getElementById('ctrlAltDelBtn');
        this.screenshotBtn = document.getElementById('screenshotBtn');
        this.showPanelBtn = document.getElementById('showPanelBtn');
        
        // Container elements
        this.connectionPanel = document.getElementById('connectionPanel');
        this.vncContainer = document.getElementById('vncContainer');
        this.vncScreen = document.getElementById('vncScreen');
        this.loadingOverlay = document.getElementById('loadingOverlay');
        this.connectionInfo = document.getElementById('connectionInfo');
        
        // Notification elements
        this.notification = document.getElementById('notification');
        this.notificationText = document.getElementById('notificationText');
        this.notificationClose = document.getElementById('notificationClose');
    }

    bindEvents() {
        // Form submission
        this.connectionForm.addEventListener('submit', (e) => {
            e.preventDefault();
            this.connect();
        });

        // Button events
        this.disconnectBtn.addEventListener('click', () => this.disconnect());
        this.fullscreenBtn.addEventListener('click', () => this.toggleFullscreen());
        this.ctrlAltDelBtn.addEventListener('click', () => this.sendCtrlAltDel());
        this.screenshotBtn.addEventListener('click', () => this.takeScreenshot());
        this.showPanelBtn.addEventListener('click', () => this.togglePanel());
        
        // Notification close
        this.notificationClose.addEventListener('click', () => this.hideNotification());
        
        // Keyboard shortcuts
        document.addEventListener('keydown', (e) => {
            if (e.ctrlKey && e.altKey && e.key === 'Delete') {
                e.preventDefault();
                this.sendCtrlAltDel();
            }
            if (e.key === 'F11') {
                e.preventDefault();
                this.toggleFullscreen();
            }
            if (e.key === 'Escape' && this.isFullscreen()) {
                this.exitFullscreen();
            }
        });

        // Window resize
        window.addEventListener('resize', () => {
            if (this.rfb && this.resizeInput.checked) {
                this.resizeSession();
            }
        });
    }

    async loadConfiguration() {
        try {
            const response = await fetch('../config/web-config.json');
            if (response.ok) {
                this.config = await response.json();
                this.applyConfiguration();
            }
        } catch (error) {
            console.warn('Could not load configuration:', error);
            this.config = this.getDefaultConfig();
        }
    }

    getDefaultConfig() {
        return {
            webPort: 8080,
            websocketPort: 6080,
            vncHost: 'localhost',
            vncPort: 5901,
            title: 'YesVNC - Remote Desktop',
            autoConnect: false,
            encryption: false,
            resizeSession: true,
            showDotCursor: false,
            logging: 'warn'
        };
    }

    applyConfiguration() {
        this.hostInput.value = this.config.vncHost || 'localhost';
        this.portInput.value = this.config.websocketPort || 6080;
        this.encryptInput.checked = this.config.encryption || false;
        this.resizeInput.checked = this.config.resizeSession !== false;
        
        document.title = this.config.title || 'YesVNC - Remote Desktop';
        
        if (this.config.autoConnect) {
            setTimeout(() => this.connect(), 1000);
        }
    }

    updateStatus(state, message) {
        this.statusIndicator.className = `status-indicator ${state}`;
        this.statusText.textContent = message;
        
        switch (state) {
            case 'connected':
                this.connectBtn.disabled = true;
                this.disconnectBtn.disabled = false;
                this.fullscreenBtn.disabled = false;
                this.ctrlAltDelBtn.disabled = false;
                this.screenshotBtn.disabled = false;
                break;
            case 'connecting':
                this.connectBtn.disabled = true;
                this.disconnectBtn.disabled = false;
                break;
            case 'disconnected':
            default:
                this.connectBtn.disabled = false;
                this.disconnectBtn.disabled = true;
                this.fullscreenBtn.disabled = true;
                this.ctrlAltDelBtn.disabled = true;
                this.screenshotBtn.disabled = true;
                break;
        }
    }

    async connect() {
        if (this.connecting || this.connected) {
            return;
        }

        const host = this.hostInput.value.trim();
        const port = parseInt(this.portInput.value);
        const password = this.passwordInput.value;
        const encrypt = this.encryptInput.checked;

        if (!host || !port) {
            this.showNotification('Please enter valid host and port', 'error');
            return;
        }

        this.connecting = true;
        this.updateStatus('connecting', 'Connecting...');
        this.showLoading('Connecting to remote desktop...');

        try {
            // Check if noVNC is available
            if (typeof RFB === 'undefined') {
                await this.loadNoVNC();
            }

            // Build WebSocket URL
            const protocol = encrypt ? 'wss:' : 'ws:';
            const wsUrl = `${protocol}//${host}:${port}/websockify`;

            // Create RFB connection
            this.rfb = new RFB(this.vncScreen, wsUrl, {
                credentials: { password: password },
                repeaterID: '',
                shared: !this.viewOnlyInput.checked,
                wsProtocols: ['binary'],
                showDotCursor: this.config.showDotCursor || false
            });

            // Set up event handlers
            this.rfb.addEventListener('connect', this.onConnect.bind(this));
            this.rfb.addEventListener('disconnect', this.onDisconnect.bind(this));
            this.rfb.addEventListener('credentialsrequired', this.onCredentialsRequired.bind(this));
            this.rfb.addEventListener('securityfailure', this.onSecurityFailure.bind(this));

            // Set view only mode
            this.rfb.viewOnly = this.viewOnlyInput.checked;

            // Set scaling mode
            this.rfb.scaleViewport = true;
            this.rfb.resizeSession = this.resizeInput.checked;

        } catch (error) {
            console.error('Connection error:', error);
            this.onConnectionError(error);
        }
    }

    async loadNoVNC() {
        return new Promise((resolve, reject) => {
            // Try to load noVNC from the noVNC directory
            const script = document.createElement('script');
            script.src = '../noVNC/app/ui.js';
            script.onload = () => {
                // Also load the RFB module
                const rfbScript = document.createElement('script');
                rfbScript.src = '../noVNC/core/rfb.js';
                rfbScript.onload = resolve;
                rfbScript.onerror = () => {
                    // Fallback: try to use embedded noVNC via websockify
                    this.showNotification('noVNC not found locally, using websockify interface', 'warning');
                    resolve();
                };
                document.head.appendChild(rfbScript);
            };
            script.onerror = () => {
                // Fallback: redirect to websockify's noVNC interface
                const host = this.hostInput.value.trim();
                const port = parseInt(this.portInput.value);
                const fallbackUrl = `http://${host}:${port}/vnc.html?host=${host}&port=${port}&autoconnect=1`;
                window.location.href = fallbackUrl;
                reject(new Error('Redirecting to websockify interface'));
            };
            document.head.appendChild(script);
        });
    }

    onConnect(e) {
        this.connected = true;
        this.connecting = false;
        this.hideLoading();
        this.updateStatus('connected', 'Connected');
        this.showNotification('Successfully connected to remote desktop', 'success');
        
        // Hide connection panel and show VNC container
        this.connectionPanel.style.display = 'none';
        this.vncContainer.style.display = 'flex';
        
        // Update connection info
        const host = this.hostInput.value;
        const port = this.portInput.value;
        this.connectionInfo.textContent = `Connected to ${host}:${port}`;
        
        // Resize session if enabled
        if (this.resizeInput.checked) {
            setTimeout(() => this.resizeSession(), 1000);
        }
    }

    onDisconnect(e) {
        this.connected = false;
        this.connecting = false;
        this.hideLoading();
        
        const reason = e.detail.clean ? 'Connection closed' : 'Connection lost';
        this.updateStatus('disconnected', reason);
        
        // Show connection panel and hide VNC container
        this.connectionPanel.style.display = 'block';
        this.vncContainer.style.display = 'none';
        
        if (!e.detail.clean) {
            this.showNotification('Connection lost unexpectedly', 'error');
        }
        
        this.rfb = null;
    }

    onCredentialsRequired(e) {
        this.hideLoading();
        this.showNotification('Password required for this connection', 'warning');
        this.passwordInput.focus();
    }

    onSecurityFailure(e) {
        this.hideLoading();
        this.updateStatus('disconnected', 'Security failure');
        this.showNotification(`Security failure: ${e.detail.reason}`, 'error');
    }

    onConnectionError(error) {
        this.connecting = false;
        this.hideLoading();
        this.updateStatus('disconnected', 'Connection failed');
        this.showNotification(`Connection failed: ${error.message}`, 'error');
    }

    disconnect() {
        if (this.rfb) {
            this.rfb.disconnect();
        }
    }

    toggleFullscreen() {
        if (this.isFullscreen()) {
            this.exitFullscreen();
        } else {
            this.enterFullscreen();
        }
    }

    enterFullscreen() {
        this.vncContainer.classList.add('fullscreen');
        if (this.vncContainer.requestFullscreen) {
            this.vncContainer.requestFullscreen();
        } else if (this.vncContainer.webkitRequestFullscreen) {
            this.vncContainer.webkitRequestFullscreen();
        } else if (this.vncContainer.msRequestFullscreen) {
            this.vncContainer.msRequestFullscreen();
        }
    }

    exitFullscreen() {
        this.vncContainer.classList.remove('fullscreen');
        if (document.exitFullscreen) {
            document.exitFullscreen();
        } else if (document.webkitExitFullscreen) {
            document.webkitExitFullscreen();
        } else if (document.msExitFullscreen) {
            document.msExitFullscreen();
        }
    }

    isFullscreen() {
        return document.fullscreenElement === this.vncContainer ||
               document.webkitFullscreenElement === this.vncContainer ||
               document.msFullscreenElement === this.vncContainer;
    }

    sendCtrlAltDel() {
        if (this.rfb && this.connected) {
            this.rfb.sendCtrlAltDel();
            this.showNotification('Sent Ctrl+Alt+Del', 'success');
        }
    }

    takeScreenshot() {
        if (this.rfb && this.connected) {
            // This is a placeholder - actual screenshot functionality would need
            // to be implemented based on the specific noVNC version
            this.showNotification('Screenshot feature not yet implemented', 'warning');
        }
    }

    resizeSession() {
        if (this.rfb && this.connected && this.resizeInput.checked) {
            const container = this.vncScreen;
            const width = container.clientWidth;
            const height = container.clientHeight;
            
            try {
                this.rfb.resizeSession(width, height);
            } catch (error) {
                console.warn('Could not resize session:', error);
            }
        }
    }

    togglePanel() {
        if (this.connectionPanel.style.display === 'none') {
            this.connectionPanel.style.display = 'block';
        } else {
            this.connectionPanel.style.display = 'none';
        }
    }

    showLoading(message = 'Loading...') {
        document.getElementById('loadingText').textContent = message;
        this.loadingOverlay.style.display = 'flex';
    }

    hideLoading() {
        this.loadingOverlay.style.display = 'none';
    }

    showNotification(message, type = 'info') {
        this.notificationText.textContent = message;
        this.notification.className = `notification ${type}`;
        this.notification.style.display = 'block';
        
        // Auto-hide after 5 seconds
        setTimeout(() => this.hideNotification(), 5000);
    }

    hideNotification() {
        this.notification.style.display = 'none';
    }
}

// Initialize the application when the DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    window.yesVNC = new YesVNCClient();
});

// Handle page visibility changes
document.addEventListener('visibilitychange', () => {
    if (window.yesVNC && window.yesVNC.rfb) {
        if (document.hidden) {
            // Pause updates when page is hidden
            console.log('Page hidden, pausing VNC updates');
        } else {
            // Resume updates when page is visible
            console.log('Page visible, resuming VNC updates');
        }
    }
});
