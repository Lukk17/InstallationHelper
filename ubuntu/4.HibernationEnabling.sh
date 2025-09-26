#!/bin/bash

# This script configures hibernation for an existing swap partition.
# It must be run with root privileges.

if [ "$EUID" -ne 0 ]; then
  echo "Error: This script must be run as root. Please use sudo."
  exit 1
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
SWAP_UUID=$(blkid -s UUID -o value "$SWAP_PARTITION")

if [ -z "$SWAP_UUID" ]; then
    echo "Error: Could not determine UUID for $SWAP_PARTITION."
    exit 1
fi

echo "Swap partition UUID is $SWAP_UUID"


echo "Configuring GRUB..."
GRUB_CONFIG="/etc/default/grub"
cp "$GRUB_CONFIG" "$GRUB_CONFIG.backup.$(date +%Y%m%d_%H%M%S)"

# Check if the resume parameter is already set
if grep -q "resume=UUID=$SWAP_UUID" "$GRUB_CONFIG"; then
    echo "GRUB resume parameter already correctly set. Skipping."
elif grep -q "resume=" "$GRUB_CONFIG"; then
    echo "Warning: Different resume parameter found. Please manually review $GRUB_CONFIG"
    echo "Expected: resume=UUID=$SWAP_UUID"
    exit 1
else
    # More robust GRUB modification
    if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_CONFIG"; then
        # Add resume parameter to existing GRUB_CMDLINE_LINUX_DEFAULT
        sed -i "/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/\"$/ resume=UUID=$SWAP_UUID\"/" "$GRUB_CONFIG"
        echo "GRUB configuration updated."
    else
        echo "Error: GRUB_CMDLINE_LINUX_DEFAULT not found in $GRUB_CONFIG"
        exit 1
    fi
fi

echo "Updating GRUB bootloader..."
update-grub

echo "Creating PolicyKit rule to show hibernate in menus..."
# Check if modern PolicyKit directory exists
MODERN_POLICY_DIR="/etc/polkit-1/rules.d"
if [ -d "$MODERN_POLICY_DIR" ]; then
    # Use modern .rules format
    POLICY_FILE="$MODERN_POLICY_DIR/10-enable-hibernate.rules"
    cat > "$POLICY_FILE" <<EOF
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
    mkdir -p "/etc/polkit-1/localauthority/50-local.d/"
    cat > "$POLICY_FILE" <<EOF
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
echo "Please reboot your system for all changes to take effect."
