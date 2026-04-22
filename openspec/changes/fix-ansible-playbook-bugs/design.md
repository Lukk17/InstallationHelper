## Context

The current playbook has failed because:
1. Wrong installation order - prerequisites not installed first
2. Wrong package sources per distribution
3. Missing pre-requisites (JVM, SDKMAN, Snap, Flatpak)

## Goals / Non-Goals

**Goals:**
- Fix all identified failures using official methods
- Establish proper package installation order
- Update var files for correct package sources per distro
- Update SOFTWARE.md with current methods

**Non-Goals:**
- Don't hide errors with workarounds
- Don't skip packages that need to be fixed

## Decisions

### Decision 1: Package Installation Order
**Phase Order:**
1. **Base System**: gcc, make, curl, git, wget (all distros)
2. **JVM**: OpenJDK 17+ (required by many tools)
3. **SDKMAN**: Install first for Gradle, Maven (ALL DISTROS)
4. **Snapd**: For snap packages
5. **Flatpak + Flathub**: For flatpak packages
6. **Application Packages**: All software

**Rationale**: Dependencies must be available before packages that need them.

### Decision 2: Gradle via SDKMAN
**Choice**: Install Gradle via SDKMAN on ALL distributions, not package managers
**Install**: `sdk install gradle`
**Rationale**: Version management, works on all distros

### Decision 3: Gridcoin per Distro
**Fedora**:
```bash
dnf config-manager addrepo --from-repofile=https://download.opensuse.org/repositories/home:theMarix/Fedora_Rawhide/home:theMarix.repo
dnf install gridcoinresearch
```
**Ubuntu/Debian**:
```bash
add-apt-repository ppa:gridcoin/gridcoin-stable
apt update
apt install gridcoinresearch
```
**Arch**: Already correct via AUR

### Decision 4: Docker on Fedora
**Choice**: Official Docker repository
```bash
dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
dnf install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable docker
```

### Decision 5: Flatpak Pre-requisite
**Choice**: Install flatpak and flathub BEFORE flatpak packages
```bash
# Install flatpak
dnf install flatpak

# Add flathub
flatpak remote-add --if-not-exists flathub https://flathub.org/flathub.flatpakrepo
```

### Decision 6: Snapd Installation
**Debian**: `apt install snapd`
**Arch**: `pacman -S snapd`
**Fedora**: `dnf install snapd`

### Decision 7: Antigravity
**Method**:
```bash
mkdir -p /etc/apt/keyrings
curl -fsSL https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg | \
  gpg --dearmor --yes -o /etc/apt/keyrings/antigravity-repo-key.gpg
echo "deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ antigravity-debian main" | \
  tee /etc/apt/sources.list.d/antigravity.list > /dev/null
apt update
apt install antigravity
```

## Implementation Tasks

### Update vars/{Distro}.yaml Files

#### RedHat.yaml changes needed:
- gradle: Remove (use SDKMAN)
- gridcoin: Add custom task with OpenSUSE repo
- docker: Change to docker-ce

#### Debian.yaml changes needed:
- gradle: Remove (use SDKMAN)  
- gridcoin: Add PPA method
- docker: Already docker.io (OK)

#### Archlinux.yaml changes needed:
- gradle: Already pacman - can keep or use SDKMAN (user preference)

## Risks / Trade-offs

- **[Risk]**: OpenSUSE repo might be unreliable
  - **Mitigation**: Use fallback to manual download if repo fails

- **[Risk]**: SDKMAN requires bash
  - **Mitigation**: Ensure bash is installed first