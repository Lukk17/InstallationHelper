## ADDED Requirements

### Requirement: Official Snapd Installation
The system SHALL install snapd using official installation methods for each distribution.

#### Scenario: Install Snap on Debian
- **WHEN** Debian system needs snapd
- **THEN** install via: `apt update && apt install snapd` from official Debian repos

#### Scenario: Install Snap on Arch Linux
- **WHEN** Arch Linux system needs snapd
- **THEN** install via: `pacman -S snapd` from official Arch repos

#### Scenario: Install Snap on Fedora
- **WHEN** Fedora system needs snapd
- **THEN** install via: `dnf install snapd` from official Fedora repos

### Requirement: Official Antigravity Installation
The system SHALL install Antigravity using official method with /etc/apt/keyrings directory.

#### Scenario: Antigravity Installation
- **WHEN** Antigravity is requested on Debian/Ubuntu
- **THEN** create /etc/apt/keyrings, download GPG key, create sources.list with signed-by, update, install

### Requirement: Gradle via SDKMAN
The system SHALL install Gradle via SDKMAN! for version management.

#### Scenario: Gradle Installation
- **WHEN** Gradle is requested on any Linux distribution
- **THEN** install via: `sdk install gradle` command (using existing sdk_manager role)

### Requirement: Docker Official Repository
The system SHALL install Docker using official Docker repository method.

#### Scenario: Docker Installation on Fedora
- **WHEN** Docker is requested on Fedora
- **THEN** add Docker repository via `dnf config-manager`, install docker-ce packages, enable service

### Requirement: Flatpak for GUI Applications
The system SHALL use Flatpak for GUI applications that don't have official Fedora packages.

#### Scenario: Flatpak Not Installed
- **WHEN** Flatpak is not installed on the system
- **THEN** install flatpak first

#### Scenario: Install Steam via Flatpak
- **WHEN** Steam is requested on Fedora
- **THEN** install via: `flatpak install flathub com.valvesoftware.Steam`

#### Scenario: Install HandBrake via Flatpak
- **WHEN** HandBrake is requested on Fedora
- **THEN** install via: `flatpak install flathub fr.handbrake.ghb`

#### Scenario: Install Polychromatic via Flatpak
- **WHEN** Polychromatic is requested on Fedora
- **THEN** install via: `flatpak install flathub app.polychromatic.controller`

### Requirement: Unsupported Packages Handling
The system SHALL NOT attempt to install packages that don't exist in a distribution's repositories.

#### Scenario: Package Not Available
- **WHEN** a package is requested but not available in the current distribution
- **THEN** skip with warning message, do not fail the playbook