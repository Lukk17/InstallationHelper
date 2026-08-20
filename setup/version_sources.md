# Version sources

Where to look up available versions for every package manager and direct-URL source this playbook touches. Use this when bumping a pin in [pinned_values.toml](pinned_values/pinned_values.toml), debugging an "I can't find that package" failure, or just confirming a vendor hasn't moved a download.

Each row gives a **browse page** (open in a browser) and an **API endpoint** (for scripts and CI checks). Where the package's identity in this repo differs from the upstream slug, both are listed.

## Pinned values file

Every pinned version, download location, filename, vendor identifier, build number and channel lives in [setup/pinned_values/pinned_values.toml](pinned_values/pinned_values.toml), not in a `group_vars/versions.yaml` any more. The file holds two TOML tables. `[pins]` carries 67 keys covering all of the above. `[checksums]` is the download verification table, empty today, so no vendor download in this repository is verified yet.

Every value in the file is a quoted string, even one that looks numeric, such as `android_api_level`. Unquoted, a two-component version such as `9.70` would arrive as a float that loses its trailing zero, and a three-component one such as `1.13.3` is not valid TOML at all. A value may reference another key in the same file with `{{ other_key }}`, and the reference always names a key inside the file itself, never a host fact, so the file resolves entirely on its own.

[setup/pinned_values/pinned_values.py](pinned_values/pinned_values.py) is the only reader and the only thing allowed to resolve a `{{ ref }}`. Ansible reaches it through a vars plugin at [setup/ansible/vars_plugins/pinned_values.py](ansible/vars_plugins/pinned_values.py), which injects every pin as a host variable so `{{ minikube_url }}` keeps working unchanged in every role. PowerShell reaches it through `setup/pinned_values/PinnedValues.psm1`, and shell scripts by sourcing `setup/pinned_values/pinned_values.sh`. Nothing else in this repository is allowed to parse the file, which `e2e/tier1/pinned_values.sh` checks for.

To read one value from a shell without writing Ansible:

```bash
python3 setup/pinned_values/pinned_values.py --get minikube_url
```

```powershell
python setup/pinned_values/pinned_values.py --get minikube_url
```

Bumping a version is not enough on its own. Once the value is updated, [e2e/tier2/resolve_pinned_urls.sh](../e2e/tier2/resolve_pinned_urls.sh) sends every download location a request to confirm the vendor still serves it there, which is what catches a version pinned past the point the release was pulled or the URL shape changed.

## Linux package managers

### `apt` — Debian / Ubuntu

| What | URL |
|---|---|
| Browse Ubuntu packages | <https://packages.ubuntu.com/> |
| Browse Debian packages | <https://packages.debian.org/> |
| Per-package detail (Ubuntu) | `https://packages.ubuntu.com/<release>/<package>` (e.g. `noble/git`) |
| Per-package detail (Debian) | `https://packages.debian.org/<release>/<package>` (e.g. `bookworm/git`) |
| Reverse search by file | <https://packages.ubuntu.com/search?searchon=contents&keywords=...> |

Direct query from a shell:

```bash
apt-cache policy <package>
```

Mapped in `vars/Debian.yaml` under `software_mapping`.

### `dnf` — Fedora

| What | URL |
|---|---|
| Browse Fedora packages | <https://packages.fedoraproject.org/> |
| Per-package detail | `https://packages.fedoraproject.org/pkgs/<package>/` |
| Koji build system (source-of-truth for release builds) | <https://koji.fedoraproject.org/koji/packages> |
| Bodhi (updates and testing) | <https://bodhi.fedoraproject.org/> |

Direct query from a shell:

```bash
dnf info <package>
```

Mapped in `vars/RedHat.yaml`.

### `pacman` — Arch Linux

| What | URL |
|---|---|
| Browse Arch official | <https://archlinux.org/packages/> |
| Per-package detail | `https://archlinux.org/packages/<repo>/<arch>/<package>/` |
| JSON API | `https://archlinux.org/packages/search/json/?name=<package>` |
| Group listing | <https://archlinux.org/groups/> |

Direct query from a shell:

```bash
pacman -Si <package>
```

Mapped in `vars/Archlinux.yaml` under `manager: pacman`.

### AUR — Arch User Repository

| What | URL |
|---|---|
| Browse AUR | <https://aur.archlinux.org/packages> |
| Per-package detail | `https://aur.archlinux.org/packages/<package>` |
| RPC JSON API (`info`) | `https://aur.archlinux.org/rpc/?v=5&type=info&arg=<package>` |
| RPC JSON API (`search`) | `https://aur.archlinux.org/rpc/?v=5&type=search&arg=<keyword>` |

AUR builds need `yay` or `paru`, both built earlier in the playbook. Entries marked `manager: aur` in `vars/Archlinux.yaml`.

### `flatpak` — Flathub

| What | URL |
|---|---|
| Browse apps | <https://flathub.org/apps> |
| Per-app detail | `https://flathub.org/apps/<app-id>` (e.g. `org.mozilla.firefox`) |
| JSON API | `https://flathub.org/api/v2/appstream/<app-id>` |
| Search API | `https://flathub.org/api/v2/search` |
| Runtime browser | <https://flathub.org/apps/runtimes> |

