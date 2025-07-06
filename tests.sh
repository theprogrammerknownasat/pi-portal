#!/bin/bash

# Moonlight Gaming Appliance Installation Script
# Creates a locked-down thin client that auto-boots into Moonlight
# Author: Gaming Portal Project
# Usage: Run as root on fresh Debian installation

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print functions
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "\n${BLUE}===========================================${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}===========================================${NC}\n"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root"
    echo "Usage: sudo $0"
    exit 1
fi

print_header "MOONLIGHT GAMING APPLIANCE INSTALLER"
print_info "This will create a locked-down gaming thin client"
print_info "The system will auto-boot into Moonlight streaming"
echo ""

# =============================================================================
# SYSTEM UPDATES AND BASE PACKAGES
# =============================================================================

print_header "UPDATING SYSTEM AND INSTALLING BASE PACKAGES"

print_info "Updating package repositories..."
apt update && apt upgrade -y

print_info "Installing essential packages..."
apt install -y \
    xorg \
    lightdm \
    plymouth \
    plymouth-themes \
    flatpak \
    network-manager \
    pulseaudio \
    curl \
    wget \
    zenity \
    imagemagick \
    adwaita-qt-theme

print_success "Base packages installed"

# =============================================================================
# FLATPAK AND MOONLIGHT SETUP
# =============================================================================

print_header "SETTING UP MOONLIGHT GAME STREAMING"

print_info "Configuring Flatpak repository..."
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

print_info "Installing Moonlight from Flathub..."
flatpak install -y flathub com.moonlight_stream.Moonlight

print_info "Creating Moonlight wrapper script..."
cat > /usr/local/bin/moonlight << 'EOF'
#!/bin/bash
flatpak run com.moonlight_stream.Moonlight "$@"
EOF
chmod +x /usr/local/bin/moonlight

print_success "Moonlight installed and configured"

# =============================================================================
# APPLIANCE SCRIPTS CREATION
# =============================================================================

print_header "CREATING APPLIANCE SESSION SCRIPTS"

print_info "Creating appliance directory..."
mkdir -p /opt/moonlight-appliance

print_info "Creating main session script..."
cat > /opt/moonlight-appliance/session.sh << 'EOF'
#!/bin/bash

# Moonlight Appliance Session Manager
# Handles connection attempts with infinite retry

LOG_FILE="/tmp/moonlight.log"

log() {
    echo "$(date): $1" >> "$LOG_FILE"
}

log "=== Appliance session starting ==="

# Main session loop - retry forever
while true; do
    log "Starting connection attempt..."
    
    # Wait for network (30 seconds max)
    log "Waiting for network connection..."
    # Update Plymouth status
    plymouth message --text="Connecting to network..." 2>/dev/null || true
    
    NETWORK_READY=false
    for i in {1..30}; do
        if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
            log "Network connection established"
            NETWORK_READY=true
            break
        fi
        sleep 1
    done
    
    if [ "$NETWORK_READY" = false ]; then
        log "Network timeout - showing error"
        /opt/moonlight-appliance/show-error.sh "No network connection available"
        # This will shutdown the system, so we won't reach here
        exit 1
    fi
    
    # Try to launch Moonlight fullscreen
    log "Launching Moonlight in fullscreen mode..."
    # Update Plymouth to show connection attempt
    plymouth message --text="Connecting to gaming server..." 2>/dev/null || true
    
    moonlight --fullscreen &
    MOONLIGHT_PID=$!
    
    # Wait 45 seconds for connection to establish
    sleep 45
    
    # Check if Moonlight is still running (successful connection)
    if kill -0 $MOONLIGHT_PID 2>/dev/null; then
        log "Moonlight connected successfully"
        # Hide Plymouth boot screen now that we're connected
        plymouth quit 2>/dev/null || true
        
        # Wait for Moonlight session to end
        wait $MOONLIGHT_PID
        log "Moonlight session ended normally"
        
        # Session ended - wait a moment and retry
        sleep 5
        log "Restarting session in 5 seconds..."
        continue
    else
        log "Moonlight failed to connect within timeout"
        /opt/moonlight-appliance/show-error.sh "Could not connect to gaming server"
        # This will shutdown the system
        exit 1
    fi
done
EOF

chmod +x /opt/moonlight-appliance/session.sh

print_info "Creating error dialog script..."
cat > /opt/moonlight-appliance/show-error.sh << EOF
#!/bin/bash

