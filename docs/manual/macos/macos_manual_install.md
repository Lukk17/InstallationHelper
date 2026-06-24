# Manual install — macOS

Install commands for every app the playbook manages on macOS, via Homebrew. To install the whole `brew` set at once, run [`install.sh`](install.sh).

> `brew install` = CLI formulae; `brew install --cask` = GUI apps. Direct DMG installs (Antigravity, Gridcoin) are in [Manual install required](#manual-install-required).

## Prerequisites

Install Homebrew if you don't have it:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

## Browsers

| App | Install command |
|---|---|
| Google Chrome | `brew install --cask google-chrome` |
| Brave | `brew install --cask brave-browser` |
| Tor Browser | `brew install --cask tor-browser` |

## Dev tools

| App | Install command |
|---|---|
| Git | `brew install git` |
| Maven | `brew install maven` |
| Gradle | `brew install gradle` |
| OpenSSL | `brew install openssl@3` |
| Postman | `brew install --cask postman` |
| DBeaver CE | `brew install --cask dbeaver-community` |
| kubectl | `brew install kubernetes-cli` |
| Minikube | `brew install minikube` |
| k3d | `brew install k3d` |
| Helm | `brew install helm` |
| Terraform | `brew install hashicorp/tap/terraform` (HashiCorp tap — off Homebrew core since the BUSL relicense) |
| GitHub CLI | `brew install gh` |
| jq | `brew install jq` |
| fzf | `brew install fzf` |
| ripgrep | `brew install ripgrep` |
| Lens | `brew install --cask lens` |
| FileZilla → Cyberduck | `brew install --cask cyberduck` |
| Bruno CLI | `brew install bruno-cli` |

> No maintained Homebrew cask exists for FileZilla; the playbook maps it to **Cyberduck**. For FileZilla itself, download from [filezilla-project.org](https://filezilla-project.org/).

## IDEs and editors

| App | Install command |
|---|---|
| IntelliJ IDEA | `brew install --cask intellij-idea` |
| VS Code | `brew install --cask visual-studio-code` |
| Sublime Text | `brew install --cask sublime-text` |
| Arduino IDE 2.x | `brew install --cask arduino-ide` |
| Bruno | `brew install --cask bruno` |

> Antigravity needs a manual DMG install — see below.

## Communication

| App | Install command |
|---|---|
| Discord | `brew install --cask discord` |
| Slack | `brew install --cask slack` |
| Microsoft Teams | `brew install --cask microsoft-teams` |
| Telegram | `brew install --cask telegram` |
| Signal | `brew install --cask signal` |
| WhatsApp | `brew install --cask whatsapp` |

## Productivity

| App | Install command |
|---|---|
| Obsidian | `brew install --cask obsidian` |
| Bitwarden | `brew install --cask bitwarden` |
| KeePassXC | `brew install --cask keepassxc` |
| OnlyOffice | `brew install --cask onlyoffice` |

## Media and design

| App | Install command |
|---|---|
| VLC | `brew install --cask vlc` |
| Spotify | `brew install --cask spotify` |
| GIMP | `brew install --cask gimp` |
| Krita | `brew install --cask krita` |
| HandBrake | `brew install --cask handbrake-app` |
| Audacity | `brew install --cask audacity` |
| RawTherapee | `brew install --cask rawtherapee` |

## Gaming

| App | Install command |
|---|---|
| Steam | `brew install --cask steam` |
| EA app | `brew install --cask ea` |
| GOG Galaxy | `brew install --cask gog-galaxy` |
| Epic Games | `brew install --cask epic-games` |
| CurseForge | `brew install --cask curseforge` |

## CAD and 3D

| App | Install command |
|---|---|
| FreeCAD | `brew install --cask freecad` |
| PrusaSlicer | `brew install --cask prusaslicer` |

## Utilities

| App | Install command |
|---|---|
| TeamViewer | `brew install --cask teamviewer` |
| VeraCrypt | `brew install --cask veracrypt` |
| Speedtest CLI | `brew install speedtest-cli` |
| Lynis | `brew install lynis` |
| Stats (HWMonitor) | `brew install --cask stats` |
| GrandPerspective (WizTree) | `brew install --cask grandperspective` |
| LuLu (firewall) | `brew install --cask lulu` |
| Balena Etcher | `brew install --cask balenaetcher` |

## Crypto / volunteer

| App | Install command |
|---|---|
| BOINC | `brew install --cask boinc` |

> Gridcoin needs a manual DMG install — see below.

## Virtualization

| App | Install command |
|---|---|
| UTM | `brew install --cask utm` |
| Docker Desktop | `brew install --cask docker-desktop` |
| VMware Fusion | `brew install --cask vmware-fusion` |

## Developer toolchain (SDK / runtimes)

Run these as your normal user, in order.

**NVM** (pinned `0.40.4`) + Node LTS:

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash
```

```bash
nvm install --lts
```

**SDKMAN** + Java:

```bash
curl -s https://get.sdkman.io | bash
```

```bash
sdk install java 21.0.11-tem
```

**Pyenv** + Python:

```bash
curl https://pyenv.run | bash
```

```bash
pyenv install 3.11.15
```

**FVM** (Flutter) + Flutter stable:

```bash
curl -fsSL https://fvm.app/install.sh | bash
```

```bash
fvm install stable
```

**Dart SDK:**

```bash
brew install dart
```

## AI tools

Need Node from NVM above first.

| Tool | Install command |
|---|---|
| Claude Code CLI | `npm install -g @anthropic-ai/claude-code` |
| Claude Desktop | `brew install --cask claude` |
| OpenCode | `npm install -g opencode-ai` |
| OpenSpec | `npm install -g openspec` |
| LM Studio | `curl -fsSL https://lmstudio.ai/install.sh \| bash` |

**Stable Diffusion WebUI** (pinned `v1.10.1`):

```bash
git clone --branch v1.10.1 https://github.com/AUTOMATIC1111/stable-diffusion-webui
```

## Shell

```bash
brew install zsh
```

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```

```bash
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
```

## Manual install required

These are **not** in `install.sh` — the playbook installs them from a direct DMG. Install by hand:

- **Antigravity** — download the DMG for your chip from Google's CDN, then drag `Antigravity.app` to `/Applications`. Apple Silicon:

  ```bash
  curl -fsSLo /tmp/Antigravity.dmg "https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/1.13.3-4533425205018624/darwin-arm/Antigravity.dmg"
  ```

  Intel:

  ```bash
  curl -fsSLo /tmp/Antigravity.dmg "https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/1.13.3-4533425205018624/darwin-x64/Antigravity.dmg"
  ```

- **Gridcoin** (pinned `5.5.0.0`) — download the DMG and drag the app to `/Applications`:

  ```bash
  curl -fsSLo /tmp/gridcoin.dmg https://github.com/gridcoin-community/Gridcoin-Research/releases/download/5.5.0.0/gridcoin-5.5.0.0-macos-x86_64.dmg
  ```