Runtime versions and GL extensions (e.g. `org.freedesktop.Platform.GL.default//24.08`) are pulled in by app declarations — don't bump these manually, they follow the app.

### `snap` — Snapcraft

| What | URL |
|---|---|
| Browse snaps | <https://snapcraft.io/store> |
| Per-snap detail | `https://snapcraft.io/<snap-name>` |
| JSON API (info) | `https://api.snapcraft.io/v2/snaps/info/<snap-name>` (requires `Snap-Device-Series: 16` header) |

Direct query from a shell:

```bash
snap info <snap-name>
```

## macOS

### `brew` and `brew_cask` — Homebrew

| What | URL |
|---|---|
| Browse formulae | <https://formulae.brew.sh/formula/> |
| Browse casks | <https://formulae.brew.sh/cask/> |
| Per-formula JSON | `https://formulae.brew.sh/api/formula/<formula>.json` |
| Per-cask JSON | `https://formulae.brew.sh/api/cask/<cask>.json` |
| All formulae (single dump) | <https://formulae.brew.sh/api/formula.json> |
| All casks (single dump) | <https://formulae.brew.sh/api/cask.json> |

Direct query from a shell:

```bash
brew info <formula-or-cask>
```

Mapped in `vars/Darwin.yaml` under `manager: brew` or `manager: brew_cask`.

### MAS — Mac App Store

| What | URL |
|---|---|
| App identifier search | <https://apps.apple.com/> (search and read the ID from the URL) |
| `mas` CLI search | `mas search <name>` (CLI returns IDs) |

## Windows

### `choco` — Chocolatey

| What | URL |
|---|---|
| Browse packages | <https://community.chocolatey.org/packages> |
| Per-package detail | `https://community.chocolatey.org/packages/<id>` |
| NuGet OData API | `https://community.chocolatey.org/api/v2/Packages()?$filter=Id%20eq%20%27<id>%27` |
| Latest version shortcut | `https://community.chocolatey.org/api/v2/package/<id>` (302 redirects to the `.nupkg`) |

Direct query from a shell:

```powershell
choco info <id>
```

Mapped in `vars/Windows.yaml` under `manager: choco`.

### `winget` — Windows Package Manager

| What | URL |
|---|---|
| Browse community manifest | <https://github.com/microsoft/winget-pkgs/tree/master/manifests> |
| Third-party search UI | <https://winstall.app/> |
| Manifest source path | `manifests/<letter>/<Publisher>/<Package>/` |
| Microsoft Store search | <https://apps.microsoft.com/> |

Direct query from a shell:

```powershell
winget show <id>
```

Mapped in `vars/Windows.yaml` under `manager: winget`.

## Language runtimes and SDK managers

### `pip` / PyPI

| What | URL |
|---|---|
| Browse packages | <https://pypi.org/> |
| Per-package detail | `https://pypi.org/project/<package>/` |
| JSON API | `https://pypi.org/pypi/<package>/json` |

### `pyenv` Python releases

`pyenv install` downloads from python.org, not PyPI. The version string in `pinned_values.toml` must match an exact `Python-<X.Y.Z>.tar.xz` filename.

| What | URL |
|---|---|
| Python release index | <https://www.python.org/ftp/python/> |
| Per-version listing | `https://www.python.org/ftp/python/<X.Y.Z>/` |
| Active releases overview | <https://devguide.python.org/versions/> |

Direct query from a shell:

```bash
pyenv install --list
```

### `npm` / npm registry

| What | URL |
|---|---|
| Browse | <https://www.npmjs.com/> |
| Per-package detail | `https://www.npmjs.com/package/<package>` (including scoped like `@anthropic-ai/claude-code`) |
| Latest JSON | `https://registry.npmjs.org/<package>/latest` |
| All versions | `https://registry.npmjs.org/<package>` |

### `nvm` Node releases

`nvm install --lts` floats to the current Node LTS, no version pin needed in `pinned_values.toml`. The pin we DO keep is the nvm installer itself:

| What | URL |
|---|---|
| nvm releases | <https://github.com/nvm-sh/nvm/releases> |
| Node release index | <https://nodejs.org/en/about/previous-releases> |
| Node `dist` JSON | <https://nodejs.org/dist/index.json> |

### `SDKMAN` — JVM ecosystem (Java, Kotlin, Gradle, ...)

| What | URL |
|---|---|
| Browse candidates | <https://sdkman.io/jdks> |
| Java vendor matrix | <https://sdkman.io/jdks> |
| JSON API (per-platform list) | `https://api.sdkman.io/2/candidates/java/linuxx64/versions/list?installed=` |
| JSON API (other candidates) | `https://api.sdkman.io/2/candidates/<candidate>/<platform>/versions/list?installed=` |

Direct query from a shell:

```bash
sdk list java
```

The Temurin identifiers we use (e.g. `21.0.11-tem`) come from the `linuxx64` table — Adoptium publishes them and Apple Silicon mac uses `darwinarm64`, Intel mac uses `darwinx64`.