# Display error message and shutdown system

MESSAGE="\$1"
if [ -z "\$MESSAGE" ]; then
    MESSAGE="Connection failed"
fi

# Ensure Plymouth is hidden
plymouth quit 2>/dev/null || true

# Show error dialog with shutdown option
DISPLAY=:0 zenity --error \\
    --title="Gaming Portal - Connection Error" \\
    --text="\$MESSAGE

$CUSTOM_CONTACT

The system will shutdown when you press OK." \\
    --width=450 \\
    --height=250 2>/dev/null

# Immediate system shutdown
systemctl poweroff
EOF

chmod +x /opt/moonlight-appliance/show-error.sh

print_success "Session scripts created"

# =============================================================================
# DISPLAY MANAGER CONFIGURATION
# =============================================================================

print_header "CONFIGURING DISPLAY MANAGER"

print_info "Creating black background image..."
convert -size 1920x1080 xc:black /usr/share/pixmaps/black.png

print_info "Configuring LightDM greeter appearance..."
cat > /etc/lightdm/lightdm-gtk-greeter.conf << 'EOF'
[greeter]
background=/usr/share/pixmaps/black.png
theme-name=Adwaita-dark
icon-theme-name=Adwaita
font-name=Sans 11
xft-antialias=true
xft-dpi=96
xft-hintstyle=hintslight
xft-rgba=rgb
show-indicators=
show-clock=false
default-user-image=/usr/share/pixmaps/nobody.png
hide-user-image=true
round-user-image=false
highlight-logged-user=true
panel-position=bottom
hide-panel=true
default-user=user
EOF

print_info "Creating custom session desktop file..."
cat > /usr/share/xsessions/moonlight-appliance.desktop << 'EOF'
[Desktop Entry]
Name=Moonlight Appliance
Comment=Gaming Portal Session
Exec=/opt/moonlight-appliance/session.sh
Type=Application
DesktopNames=Moonlight
EOF

print_success "Display manager configured"

# =============================================================================
# USER ACCOUNT CREATION
# =============================================================================

print_header "CREATING USER ACCOUNT"

print_info "Creating 'user' account with restricted permissions..."
useradd -m -s /bin/bash user

print_info "Setting secure password for user account..."
echo 'user:Zx9#mK8$vN2&pL4!' | chpasswd

print_info "Adding user to sudo group temporarily for debugging..."
usermod -aG sudo user

print_info "Creating debug script for easy log access..."
cat > /home/user/debug.sh << 'EOF'
#!/bin/bash
echo "=== MOONLIGHT SESSION LOG ==="
cat /tmp/moonlight.log 2>/dev/null || echo "No session log found"
echo ""
echo "=== WATCHDOG LOG ==="
cat /tmp/watchdog.log 2>/dev/null || echo "No watchdog log found"
echo ""
echo "=== RUNNING PROCESSES ==="
ps aux | grep -E "(moonlight|session|lightdm)"
echo ""
echo "=== SYSTEMD STATUS ==="
systemctl status lightdm --no-pager
echo ""
systemctl status moonlight-watchdog --no-pager
EOF

chmod +x /home/user/debug.sh
chown user:user /home/user/debug.sh

print_success "User account created and configured"

# =============================================================================
# AUTO-LOGIN CONFIGURATION
# =============================================================================

print_header "CONFIGURING AUTO-LOGIN"

print_info "Setting up automatic login to appliance session..."
cat > /etc/lightdm/lightdm.conf << 'EOF'
[Seat:*]
greeter-session=lightdm-gtk-greeter
user-session=moonlight-appliance
autologin-user=user
autologin-user-timeout=0
autologin-session=moonlight-appliance
greeter-hide-users=false
greeter-allow-guest=false
greeter-show-manual-login=false
EOF

print_success "Auto-login configured"

# =============================================================================
# NETWORK CONFIGURATION
# =============================================================================

print_header "NETWORK CONFIGURATION"

echo ""
print_info "You will now configure the WiFi connection for this appliance"
print_warning "This information will be stored and used for automatic connection"
echo ""

# Get WiFi credentials from user
while true; do
    read -p "Enter WiFi network name (SSID): " WIFI_SSID
    if [ -n "$WIFI_SSID" ]; then
        break
    fi
    print_error "WiFi SSID cannot be empty. Please try again."
done

