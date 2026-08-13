# Package Installation Analysis by Distribution

## Summary of Failed Packages from Logs

| Package | Debian | Ubuntu | Fedora | Arch | Issue |
|---------|--------|--------|--------|------|-------|
| gradle | apt ✓ | ? | NOT IN REPOS | pacman ✓ | Already marked for SDKMAN on Fedora (line 11 RedHat.yaml: `# gradle: not in Fedora`) |
| steam | flatpak ✓ | ? | flatpak FAIL | pacman ✓ | Package available in config |
| handbrake | apt ✓ | ? | flatpak FAIL | pacman ✓ | Package available in config |
| polychromatic | flatpak ✓ | ? | flatpak FAIL | flatpak ✓ | Package available in config |
| hardinfo | apt ✓ | ? | dnf FAIL | pacman ✓ | Uses hardinfo2 on Fedora |
| gridcoin | custom ✓ | ? | custom FAIL | custom | Need decision |
| gputest | custom ✓ | ? | (not tried) | aur | Need decision |
| partitionmanager | apt ✓ | ? | dnf FAIL | pacman | Uses kde-partitionmanager on Fedora |

## Detailed Analysis

### ✅ Already Correct (No Action Needed)

| Package | Debian | Ubuntu | Fedora | Arch | Fix |
|---------|--------|--------|--------|------|-----|
| gradle | apt | - | SDKMAN | pacman | Already correct - SDKMAN for Fedora |
| steam | flatpak | - | flatpak | pacman | Already correct |
| handbrake | apt | - | flatpak | pacman | Already correct |
| polychromatic | flatpak | - | flatpak | flatpak | Already correct |
| hardinfo | apt | - | hardinfo2 (dnf) | hardinfo2 | Already correct |
| partitionmanager | apt | - | kde-partitionmanager | pacman | Already correct |

### ❓ Need Your Decision

| Package | Current Fedora | Suggested Fix | Notes |
|---------|--------------|--------------|-------|
| gridcoin | custom flatpak bundle | ? | Not in Fedora repos. Comment says "installed via custom flatpak bundle task" |
| gputest | custom binary download | ? | Comment says "installed via custom binary download task in custom_installs.yaml" |

### Why Flatpak Packages Failed on Fedora

The configuration is CORRECT but they failed because:
1. **Flatpak was not installed** on the system first
2. **Flathub repo was not added** before trying to install

Solution: Ensure flatpak and flathub are configured BEFORE attempting to install flatpak packages.

### Docker Issue

| Distro | Current | Issue | Recommended |
|-------|---------|-------|-------------|
| Fedora | moby-engine (dnf) | Package works but user wants official Docker CE | Use official Docker repo |

The current `docker: { manager: "dnf", package: "moby-engine" }` works but the user wants Docker CE from official repo.

### Snap Issues

| Distro | Current | Issue | Fix |
|-------|--------|-------|-----|
| Debian | Manual symlink | Failed - snapd not installed | Install snapd via official method first |
| Arch | Service not running | Snapd installed but service not started | Install and enable snapd properly |

### Antigravity (Debian/Ubuntu)

| Distro | Current | Issue | Fix |
|-------|--------|-------|-----|
| Debian/Ubuntu | wget to file | Wrong method | Use official method with /etc/apt/keyrings |