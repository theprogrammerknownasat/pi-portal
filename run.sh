#! /bin/bash
# Update system
apt update && apt upgrade -y

# Install only what we absolutely need
apt install -y \
    xorg \
    lightdm \
    plymouth \
    plymouth-themes \
    flatpak \
    network-manager \
    pulseaudio \
    curl \
    wget

# Setup Flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# Install Moonlight
flatpak install -y flathub com.moonlight_stream.Moonlight

# Create a simple wrapper script for Moonlight
echo '#!/bin/bash
flatpak run com.moonlight_stream.Moonlight "$@"' > /usr/local/bin/moonlight
chmod +x /usr/local/bin/moonlight

# Create directory for our scripts
mkdir -p /opt/moonlight-appliance

# Create the main session script
cat > /opt/moonlight-appliance/session.sh << 'EOF'
#!/bin/bash

# Simple Moonlight Appliance Session
# Connects to gaming server or shows error

LOG_FILE="/tmp/moonlight.log"

log() {
    echo "$(date): $1" >> "$LOG_FILE"
}

log "Appliance starting..."

# Wait for network (30 seconds max)
log "Waiting for network..."
for i in {1..30}; do
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log "Network connected"
        break
    fi
    sleep 1
    if [ $i -eq 30 ]; then
        log "Network timeout"
        /opt/moonlight-appliance/show-error.sh "No network connection"
        exit 1
    fi
done

# Try to launch Moonlight fullscreen
log "Starting Moonlight..."
moonlight --fullscreen &
MOONLIGHT_PID=$!

# Wait 45 seconds for connection
sleep 45

# Check if Moonlight is still running (means it connected)
if kill -0 $MOONLIGHT_PID 2>/dev/null; then
    log "Moonlight connected successfully"
    # Hide plymouth now that we're connected
    plymouth quit 2>/dev/null || true
    # Wait for Moonlight to exit
    wait $MOONLIGHT_PID
    log "Moonlight session ended"
else
    log "Moonlight failed to connect"
    /opt/moonlight-appliance/show-error.sh "Could not connect to gaming server"
fi

# If we get here, either Moonlight exited or failed
/opt/moonlight-appliance/show-error.sh "Session ended"
EOF

chmod +x /opt/moonlight-appliance/session.sh

cat > /opt/moonlight-appliance/show-error.sh << 'EOF'
#!/bin/bash

# Show simple error message and shutdown

MESSAGE="$1"
if [ -z "$MESSAGE" ]; then
    MESSAGE="Connection failed"
fi

# Kill plymouth if running
plymouth quit 2>/dev/null || true

# Show error message using zenity (simple dialog)
DISPLAY=:0 zenity --error \
    --title="Gaming Portal" \
    --text="$MESSAGE

Contact your friend for help.

Press OK to shutdown." \
    --width=400 \
    --height=200 2>/dev/null

# Shutdown immediately
systemctl poweroff
EOF

chmod +x /opt/moonlight-appliance/show-error.sh

# Install zenity for simple dialogs
apt install -y zenity

apt install -y imagemagick
convert -size 1920x1080 xc:black /usr/share/pixmaps/black.png

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
default-user=staging
EOF

cat > /usr/share/xsessions/moonlight-appliance.desktop << 'EOF'
[Desktop Entry]
Name=Moonlight Appliance
Comment=Gaming Portal Session
Exec=/opt/moonlight-appliance/session.sh
Type=Application
DesktopNames=Moonlight
EOF

useradd -m -s /bin/bash user

# Locked down user with a 'random' password
echo 'user:Zx9#mK8$vN2&pL4!' | chpasswd

# Configure LightDM to auto-login with our session
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

sed -i 's/default-user=staging/default-user=user/' /etc/lightdm/lightdm-gtk-greeter.conf