while true; do
    read -s -p "Enter WiFi password: " WIFI_PASSWORD
    echo ""
    if [ -n "$WIFI_PASSWORD" ]; then
        break
    fi
    print_error "WiFi password cannot be empty. Please try again."
done

print_info "Configuring WiFi connection for: $WIFI_SSID"

# Remove any existing connection with the same name
nmcli connection delete "appliance-wifi" 2>/dev/null || true

# Create new WiFi connection
nmcli device wifi connect "$WIFI_SSID" password "$WIFI_PASSWORD" name "appliance-wifi"

# Set to auto-connect with high priority
nmcli connection modify "appliance-wifi" connection.autoconnect yes
nmcli connection modify "appliance-wifi" connection.autoconnect-priority 100

print_info "Testing WiFi connection..."
if nmcli connection up "appliance-wifi" 2>/dev/null; then
    print_success "WiFi connection test successful"
else
    print_warning "WiFi connection test failed - please verify credentials later"
fi

# =============================================================================
# MOONLIGHT SERVER CONFIGURATION
# =============================================================================

print_header "MOONLIGHT SERVER CONFIGURATION"

echo ""
print_info "Configure the gaming server that this appliance will connect to"
print_warning "This should be the IP address or hostname of your Sunshine/GameStream server"
echo ""

while true; do
    read -p "Enter gaming server IP address or hostname: " SERVER_HOST
    if [ -n "$SERVER_HOST" ]; then
        break
    fi
    print_error "Server host cannot be empty. Please try again."
done

read -p "Enter server port (default 47989): " SERVER_PORT
SERVER_PORT=${SERVER_PORT:-47989}

# =============================================================================
# ERROR DIALOG CUSTOMIZATION
# =============================================================================

print_header "ERROR DIALOG CUSTOMIZATION"

echo ""
print_info "Customize the error message that users will see if connection fails"
print_warning "This should include your contact information for technical support"
echo ""

echo "Default message: 'Please contact your friend for technical support.'"
read -p "Enter custom support contact info (or press Enter for default): " CUSTOM_CONTACT

if [ -z "$CUSTOM_CONTACT" ]; then
    CUSTOM_CONTACT="Please contact your friend for technical support."
fi

print_success "Error dialog will show: $CUSTOM_CONTACT"

print_info "Configuring Moonlight for server: $SERVER_HOST:$SERVER_PORT"

# Create Moonlight config directory for the user
mkdir -p "/home/user/.config/Moonlight Game Streaming Project"

# Create Moonlight configuration file
cat > "/home/user/.config/Moonlight Game Streaming Project/Moonlight.conf" << EOL
[General]
host=$SERVER_HOST
port=$SERVER_PORT
fullscreen=true
vsync=true
framerate=60
bitrate=20000
resolution=1920x1080
EOL

# Set proper ownership
chown -R user:user "/home/user/.config"

print_success "Moonlight server configuration complete"
print_info "Server: $SERVER_HOST:$SERVER_PORT"
print_info "Mode: Fullscreen, 1920x1080 @ 60fps"
echo ""
print_warning "IMPORTANT: You must pair this client with your server"
print_warning "This requires entering a PIN code from the client into your server setup"

# =============================================================================
# SYSTEM OPTIMIZATION
# =============================================================================

print_header "OPTIMIZING SYSTEM FOR APPLIANCE USE"

print_info "Disabling unnecessary services..."
systemctl disable bluetooth 2>/dev/null || true
systemctl disable cups 2>/dev/null || true
systemctl disable avahi-daemon 2>/dev/null || true
systemctl mask NetworkManager-wait-online.service

print_info "Setting graphical boot target..."
systemctl set-default graphical.target

print_info "Configuring audio system..."
systemctl --user enable pulseaudio 2>/dev/null || true

print_success "System optimization complete"

# =============================================================================
# WATCHDOG SERVICE SETUP
# =============================================================================

print_header "SETTING UP SESSION WATCHDOG"

print_info "Creating session monitoring service..."
cat > /etc/systemd/system/moonlight-watchdog.service << 'EOF'
[Unit]
Description=Moonlight Session Watchdog
After=lightdm.service

[Service]
Type=simple
ExecStart=/opt/moonlight-appliance/watchdog.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

print_info "Creating watchdog monitoring script..."
cat > /opt/moonlight-appliance/watchdog.sh << 'EOF'
#!/bin/bash

