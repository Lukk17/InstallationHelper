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

## Section 15: New Issues from Full Log Analysis

### 15.1 Debian Issues

#### 15.1.1: Enable contrib non-free repos (Debian)
- **Problem**: Package may require contrib non-free repos
- **Root Cause**: Need to enable contrib and non-free repos on Debian
- **Fix**: Enable contrib and non-free repos:
```bash
# Enable contrib and non-free repos
echo "deb http://deb.debian.org/debian bookworm contrib non-free non-free-firmware" | sudo tee /etc/apt/sources.list.d/contrib-non-free.list
sudo apt update
# Now install curl
sudo apt install curl
```

#### 15.1.2: curl command not found - Antigravity key download
- **Problem**: curl not installed before Antigravity key download task
- **Root Cause**: curl not in base system before running Antigravity task
- **Fix**: Install curl BEFORE Antigravity key task runs:
```bash
# FIRST: Install curl (must be before any Antigravity task)
sudo apt update && sudo apt install curl

# SECOND: Create keyrings directory
sudo mkdir -p /etc/apt/keyrings

# THIRD: Download and convert GPG key
curl -fsSL https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg | sudo gpg --dearmor --yes -o /etc/apt/keyrings/antigravity-repo-key.gpg
# FOURTH: Create sources list
echo "deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ antigravity-debian main" | sudo tee /etc/apt/sources.list.d/antigravity.list > /dev/null

# FIFTH: Update and install
sudo apt update && sudo apt install antigravity
```
- **Reference**: https://antigravity.google/download/linux

#### 15.1.3: virtualization_config run order (Debian)
- **Problem**: virtualization_config role may fail if Docker not installed yet
- **Fix**: Ensure virtualization_config ALWAYS runs AFTER docker installation on Debian

### 15.2 Ubuntu Issues

#### 15.2.1: curl not installed
- **Problem**: curl not available before APT key download
- **Fix**: Install curl in system packages:
```bash
sudo apt update && sudo apt install curl
```

#### 15.2.2: Antigravity Installation (Ubuntu)
- **Problem**: Antigravity key download fails without prerequisites
- **Fix**: Same as Debian - install curl first, then use keyring method:
```bash
# FIRST: Install curl (must be before any Antigravity task)
sudo apt update && sudo apt install curl

# SECOND: Create keyrings directory
sudo mkdir -p /etc/apt/keyrings

# THIRD: Download and convert GPG key
curl -fsSL https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg | sudo gpg --dearmor --yes -o /etc/apt/keyrings/antigravity-repo-key.gpg
# FOURTH: Create sources list
echo "deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ antigravity-debian main" | sudo tee /etc/apt/sources.list.d/antigravity.list > /dev/null

# FIFTH: Update and install
sudo apt update && sudo apt install antigravity
```
- **Reference**: https://antigravity.google/download/linux

#### 15.2.3: virtualization_config run order (Ubuntu)
- **Problem**: virtualization_config role may fail if Docker not installed yet
- **Fix**: Ensure virtualization_config ALWAYS runs AFTER docker installation on Ubuntu

### 15.3 Fedora Issues

#### 15.3.1: Flathub repo 404
- **Problem**: URL `https://flathub.org/flathub.flatpakrepo` returns 404
- **Root Cause**: Flathub changed their repository URL
- **Fix**: Use new URL:
```bash
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
```

#### 15.3.2: Dart SDK not available
- **Problem**: No `dart` package in Fedora repos
- **Root Cause**: Dart not in Fedora package repos
- **Fix**: ALWAYS install Dart via FVM on ALL distros:
```bash
curl -fsSL https://fvm.app/install.sh | bash
fvm install stable  # or specific version
```

#### 15.3.3: Docker-ce installation (FEDORA - CRITICAL)
- **Problem**: docker-ce package not found, repo not added
- **Root Cause**: Need to add Docker repo BEFORE installing
- **Fix**: Add Docker repo using OFFICIAL method from https://docs.docker.com/engine/install/fedora/:
```bash
sudo dnf config-manager addrepo --from-repofile https://download.docker.com/linux/fedora/docker-ce.repo
sudo dnf install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
```
- **Reference**: https://docs.docker.com/engine/install/fedora/

### 15.3.4: virtualization_config run order (ALL DISTROS)
- **Problem**: virtualization_config role fails because Docker not installed yet
- **Root Cause**: virtualization_config runs BEFORE docker installation
- **Fix**: Ensure virtualization_config ALWAYS runs AFTER docker installation:
  - Move virtualization_config role to run AFTER software_installer role
  - In site.yaml, ensure docker is installed BEFORE virtualization_config task
  - This applies to Debian, Ubuntu, Fedora, Arch Linux

### 15.4 Arch Linux Issues

#### 15.4.1: Flathub repo 404
- **Problem**: Same URL issue as Fedora
- **Fix**: Use correct Flathub URL:
```bash
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
```

#### 15.4.2: virtualization_config run order (Arch)
- **Problem**: virtualization_config role may fail if Docker not installed yet
- **Fix**: Ensure virtualization_config ALWAYS runs AFTER docker installation on Arch

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