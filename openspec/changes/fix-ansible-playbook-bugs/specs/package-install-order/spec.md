# package-install-order

## Context
The Ansible playbook needs proper installation order to succeed. Many packages depend on prerequisites being installed first.

## Problem
- Packages installed before their dependencies
- docker-ce not found because repo not added first
- flatpak packages fail because flatpak not installed first
- Dart fails because FVM not installed first

## Phases

### Phase 1: Base System
Install first - required by everything:
- gcc, make, curl, git, wget
- bash (required by SDKMAN)

Distro-specific:
- Debian/Ubuntu: `apt install gcc make curl git wget`
- Fedora: `dnf install gcc make curl git wget`
- Arch: `pacman -S gcc make curl git wget`

### Phase 2: JVM
Required by many tools (Gradle, Maven):
- OpenJDK 17+

### Phase 3: SDK Managers
Install in this order:
- SDKMAN (for Gradle, Maven)
- FVM (for Flutter/Dart)
- NVM (for Node.js)
- pyenv (for Python) - optionally

### Phase 4: Snapd
For snap packages:
- Install snapd package

### Phase 5: Flatpak + Flathub
For flatpak packages:
- Install flatpak package
- Add flathub repository:
  - OLD (404): `https://flathub.org/flathub.flatpakrepo`
  - NEW: `https://dl.flathub.org/repo/flathub.flatpakrepo`

### Phase 6: Docker
Install BEFORE virtualization_config:
- Fedora: `dnf config-manager addrepo --from-repofile https://download.docker.com/linux/fedora/docker-ce.repo && dnf install docker-ce`
- Debian/Ubuntu: Use docker.io or install docker-ce

### Phase 7: Application Packages
All software after phases 1-6

## Implementation
Add phase comments to software_installer tasks. Ensure proper order in site.yaml.

## Testing
Verify each phase completes before next phase starts.

## References
- https://antigravity.google/download/linux
- https://docs.docker.com/engine/install/fedora/
- https://dl.flathub.org/repo/flathub.flatpakrepo