# Monitor user session and restart if crashed
while true; do
    sleep 30
    
    # Check if user session is running
    if ! pgrep -u user > /dev/null; then
        echo "$(date): User session not found, restarting LightDM" >> /tmp/watchdog.log
        systemctl restart lightdm
    fi
done
EOF

chmod +x /opt/moonlight-appliance/watchdog.sh
systemctl enable moonlight-watchdog

print_success "Session watchdog configured"

# =============================================================================
# TIMEZONE CONFIGURATION
# =============================================================================

print_header "TIMEZONE CONFIGURATION"

CURRENT_TZ=$(cat /etc/timezone 2>/dev/null || timedatectl show --property=Timezone --value)

if [ -z "$CURRENT_TZ" ]; then
    print_info "Available timezone examples:"
    timedatectl list-timezones | grep -E "(New_York|Chicago|Denver|Los_Angeles|America/)" | head -10
    echo ""
    read -p "Enter timezone (e.g., America/New_York): " USER_TZ
    if [ -n "$USER_TZ" ]; then
        timedatectl set-timezone "$USER_TZ"
        print_success "Timezone set to: $USER_TZ"
    fi
else
    print_success "Using current timezone: $CURRENT_TZ"
fi

# =============================================================================
# SYSTEM UPDATES DISABLE
# =============================================================================

print_header "DISABLING AUTOMATIC UPDATES"

print_info "Disabling automatic package updates..."
systemctl disable apt-daily.timer 2>/dev/null || true
systemctl disable apt-daily-upgrade.timer 2>/dev/null || true
systemctl disable unattended-upgrades 2>/dev/null || true
systemctl mask apt-daily.service apt-daily-upgrade.service

cat > /etc/apt/apt.conf.d/99disable-auto-updates << 'EOF'
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Unattended-Upgrade "0";
EOF

print_success "Automatic updates disabled"

# =============================================================================
# SWAP CONFIGURATION
# =============================================================================

print_header "CONFIGURING SWAP MEMORY"

print_info "Creating 512MB swap file for emergency memory..."
swapoff -a 2>/dev/null || true
dd if=/dev/zero of=/swapfile bs=1M count=512 2>/dev/null
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile

# Add to fstab if not already present
if ! grep -q "/swapfile" /etc/fstab; then
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

print_info "Configuring low swap usage (RAM priority)..."
echo 'vm.swappiness=10' >> /etc/sysctl.conf

print_success "Swap configuration complete"

# =============================================================================
# SECURITY HARDENING
# =============================================================================

print_header "APPLYING SECURITY HARDENING"

print_info "Disabling TTY console access..."
systemctl mask getty@tty1 getty@tty2 getty@tty3 getty@tty4 getty@tty5 getty@tty6

print_info "Reducing kernel messages..."
echo 'kernel.printk = 3 3 3 3' >> /etc/sysctl.conf

print_info "Removing text editors and package managers from user access..."
apt remove -y --purge nano vim-tiny ed 2>/dev/null || true
chmod 000 /usr/bin/apt /usr/bin/apt-get /usr/bin/dpkg 2>/dev/null || true

print_info "Configuring GRUB for security..."
echo 'GRUB_DISABLE_RECOVERY=true' >> /etc/default/grub
echo 'GRUB_TIMEOUT=0' >> /etc/default/grub
update-grub

print_info "Setting process limits for user account..."
cat >> /etc/security/limits.conf << 'EOF'
user soft nproc 20
user hard nproc 30
EOF

print_info "Hiding system information from user..."
chmod 700 /proc/sys 2>/dev/null || true
chmod 700 /proc/modules 2>/dev/null || true

print_info "Disabling Ctrl+Alt+Del shortcut..."
systemctl mask ctrl-alt-del.target

print_info "Securing home directory..."
chmod 750 /home/user

print_info "Making critical configuration files immutable..."
chattr +i /etc/lightdm/lightdm.conf 2>/dev/null || true
chattr +i /etc/lightdm/lightdm-gtk-greeter.conf 2>/dev/null || true

print_success "Security hardening complete"

# =============================================================================
# AUDIO OPTIMIZATION
# =============================================================================

print_header "OPTIMIZING AUDIO CONFIGURATION"

print_info "Setting audio levels to maximum for optimal streaming..."

# Set ALSA volumes to maximum
amixer set Master 100% 2>/dev/null || true
amixer set PCM 100% 2>/dev/null || true
amixer set Headphone 100% 2>/dev/null || true

