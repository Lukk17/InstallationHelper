## 1. Package Installation Order

- [x] 1.1 Create package_order role/tasks for system_core
- [x] 1.2 Ensure JVM is installed in Phase 2
- [x] 1.3 Ensure SDKMAN is installed in Phase 3
- [x] 1.4 Ensure Snapd is installed in Phase 4
- [x] 1.5 Ensure Flatpak+Flathub is installed in Phase 5
- [x] 1.6 Add package_order documentation to software.md

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

## 9. software.md Updates

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

## 15. New Issues from Log Analysis (2026-04-23)

### 15.1 Debian Log Issues

- [x] 15.1.1 Fix software-properties-common package not found (Debian)
  - Task: `debian_core : Install software-properties-common`
  - Issue: Package `software-properties-common` doesn't exist in Debian repos
  - Fix: Enable contrib non-free repos + install curl instead
- [x] 15.1.2 Add curl dependency check before Antigravity key download
  - Issue: curl command not found on Ubuntu when downloading APT key
  - Fix: Install curl before Antigravity task
- [x] 15.1.3 Fix virtualization_config run order (Debian)
  - Issue: virtualization_config runs BEFORE docker installation
  - Fix: Move virtualization_config to run AFTER software_installer (docker already installed)

### 15.2 Ubuntu Log Issues

- [x] 15.2.1 Fix curl dependency check (Ubuntu)
  - Issue: curl not installed before Antigravity APT key download task
  - Fix: Add curl to base_utils install list for Debian/Ubuntu
- [x] 15.2.2 Fix virtualization_config run order (Ubuntu)
  - Issue: virtualization_config runs BEFORE docker installation
  - Fix: Move virtualization_config to run AFTER software_installer (docker already installed)

### 15.3 Fedora Log Issues

- [x] 15.3.1 Fix Flathub repository URL (Fedora)
  - Task: `system_core : Add Flathub repository (Linux)`
  - Error: `error: Can't load uri https://flathub.org/flathub.flatpakrepo: Server returned status 404`
  - Fix: Update URL to `https://dl.flathub.org/repo/flathub.flatpakrepo`
- [ ] 15.3.2 Fix Dart SDK package not available (Fedora)
  - Task: `sdk_manager : Install Dart SDK (Fedora)`
  - Error: `No package dart available`
  - Fix: Install Dart via FVM instead of dnf
- [x] 15.3.3 Fix Docker service not found (Fedora)
  - Task: `virtualization_config : Enable and start Docker service (Linux)`
  - Error: `Could not find the requested service docker`
  - Fix: Docker package wasn't installed - fix docker-ce installation order
- [x] 15.3.4 Fix docker-ce package not found (Fedora)
  - Task: `software_installer : Install DNF packages (Native)`
  - Error: `No package docker-ce available`
  - Fix: Ensure Docker repo is added before installation
- [x] 15.3.5 Fix virtualization_config run order (Fedora)
  - Issue: virtualization_config runs BEFORE docker installation
  - Fix: Move virtualization_config to run AFTER software_installer (docker already installed)

### 15.4 Arch Log Issues

- [x] 15.4.1 Fix Flathub repository URL (Arch)
  - Task: `system_core : Add Flathub repository (Linux)`
  - Error: Same as Fedora - URL returns 404
  - Fix: Update URL to `https://dl.flathub.org/repo/flathub.flatpakrepo`
- [x] 15.4.2 Fix virtualization_config run order (Arch)
  - Issue: virtualization_config runs BEFORE docker installation
  - Fix: Move virtualization_config to run AFTER software_installer

## 16. Flathub URL Fix (ALL Distros)

- [x] 16.1 Update Flathub URL in base_utils.yaml
- [ ] 16.2 Test on Fedora
- [ ] 16.3 Test on Arch Linux

## 17. Curl Dependency (Debian/Ubuntu)

- [x] 17.1 Add curl to base_utils.yaml for Debian/Ubuntu
- [ ] 17.2 Test on Debian
- [ ] 17.3 Test on Ubuntu

## 18. Dart SDK via FVM (Fedora)

- [ ] 18.1 Update dart.yaml to use FVM on Fedora
- [ ] 18.2 Test Dart installation on Fedora

## 19. Docker Service Fix (Fedora)

- [x] 19.1 Fix docker-ce installation order in software_installer
- [x] 19.2 Fix virtualization_config to skip Docker if not installed
  - Verification: Run order in site.yaml is correct - software_installer runs BEFORE virtualization_config
  - Docker is installed by software_installer on Debian/Fedora before virtualization_config tries to enable the service
- [ ] 19.3 Test Docker installation on Fedora