### `Dart` SDK

`pyenv` and `nvm` have their own version listings; Dart hosts releases on Google Cloud Storage.

| What | URL |
|---|---|
| Release page | <https://dart.dev/get-dart/archive> |
| Per-channel directory | `https://storage.googleapis.com/dart-archive/channels/<stable\|beta\|dev>/release/` |
| Per-version file | `https://storage.googleapis.com/dart-archive/channels/stable/release/<X.Y.Z>/sdk/dartsdk-linux-x64-release.zip` |

### `FVM` — Flutter Version Management

`fvm install <channel>` accepts a flutter channel (`stable`, `beta`, `dev`, `main`) or an exact version. Channels float.

| What | URL |
|---|---|
| Flutter SDK archive | <https://docs.flutter.dev/install/archive> |
| FVM releases | <https://github.com/leoafarias/fvm/releases> |

### Android `cmdline-tools`

Google doesn't publish a JSON index for the cmdline-tools. The `_latest.zip` URL embeds a build number that has to be looked up manually:

| What | URL |
|---|---|
| Studio + tools download page (look for "Command line tools only") | <https://developer.android.com/studio> |
| Repository XML index (machine-readable) | <https://dl.google.com/android/repository/repository2-3.xml> |

## Ansible

### Ansible Galaxy collections

| What | URL |
|---|---|
| Browse collections | <https://galaxy.ansible.com/ui/collections/> |
| Per-collection detail | `https://galaxy.ansible.com/ui/repo/published/<namespace>/<name>/` (e.g. `community/general`) |
| Per-collection JSON | `https://galaxy.ansible.com/api/v3/plugin/ansible/content/published/collections/index/<namespace>/<name>/` |
| Per-version JSON | `https://galaxy.ansible.com/api/v3/plugin/ansible/content/published/collections/index/<ns>/<name>/versions/<version>/` |

Direct query from a shell:

```bash
ansible-galaxy collection list
```

Pinned in `requirements.yaml`.

### Ansible core (and the PR #86739 watch list)

| What | URL |
|---|---|
| Releases | <https://github.com/ansible/ansible/releases> |
| PR #86739 (the 2.19 deserialization bug fix) | <https://github.com/ansible/ansible/pull/86739> |
| Per-branch release notes | `https://docs.ansible.com/ansible-core/<minor>/release_and_maintenance.html` |

`AGENTS.md` lists the mandatory recheck steps before reverting the `raw:` workarounds.

## Generic vendor channels

### GitHub releases

Most direct-URL software (Trezor Suite, Lutris, Veracrypt, Minikube, Kind, Etcher, NVM, AppImageLauncher, Gridcoin, JetBrains' rolling tarball) ships through GitHub releases.

| What | URL |
|---|---|
| Per-repo releases page | `https://github.com/<owner>/<repo>/releases` |
| Latest release JSON | `https://api.github.com/repos/<owner>/<repo>/releases/latest` |
| Specific tag JSON | `https://api.github.com/repos/<owner>/<repo>/releases/tags/<tag>` |
| Tag download URL | `https://github.com/<owner>/<repo>/releases/download/<tag>/<asset>` |

### Direct vendor URLs (no API)

A few vendors publish a "latest" alias that we point at:

| Vendor | Latest alias |
|---|---|
| Ledger Live (Linux AppImage) | <https://download.live.ledger.com/latest/linux> |
| Aurora Store | <https://auroraoss.com/downloads/AuroraStore/Latest/latest.apk> |
| JetBrains Toolbox (Linux) | <https://data.services.jetbrains.com/products/download?platform=linux&code=TBA> |
| Anthropic Claude Desktop | <https://claude.com/download> (currently macOS + Windows only; Linux build not published) |
| Google Antigravity (Linux tarball) | <https://antigravity.google/download> |

If a vendor switches the alias format, the entry in `pinned_values.toml` needs a real update, and the playbook can't follow a moved redirect on its own.

## Quick rerun

[e2e/tier2/resolve_pinned_urls.sh](../e2e/tier2/resolve_pinned_urls.sh) re-runs the one check a browse page cannot give you: whether every pinned download location still resolves. It says nothing about whether a version is the newest available, only that the URL built from it still answers. The manual flow for bumping a version is:

1. Open the relevant browse page from this doc.
2. Look up the package or version you're bumping.
3. Update the entry in [setup/pinned_values/pinned_values.toml](pinned_values/pinned_values.toml).
4. Run a syntax check:

```bash
ansible-playbook --syntax-check setup/ansible/site.yaml -i localhost, -c local
```

PowerShell equivalent:

```powershell
wsl -d Ubuntu bash -c "ansible-playbook --syntax-check /mnt/d/Development/projekty-IT/InstallationHelper/setup/ansible/site.yaml -i localhost, -c local"
```

5. If the bump touched a download location, confirm the vendor still serves it:

```bash
./e2e/run.sh --tier 2
```

## Catalogue of what we install

The authoritative per-OS mapping lives in `setup/ansible/vars/{Debian,RedHat,Archlinux,Darwin,Windows}.yaml`. The human-readable catalogue is `setup/software.md`.