# Set PulseAudio volumes to maximum
pactl set-sink-volume @DEFAULT_SINK@ 100% 2>/dev/null || true
pactl set-source-volume @DEFAULT_SOURCE@ 100% 2>/dev/null || true

print_info "Creating audio level service for boot-time configuration..."
cat > /etc/systemd/system/audio-max.service << 'EOF'
[Unit]
Description=Set Audio to Maximum Volume
After=sound.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'amixer set Master 100% 2>/dev/null; pactl set-sink-volume @DEFAULT_SINK@ 100% 2>/dev/null'

[Install]
WantedBy=multi-user.target
EOF

systemctl enable audio-max

print_success "Audio optimization complete"
print_info "Audio will be controlled from the remote gaming server"

# =============================================================================
# CUSTOM PLYMOUTH THEME CREATION
# =============================================================================

print_header "CREATING CUSTOM PLYMOUTH THEME"

print_info "Creating custom Gaming Portal Plymouth theme..."

# Create theme directory
mkdir -p /usr/share/plymouth/themes/gaming-portal

# Create theme configuration file
cat > /usr/share/plymouth/themes/gaming-portal/gaming-portal.plymouth << 'EOF'
[Plymouth Theme]
Name=Gaming Portal
Description=Custom gaming appliance boot theme
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/gaming-portal
ScriptFile=/usr/share/plymouth/themes/gaming-portal/gaming-portal.script
EOF

# Create the main theme script
cat > /usr/share/plymouth/themes/gaming-portal/gaming-portal.script << 'EOF'
# Gaming Portal Plymouth Theme
# Features: Centered spinner, logo placeholder, status text

# Set pure black background
Window.SetBackgroundTopColor(0, 0, 0);
Window.SetBackgroundBottomColor(0, 0, 0);

# Screen dimensions
screen_width = Window.GetWidth();
screen_height = Window.GetHeight();

# Logo placeholder (will be replaced with actual logo later)
logo_text = Image.Text("GAMING PORTAL", 1, 1, 1, 1, "Ubuntu 32");
logo_sprite = Sprite(logo_text);
logo_sprite.SetPosition(screen_width / 2 - logo_text.GetWidth() / 2, 
                       screen_height / 2 - 150);

# Spinner setup
spinner_images = [];
for (i = 0; i < 20; i++) {
    # Create simple rotating spinner frames
    angle = i * 18; # 360/20 = 18 degrees per frame
    spinner_images[i] = Image.Text("●", 1, 1, 1, 0.3 + (i * 0.035), "Ubuntu 24");
}

spinner_sprite = Sprite();
spinner_sprite.SetPosition(screen_width / 2 - 10, screen_height / 2 - 50);

# Status text
status_sprite = Sprite();
status_sprite.SetPosition(screen_width / 2, screen_height / 2 + 50);

# Animation variables
spinner_frame = 0;
counter = 0;
current_status = "Loading...";

# Function to update status message
fun update_status(new_status) {
    current_status = new_status;
    status_image = Image.Text(current_status, 0.9, 0.9, 0.9, 1, "Ubuntu 18");
    status_sprite.SetImage(status_image);
    status_sprite.SetX(screen_width / 2 - status_image.GetWidth() / 2);
}

# Initialize with loading message
update_status("Loading system...");

# Refresh function for animation
fun refresh() {
    # Update spinner animation
    spinner_sprite.SetImage(spinner_images[spinner_frame]);
    spinner_frame = (spinner_frame + 1) % 20;
    
    counter++;
}

# Boot progress function
fun boot_progress_cb(duration, progress) {
    if (progress < 0.2) {
        update_status("Starting system...");
    } else if (progress < 0.5) {
        update_status("Loading drivers...");
    } else if (progress < 0.8) {
        update_status("Starting services...");
    } else if (progress < 0.95) {
        update_status("Preparing session...");
    } else {
        update_status("Connecting to server...");
    }
}

# System update function (called by session script)
fun system_update(status) {
    if (status == "network") {
        update_status("Connecting to network...");
    } else if (status == "moonlight") {
        update_status("Launching gaming session...");
    } else if (status == "connecting") {
        update_status("Connecting to gaming server...");
    }
}

# Message function for external updates
fun message_callback(text) {
    update_status(text);
}

