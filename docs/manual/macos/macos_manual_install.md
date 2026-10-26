# Manual install — macOS

Install commands for every app the playbook manages on macOS, via Homebrew. To install the whole `brew` set at once, run [`install.sh`](install.sh). It installs one package per `brew` call, so a name that fails costs only that package. A package that fails is tried again after twenty seconds and a `brew update`, four attempts in all, and it lists every package that failed at the end and exits 1.

> `brew install` = CLI formulae; `brew install --cask` = GUI apps. The one direct DMG install, Gridcoin, is in [Manual install required](#manual-install-required).

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
| uv | `brew install uv` |
| pipx | `brew install pipx` |
| Go | `brew install go` |
| Lens | `brew install --cask lens` |
| FileZilla → Cyberduck | `brew install --cask cyberduck` |
| Bruno CLI | `brew install bruno-cli` |

> No maintained Homebrew cask exists for FileZilla; the playbook maps it to **Cyberduck**. For FileZilla itself, download from [filezilla-project.org](https://filezilla-project.org/).

## IDEs and editors

| App | Install command |
|---|---|
| JetBrains Toolbox | `brew install --cask jetbrains-toolbox`. IntelliJ IDEA and the other JetBrains IDEs install from Toolbox after you sign in |
| VS Code | `brew install --cask visual-studio-code` |
| Sublime Text | `brew install --cask sublime-text` |
| Arduino IDE 2.x | `brew install --cask arduino-ide` |
| Bruno | `brew install --cask bruno` |
| Antigravity | `brew install --cask antigravity`, macOS 13 or newer |

## Communication

| App | Install command |
|---|---|
| Discord | `brew install --cask discord` |
| Slack | `brew install --cask slack` |
| Zoom | `brew install --cask zoom` |
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
| Syncthing | `brew install --cask syncthing-app` |
| Tailscale | `brew install --cask tailscale-app` |
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
| VirtualBox | `brew install --cask virtualbox`. On Apple Silicon it runs arm64 guests only |
| VMware Fusion | not available from Homebrew, the `vmware-fusion` cask no longer exists. Download it from Broadcom's support portal after signing in, or use UTM |

## Developer toolchain (SDK / runtimes)

Run these as your normal user, in order.

**NVM** (pinned `0.40.4`) + Node LTS:

```bash
curl -fsSL -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash
```

```bash
nvm install --lts
```

**SDKMAN** + Java:

```bash
curl -fsSL https://get.sdkman.io | bash
```

```bash
sdk install java 21.0.11-tem
```

**Pyenv** + Python:

```bash
curl -fsSL https://pyenv.run | bash
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
brew install dart-sdk
```

## AI tools

Need Node from NVM above first.

| Tool | Install command |
|---|---|
| Claude Code CLI | `npm install -g @anthropic-ai/claude-code` |
| Claude Desktop | `brew install --cask claude` |
| OpenCode | `npm install -g @opencode/cli`, after `npm uninstall -g opencode-ai` if version 1 is installed, because both claim the `opencode` command |
| OpenCode desktop | `brew install --cask opencode-desktop`, version 2 |
| Kilo Code CLI | `npm install -g @kilocode/cli`, which provides the `kilo` command |
| OpenSpec | `npm install -g @fission-ai/openspec` |
| ChatGPT | `brew install --cask chatgpt` |
| LM Studio | `brew install --cask lm-studio`, Apple Silicon only, macOS 12 or newer |

OpenCode version 1 instead of version 2. Version 2 is the default. The wizard switches when `Switch OpenCode from v2 to v1` is ticked on its checklist, or with `./setup.sh --enable opencode_use_v1`: it removes the version 2 command line tool and desktop app, installs version 1, and moves a data folder holding version 2 data to `~/.local/share/opencode.v2-backup-<date>-<time>`, because version 1 refuses to start on a version 2 database. Switching back moves version 1 data aside the same way and brings the newest version 2 backup back. Nothing is deleted. By hand, the same steps, first removing version 2:

```bash
brew uninstall --cask opencode-desktop
```

```bash
npm uninstall -g @opencode/cli
```

```bash
npm install -g opencode-ai
```

```bash
curl -fsSLo /tmp/opencode-desktop-v1.dmg https://github.com/anomalyco/opencode/releases/download/v1.19.1/opencode-desktop-mac-arm64.dmg
```

```bash
hdiutil attach -nobrowse /tmp/opencode-desktop-v1.dmg
```

```bash
cp -R "<mount point>/OpenCode.app" /Applications/
```

```bash
hdiutil detach "<mount point>"
```

```bash
mv ~/.local/share/opencode ~/.local/share/opencode.v2-backup-"$(date +%Y%m%d-%H%M%S)"
```

Homebrew has no version 1 cask, so version 1 comes from the vendor's DMG on the GitHub release, pinned `1.19.1`. On an Intel Mac take `opencode-desktop-mac-x64.dmg` instead. `<mount point>` is the `/Volumes/...` path `hdiutil attach` prints. The last command only when `~/.local/share/opencode` exists.

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

This is **not** in `install.sh`, because the playbook installs it from a direct DMG. Install it by hand:

- **Gridcoin** (pinned `5.5.0.0`) — download the DMG and drag the app to `/Applications`:

  ```bash
  curl -fsSLo /tmp/gridcoin.dmg https://github.com/gridcoin-community/Gridcoin-Research/releases/download/5.5.0.0/gridcoin-5.5.0.0-macos-x86_64.dmg
  ```
