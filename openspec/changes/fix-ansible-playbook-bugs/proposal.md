## Why

The Ansible playbook has been tested across multiple Linux distributions (Debian, Ubuntu, Fedora, Arch Linux) and has critical failures because:
1. Wrong installation methods (manual symlinks, deprecated APT keys)
2. Packages not available in certain distros
3. Missing pre-requisites (flatpak not installed before flatpak packages)
4. Need to use official installation methods for each software

We need comprehensive fixes including proper installation order, SDKMAN for Gradle on ALL distros, and correct package sources per distro.

## What Changes

### 1. Snap Installation (ALL DISTROS)
- Remove manual symlink creation  
- Use official snapd installation from snapcraft.io tutorials
- Debian: `apt install snapd`
- Arch: `pacman -S snapd`  
- Fedora: `dnf install snapd`

### 2. Antigravity Repository (Debian/Ubuntu)
- Use official installation method from https://antigravity.google/download/linux
- Create proper /etc/apt/keyrings directory
- Download and dearmor GPG key to /etc/apt/keyrings/
- Create sources.list.d with signed-by option

### 3. Gradle via SDKMAN (ALL DISTROS)
- Install Gradle via SDKMAN! on ALL distributions (Debian, Ubuntu, Fedora, Arch)
- Remove Gradle from package manager installations on all distros
- SDKMAN already installs on all distros - use it for Gradle

### 4. Gridcoin (ALL DISTROS)
- Fedora: Use OpenSUSE repo
  ```
  dnf config-manager addrepo --from-repofile=https://download.opensuse.org/repositories/home:theMarix/Fedora_Rawhide/home:theMarix.repo
  dnf install gridcoinresearch
  ```
- Ubuntu/Debian: Use PPA
  ```
  sudo add-apt-repository ppa:gridcoin/gridcoin-stable
  sudo apt update
  sudo apt install gridcoinresearch
  ```
- Arch: Already correct (AUR)

### 5. Fedora Package Fixes
- Install Steam via Flatpak
- Install HandBrake via Flatpak  
- Install Polychromatic via Flatpak
- Remove unsupported: hardinfo (use hardinfo2), gputest (custom binary), partitionmanager (doesn't exist in Fedora)

### 6. Docker Installation (Fedora)
- Use official Docker repository from https://docs.docker.com/engine/install/fedora/
- Add Docker repository via dnf config-manager
- Install docker-ce, docker-ce-cli, containerd.io, docker-buildx-plugin, docker-compose-plugin

### 7. Package Installation Order (ALL DISTROS)
- Phase 1: Base system packages (gcc, make, curl, etc.)
- Phase 2: JVM (Java) - required by many tools
- Phase 3: SDKMAN - for Gradle, Maven versions
- Phase 4: Snapd - for snap packages
- Phase 5: Flatpak + Flathub - for flatpak packages
- Phase 6: Application packages

### 8. Update SOFTWARE.md
- Update all software entries with correct installation method per OS/distro

### 9. Audacity → Flatpak (ALL DISTROS)
- Install Audacity via flatpak on all distributions for reliability
- https://flathub.org/en/apps/org.audacityteam.Audacity

### 10. PrusaSlicer → Flatpak (ALL DISTROS)
- Install PrusaSlicer via flatpak on all distributions for reliability
- https://flathub.org/en/apps/com.prusa3d.PrusaSlicer

### 11. Gridcoin PPA (Debian/Ubuntu)
- Use official PPA: ppa:gridcoin/gridcoin-stable
- Add software-properties-common as prerequisite

### 12. Detailed Installation Order Section
- Add comprehensive Installation Order section at bottom of SOFTWARE.md
- Document SDK/Runtime Managers order (pyenv → nvm → SDKMAN)
- Document system packages installation order
- Document package managers installation phases

## Capabilities

### New Capabilities
- **package-order-system**: Define proper installation order of dependencies
- **official-package-installers**: Implement distribution-specific official installation methods

### Modified Capabilities
- **gradle-installation**: Change to use SDKMAN on ALL distributions
- **gridcoin-installation**: Use proper repo/ppa per distribution
- **snap-installation**: Use official snapd installation
- **docker-installation**: Use official Docker repository
- **software-documentation**: Update SOFTWARE.md with current methods