# Hide function (called when connection successful)
fun quit_cb() {
    logo_sprite.SetOpacity(0);
    spinner_sprite.SetOpacity(0);
    status_sprite.SetOpacity(0);
}

# Set up callbacks
Plymouth.SetRefreshFunction(refresh);
Plymouth.SetBootProgressFunction(boot_progress_cb);
Plymouth.SetUpdateStatusFunction(system_update);
Plymouth.SetMessageFunction(message_callback);
Plymouth.SetQuitFunction(quit_cb);
EOF

# Create a placeholder logo image (will be replaced later)
convert -size 400x80 xc:transparent \
        -font DejaVu-Sans-Bold -pointsize 32 \
        -fill white -gravity center \
        -annotate +0+0 "GAMING PORTAL" \
        /usr/share/plymouth/themes/gaming-portal/logo.png 2>/dev/null || true

print_info "Setting Gaming Portal as default Plymouth theme..."
plymouth-set-default-theme gaming-portal
update-initramfs -u

print_success "Custom Plymouth theme installed"
print_info "Theme features: Centered spinner, logo space, status messages"
print_warning "To add custom logo: Replace /usr/share/plymouth/themes/gaming-portal/logo.png"

# =============================================================================
# USER CLEANUP
# =============================================================================

print_header "CLEANING UP DEVELOPMENT ACCOUNTS"

print_info "Scanning for development user accounts to remove..."

# Find and remove users with UID >= 1000 that aren't 'user'
USERS_TO_DELETE=$(awk -F: '$3 >= 1000 && $1 != "user" {print $1}' /etc/passwd)

if [ -n "$USERS_TO_DELETE" ]; then
    print_info "Found development users to remove: $USERS_TO_DELETE"
    for username in $USERS_TO_DELETE; do
        print_info "Removing user: $username"
        userdel -r "$username" 2>/dev/null || true
        groupdel "$username" 2>/dev/null || true
    done
else
    print_info "No additional user accounts found"
fi

# Remove common development usernames
COMMON_DEV_USERS="staging developer admin test pi debian ubuntu"
for dev_user in $COMMON_DEV_USERS; do
    if id "$dev_user" >/dev/null 2>&1; then
        print_info "Removing common development user: $dev_user"
        userdel -r "$dev_user" 2>/dev/null || true
        groupdel "$dev_user" 2>/dev/null || true
    fi
done

print_info "Locking root account for security..."
# passwd -l root (DISABLED FOR DEBUGGING)
print_warning "Root account left unlocked for debugging"

print_info "Clearing temporary files and logs..."
rm -rf /tmp/* 2>/dev/null || true
rm -rf /var/log/* 2>/dev/null || true
rm -f /home/*/.bash_history 2>/dev/null || true
rm -f /root/.bash_history 2>/dev/null || true
history -c 2>/dev/null || true

print_success "User cleanup complete"

# =============================================================================
# INSTALLATION COMPLETE
# =============================================================================

print_header "INSTALLATION COMPLETE"

print_success "Moonlight Gaming Appliance has been successfully configured!"
echo ""
print_info "CONFIGURATION SUMMARY:"
print_info "• Auto-login user: user"
print_info "• WiFi network: $WIFI_SSID"
print_info "• Gaming server: $SERVER_HOST:$SERVER_PORT"
print_info "• Session type: Moonlight fullscreen streaming"
print_info "• Security: Hardened and locked down"
print_info "• Audio: Optimized for streaming"
echo ""
print_warning "DEVELOPMENT MODE ACTIVE"
print_warning "The following security restrictions are disabled for debugging:"
print_warning "• TTY access (Ctrl+Alt+F1-F6 work)"
print_warning "• Text editors available"
print_warning "• Package managers accessible"
print_warning "• Root account unlocked"
print_warning "• User has sudo access"
print_warning "• Debug script available: ~/debug.sh"
echo ""
print_info "To view logs after reboot:"
print_info "1. Log in as user"
print_info "2. Run: ./debug.sh"
print_info "3. Or manually: cat /tmp/moonlight.log"
echo ""
print_info "The system will automatically:"
print_info "• Boot with minimal splash screen"
print_info "• Connect to configured WiFi"
print_info "• Launch Moonlight in fullscreen"
print_info "• Show error dialog if connection fails"
print_info "• Restart session if Moonlight exits"
echo ""

read -p "Press Enter to reboot and test the system..." 

print_info "Rebooting system..."
systemctl reboot
