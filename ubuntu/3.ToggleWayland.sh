#!/bin/bash

# This script toggles the default display server by enabling or disabling Wayland in the GDM3 config.
# Uses sudo only for commands that require root privileges.

CONFIG_FILE="/etc/gdm3/custom.conf"
GRUB_CONFIG="/etc/default/grub"

# Check if GDM3 config exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: $CONFIG_FILE not found. Is GDM3 installed?"
    exit 1
fi

# Check if user can use sudo
if ! sudo -n true 2>/dev/null; then
    echo "This script requires sudo privileges for system configuration changes."
    echo "You may be prompted for your password."
fi

# Create backup directory in user's home
BACKUP_DIR="$HOME/backup"
if [ ! -d "$BACKUP_DIR" ]; then
    mkdir -p "$BACKUP_DIR"
    echo "Created backup directory: $BACKUP_DIR"
fi

# Create backups with timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/custom.conf.bak.$TIMESTAMP"
sudo cp "$CONFIG_FILE" "$BACKUP_FILE"
sudo chown "$USER:$(id -gn)" "$BACKUP_FILE"
echo "GDM backup created: $BACKUP_FILE"

# Function to ensure [daemon] section exists
ensure_daemon_section() {
    if ! sudo grep -q "^\[daemon\]" "$CONFIG_FILE"; then
        echo "[daemon]" | sudo tee -a "$CONFIG_FILE" > /dev/null
        echo "Added [daemon] section to config file"
    fi
}

# Check if NVIDIA driver is in use
NVIDIA_DRIVER=$(lspci | grep -i nvidia)
NVIDIA_MODULE=$(lsmod | grep nvidia)

echo "Currently running: $XDG_SESSION_TYPE"

if [ -n "$NVIDIA_DRIVER" ] && [ -n "$NVIDIA_MODULE" ]; then
    echo "NVIDIA GPU detected with driver loaded"
    NVIDIA_PRESENT=true
else
    NVIDIA_PRESENT=false
fi

echo
echo "Which session do you want to set as the default?"
echo "  1) Enable Wayland"
echo "  2) Force X11 (Disable Wayland)"
read -p "Enter your choice [1 or 2]: " choice

case $choice in
    1)
        echo "Enabling Wayland..."
        ensure_daemon_section

        # Enable Wayland in GDM
        sudo sed -i '/^\[daemon\]/,/^\[/ { s/^WaylandEnable=false/#WaylandEnable=false/ }' "$CONFIG_FILE"

        # Handle NVIDIA setup
        if [ "$NVIDIA_PRESENT" = true ]; then
            echo "NVIDIA detected. Configuring GRUB for Wayland compatibility..."

            # Backup GRUB config
            GRUB_BACKUP="$BACKUP_DIR/grub.bak.$TIMESTAMP"
            sudo cp "$GRUB_CONFIG" "$GRUB_BACKUP"
            sudo chown "$USER:$(id -gn)" "$GRUB_BACKUP"
            echo "GRUB backup created: $GRUB_BACKUP"

            # Add nvidia-drm.modeset=1 if not present
            if ! sudo grep -q "nvidia-drm.modeset=1" "$GRUB_CONFIG"; then
                sudo sed -i "/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/\"$/ nvidia-drm.modeset=1\"/" "$GRUB_CONFIG"
                echo "Added nvidia-drm.modeset=1 to GRUB"

                echo "Updating GRUB..."
                sudo update-grub
                GRUB_UPDATED=true
            else
                echo "nvidia-drm.modeset=1 already present in GRUB"
                GRUB_UPDATED=false
            fi
        fi

        echo "Wayland has been enabled."
        ;;
    2)
        echo "Forcing X11 by disabling Wayland..."
        ensure_daemon_section

        # Disable Wayland in GDM
        sudo sed -i '/^\[daemon\]/,/^\[/ { /^#WaylandEnable=false/d }' "$CONFIG_FILE"
        if sudo grep -q "^WaylandEnable=false" "$CONFIG_FILE"; then
            echo "WaylandEnable=false already set"
        else
            sudo sed -i '/^\[daemon\]/a WaylandEnable=false' "$CONFIG_FILE"
        fi

        echo "Wayland has been disabled. System will use X11."
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

echo
echo "Available backups in $BACKUP_DIR:"
ls -la "$BACKUP_DIR"/*.bak.$TIMESTAMP 2>/dev/null || echo "  No backups from this session found"

echo
if [ "$choice" = "1" ] && [ "$NVIDIA_PRESENT" = true ] && [ "$GRUB_UPDATED" = true ]; then
    echo "IMPORTANT: GRUB was updated for NVIDIA Wayland support."
    echo "You must REBOOT for Wayland to work properly with NVIDIA."
else
    echo "Changes will take effect after:"
    echo "  - Logging out and back in, OR"
    echo "  - Restarting GDM: sudo systemctl restart gdm3"
fi

if [ "$choice" = "1" ]; then
    echo
    echo "After restart, check your session with: echo \$XDG_SESSION_TYPE"
fi

echo "For NVIDIA users: GDM blocks Wayland by default with drivers version more recent than 510 on NVIDIA systems."
echo "To override this, override rule:"
echo "sudo touch /etc/udev/rules.d/61-gdm.rules"
