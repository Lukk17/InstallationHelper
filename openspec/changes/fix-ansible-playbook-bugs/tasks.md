## 1. Package Installation Order

- [x] 1.1 Create package_order role/tasks for system_core
- [x] 1.2 Ensure JVM is installed in Phase 2
- [x] 1.3 Ensure SDKMAN is installed in Phase 3
- [x] 1.4 Ensure Snapd is installed in Phase 4
- [x] 1.5 Ensure Flatpak+Flathub is installed in Phase 5
- [x] 1.6 Add package_order documentation to SOFTWARE.md

## 2. Snap Installation Fixes

- [x] 2.1 Fix Debian snap installation (use official apt method)
- [x] 2.2 Fix Arch snap installation (use official pacman method)
- [x] 2.3 Fix Fedora snap installation (use official dnf method)
- [x] 2.4 Remove manual symlink creation tasks

## 3. Antigravity Fix

- [x] 3.1 Update Antigravity installation (Debian/Ubuntu)
- [x] 3.2 Use /etc/apt/keyrings method

## 4. Gradle via SDKMAN (ALL DISTROS)

- [x] 4.1 Update RedHat.yaml - remove gradle dnf package
- [x] 4.2 Update Debian.yaml - remove gradle apt package
- [x] 4.3 Update Archlinux.yaml - gradle via SDKMAN (keep pacman as option)
- [x] 4.4 Update Darwin.yaml - keep brew (macOS)
- [x] 4.5 Update software_installer to skip gradle on Linux
- [x] 4.6 Ensure sdk_manager installs gradle after SDKMAN is ready

## 5. Gridcoin Installation

- [x] 5.1 Update RedHat.yaml - add OpenSUSE repo method
- [ ] 5.2 Update Debian.yaml - add PPA method
- [x] 5.3 Update Archlinux.yaml - keep AUR (already correct)
- [x] 5.4 Create custom task for Gridcoin installation

## 6. Docker on Fedora

- [x] 6.1 Update RedHat.yaml docker package
- [x] 6.2 Change from moby-engine to docker-ce
- [x] 6.3 Add Docker repo task before installation

## 7. Fedora Flatpak Packages

- [x] 7.1 Ensure flatpak is in system_core
- [x] 7.2 Add flathub repo configuration task
- [x] 7.3 Test flatpak packages install

## 8. Unsupported Fedora Packages

- [x] 8.1 Remove hardinfo from Fedora (or use hardinfo2)
- [x] 8.2 Remove gputest from Fedora
- [x] 8.3 Remove partitionmanager from Fedora

## 9. SOFTWARE.md Updates

- [x] 9.1 Add Installation Order section
- [x] 9.2 Update all software entries with correct method per OS
- [x] 9.3 Document SDKMAN usage for Gradle
- [x] 9.4 Document each package's installation method

## 10. Testing

- [ ] 10.1 Test playbook on Debian
- [ ] 10.2 Test playbook on Ubuntu
- [ ] 10.3 Test playbook on Fedora
- [ ] 10.4 Test playbook on Arch Linux

## 11. Audacity → Flatpak (ALL Distros)

- [x] 11.1 Update Debian.yaml - Audacity flatpak
- [x] 11.2 Update RedHat.yaml - Audacity flatpak (was snap)
- [x] 11.3 Update Archlinux.yaml - Audacity flatpak (was pacman)
- [x] 11.4 Update Darwin.yaml - keep brew

## 12. PrusaSlicer → Flatpak (ALL Distros)

- [x] 12.1 Update Debian.yaml - PrusaSlicer flatpak
- [x] 12.2 Update RedHat.yaml - PrusaSlicer flatpak (was snap)
- [x] 12.3 Update Archlinux.yaml - PrusaSlicer flatpak (was pacman)
- [x] 12.4 Update Darwin.yaml - keep brew

## 13. Gridcoin PPA (Debian/Ubuntu)

- [x] 13.1 Add software-properties-common to debian_core
- [x] 13.2 Add Gridcoin PPA task to custom_installs.yaml
- [x] 13.3 Test Gridcoin installation

## 14. Detailed Installation Order Section

- [x] 14.1 Create detailed Installation Order section at bottom of SOFTWARE.md
- [x] 14.2 Document SDK/Runtime Managers (pyenv, nvm, SDKMAN)
- [x] 14.3 Document system packages order
- [x] 14.4 Document package managers order (Phase 1-5)
- [x] 14.5 Document software groups order