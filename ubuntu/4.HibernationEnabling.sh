#!/bin/bash

# This script configures hibernation for an existing swap partition.
# Uses sudo only for commands that require root privileges.

# Check if user can use sudo
if ! sudo -n true 2>/dev/null; then
    echo "This script requires sudo privileges for system configuration changes."
    echo "You may be prompted for your password."
fi

echo "Checking swap size vs RAM..."
# Get swap size in KB and convert to bytes for comparison
SWAP_SIZE_HUMAN=$(swapon --show --noheadings | awk '{print $3}' | head -1)
RAM_SIZE_HUMAN=$(free -h | awk '/^Mem:/{print $2}')

echo "Swap size: $SWAP_SIZE_HUMAN, RAM size: $RAM_SIZE_HUMAN"
echo "Note: For reliable hibernation, swap should be at least equal to RAM size."
echo "Continue with hibernation setup? (y/N)"
read -r response
if [ "$response" != "y" ] && [ "$response" != "Y" ]; then
    exit 1
fi

echo "Starting hibernation setup..."

SWAP_PARTITION=$(swapon --show --noheadings --raw | awk '{print $1}')

if [ -z "$SWAP_PARTITION" ]; then
    echo "Error: No active swap partition found. Please enable a swap partition first."
    exit 1
fi

echo "Found swap partition at $SWAP_PARTITION"
SWAP_UUID=$(sudo blkid -s UUID -o value "$SWAP_PARTITION")

if [ -z "$SWAP_UUID" ]; then
    echo "Error: Could not determine UUID for $SWAP_PARTITION."
    exit 1
fi

echo "Swap partition UUID is $SWAP_UUID"

# Create backup directory in user's home
BACKUP_DIR="$HOME/backup"
if [ ! -d "$BACKUP_DIR" ]; then
    mkdir -p "$BACKUP_DIR"
    echo "Created backup directory: $BACKUP_DIR"
fi

echo "Configuring GRUB..."
GRUB_CONFIG="/etc/default/grub"
BACKUP_FILE="$BACKUP_DIR/grub.backup.$(date +%Y%m%d_%H%M%S)"
sudo cp "$GRUB_CONFIG" "$BACKUP_FILE"
sudo chown "$USER:$(id -gn)" "$BACKUP_FILE"
echo "GRUB backup created: $BACKUP_FILE"

# Check if the resume parameter is already set
if sudo grep -q "resume=UUID=$SWAP_UUID" "$GRUB_CONFIG"; then
    echo "GRUB resume parameter already correctly set. Skipping."
elif sudo grep -q "resume=" "$GRUB_CONFIG"; then
    echo "Warning: Different resume parameter found. Please manually review $GRUB_CONFIG"
    echo "Expected: resume=UUID=$SWAP_UUID"
    exit 1
else
    # More robust GRUB modification
    if sudo grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_CONFIG"; then
        # Add resume parameter to existing GRUB_CMDLINE_LINUX_DEFAULT
        sudo sed -i "/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/\"$/ resume=UUID=$SWAP_UUID\"/" "$GRUB_CONFIG"
        echo "GRUB configuration updated."
    else
        echo "Error: GRUB_CMDLINE_LINUX_DEFAULT not found in $GRUB_CONFIG"
        exit 1
    fi
fi

echo "Updating GRUB bootloader..."
sudo update-grub

echo "Creating PolicyKit rule to show hibernate in menus..."
# Check if modern PolicyKit directory exists
MODERN_POLICY_DIR="/etc/polkit-1/rules.d"
if sudo [ -d "$MODERN_POLICY_DIR" ]; then
    # Use modern .rules format
    POLICY_FILE="$MODERN_POLICY_DIR/10-enable-hibernate.rules"
    sudo tee "$POLICY_FILE" > /dev/null <<EOF
polkit.addRule(function(action, subject) {
    if ((action.id == "org.freedesktop.upower.hibernate" ||
         action.id == "org.freedesktop.login1.hibernate" ||
         action.id == "org.freedesktop.login1.hibernate-multiple-sessions") &&
        subject.isInGroup("sudo")) {
        return polkit.Result.YES;
    }
});
EOF
    echo "Modern PolicyKit rule created."
else
    # Use legacy .pkla format
    POLICY_FILE="/etc/polkit-1/localauthority/50-local.d/com.ubuntu.enable-hibernate.pkla"
    sudo mkdir -p "/etc/polkit-1/localauthority/50-local.d/"
    sudo tee "$POLICY_FILE" > /dev/null <<EOF
[Re-enable hibernate by default in upower]
Identity=unix-user:*
Action=org.freedesktop.upower.hibernate
ResultActive=yes

[Re-enable hibernate by default in logind]
Identity=unix-user:*
Action=org.freedesktop.login1.hibernate;org.freedesktop.login1.hibernate-multiple-sessions
ResultActive=yes
EOF
    echo "Legacy PolicyKit rule created."
fi

echo "PolicyKit rule created."
echo "Configuration complete."
echo ""
echo "After reboot, you can test hibernation with: sudo systemctl hibernate"

echo "Install Hibernation extension so Hibernate button will be visible in power drop down menu"
google-chrome "https://extensions.gnome.org/extension/755/hibernate-status-button/" &>/dev/null & disown %%
echo "In extension setup you can decide which buttons to show"

echo
echo "Available backups in $BACKUP_DIR:"
ls -la "$BACKUP_DIR"/grub.backup.* 2>/dev/null || echo "  No previous GRUB backups found"

echo
echo "Please reboot your system for all changes to take effect."
