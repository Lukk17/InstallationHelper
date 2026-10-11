## Purpose

Defines how the desktop application is packaged, released and installed from the GitHub releases of Lukk17/InstallationHelper, so a user on Windows, Linux or macOS can download one file and start the application with every runtime library it needs inside that file.

## ADDED Requirements

### Requirement: Every artifact carries its runtime and the scripts of its own release

Every artifact SHALL contain the Flutter runtime, every Dart and native library the application loads, and a payload archive of the whole `setup/` directory, the KDE profile and the wallpapers included, produced by `git archive` from the commit the release tag points at, plus a manifest recording the tag, the commit and the SHA-256 of the archive. Nothing is downloaded at first start except what the Flatpak runtime itself needs and what the user explicitly asks the prerequisite screen to install.

#### Scenario: Payload matches the tag

- WHEN the application built for tag `vX.Y.Z` shows its About screen
- THEN it shows `vX.Y.Z` and the commit hash the tag points at
- AND the payload's SHA-256 equals the value in the manifest

### Requirement: The payload is unpacked to a per-user, per-version, writable directory the host can see

At first start of a version the application SHALL unpack the payload into `<user data>/InstallationHelper/scripts/<version>/`, where `<user data>` is `%LOCALAPPDATA%` on Windows, `~/Library/Application Support` on macOS and `$XDG_DATA_HOME`, or `~/.local/share` when unset, on Linux, which inside the Flatpak resolves to a path under `~/.var/app/` that is also valid on the host. It MUST verify the SHA-256 before unpacking, unpack into a temporary sibling directory and rename it into place, and reuse an existing directory only when its recorded checksum matches. It MUST keep only the current version's directory and delete older ones after a successful unpack.

#### Scenario: Upgrade to a new version

- WHEN version `vX.Y.Z` starts for the first time on a machine that has `scripts/vX.Y.W/`
- THEN `scripts/vX.Y.Z/setup/setup.sh` exists, `scripts/vX.Y.W/` is gone, and the run uses the new directory

#### Scenario: Corrupted payload

- WHEN the payload checksum does not match the manifest
- THEN the application refuses to run anything and says the download is damaged

### Requirement: Windows artifacts

The release SHALL attach for Windows x64 an Inno Setup installer, a portable zip that runs from any folder after extraction, and the winget manifest files for that installer with its SHA-256. The installer SHALL install for all users by default, into the machine-wide programs folder, and SHALL let the user choose the current user only, both in an install mode dialog and with the `/CURRENTUSER` command-line switch, with `/ALLUSERS` selecting all users without the dialog. It MUST ask for administrator rights only for an all-users install and only while installing. The installed application MUST still request `asInvoker` and run as the normal user in either mode, and MUST start on a fresh Windows 11 with no other runtime installed. The winget manifest SHALL offer both a `machine` and a `user` scope entry for the same installer.

#### Scenario: Install for all users

- WHEN a normal user double-clicks the installer and keeps the all-users choice
- THEN Windows shows one User Account Control prompt for the installer
- AND the application is installed under the machine-wide programs folder
- AND the application started from the installer's last page runs without elevation

#### Scenario: Install for the current user only

- WHEN the installer runs with `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CURRENTUSER` as a normal user
- THEN it exits 0 without a User Account Control prompt
- AND the application is installed under `%LOCALAPPDATA%\Programs\Installation Helper` and starts

#### Scenario: Silent install for the smoke test

- WHEN the installer runs with `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /ALLUSERS` and, after uninstalling, with `/CURRENTUSER` on `windows-latest`
- THEN it exits 0 both times and the installed application passes its self-test both times

#### Scenario: Local winget manifest

- WHEN an administrator has run `winget settings --enable LocalManifestFiles` and the user runs `winget install --manifest <folder> --scope machine` or `--scope user`
- THEN winget installs the same installer in the matching mode and verifies its SHA-256

### Requirement: Linux artifacts

The release SHALL attach for Linux x86_64 a `.tar.gz` of the application bundle, an AppImage, a Flatpak single-file bundle whose manifest names the Flathub runtime repository, and a classic Snap. The tar archive and the AppImage MUST start on fresh desktop installs of Ubuntu 24.04, Ubuntu 26.04, Fedora 44 Workstation and Debian 13 with no extra package. The CachyOS and Arch Linux results MUST be measured and documented before the first release states support for them.

#### Scenario: AppImage on Ubuntu 26.04

- WHEN the AppImage is made executable and started on a fresh Ubuntu 26.04 desktop
- THEN the application window opens
- AND when no setuid `fusermount` is available, starting it with `--appimage-extract-and-run` also opens the window, which the README documents

#### Scenario: Flatpak bundle

- WHEN the user runs `flatpak install --user <bundle>.flatpak` on a machine with Flatpak
- THEN Flatpak fetches the runtime from Flathub and the application starts with `flatpak run io.github.lukk17.InstallationHelper`
- AND a run executes `setup.sh` on the host, not inside the sandbox

#### Scenario: Classic Snap

- WHEN the user runs `sudo snap install --dangerous --classic ./installation-helper_<version>_amd64.snap`
- THEN the application starts with `installation-helper` and draws its window with the GTK it bundles

### Requirement: macOS artifacts

The release SHALL attach a universal (arm64 and x86_64) `.app` inside a `.dmg` and inside a `.zip`. The app MUST be ad hoc signed, MUST NOT enable the App Sandbox entitlement, and MUST start after the user approves it once under System Settings, Privacy and Security, Open Anyway. A cask named `installation-helper` SHALL live in `Casks/installation-helper.rb` at the top level of this repository, which is the Homebrew tap `Lukk17/installationhelper`, and SHALL point at the release's `.zip` with its SHA-256. No second repository SHALL be created for the tap. The tap command MUST be `brew tap Lukk17/installationhelper https://github.com/Lukk17/InstallationHelper`, with the URL and without a `-tap` suffix, and the install command MUST be `brew install --cask Lukk17/installationhelper/installation-helper`, the fully qualified name, so the user trusts only this cask and not the whole tap. `Casks/installation-helper.rb` MUST equal the template `desktop/packaging/homebrew/installation-helper.rb` except for its `version` and `sha256` lines, and the repository root MUST hold no `.rb` file, both enforced by a tier 1 check.

#### Scenario: Install through the tap

- WHEN the user runs `brew tap Lukk17/installationhelper https://github.com/Lukk17/InstallationHelper` and then `brew install --cask Lukk17/installationhelper/installation-helper`
- THEN the app is in `/Applications` and starts after Open Anyway

#### Scenario: Short tap command without the URL

- WHEN the user runs `brew tap Lukk17/installationhelper` without the URL
- THEN the command fails, because no `Lukk17/homebrew-installationhelper` repository exists, and the README warns about exactly this next to the tap command

#### Scenario: Committed cask drifts from its template

- WHEN `Casks/installation-helper.rb` differs from the template in any line other than `version` and `sha256`, or a `.rb` file is added to the repository root
- THEN `bash e2e/run.sh` fails and names the file and the line

### Requirement: Releases are built only on explicit dispatch

The release workflow SHALL declare `workflow_dispatch` as its only trigger, take the release tag as an input, refuse a tag that is not `vX.Y.Z` or that differs from the application version, build every artifact from that tag, run the smoke test of each artifact on a runner of its platform, and attach the artifacts to a draft release for that tag. It SHALL also attach `installation-helper.rb`, the cask template filled with the tag's version and the SHA-256 of the macOS zip it built, so the owner can commit it to `Casks/installation-helper.rb` on `master` after publishing. It MUST NOT publish the release, commit or push to any repository, this one included, open a pull request, or start on push, tag push, schedule or any other automatic event. A tier 1 check MUST fail when any workflow in the repository declares a trigger other than `workflow_dispatch` or `workflow_call`.

#### Scenario: Automatic trigger added by mistake

- WHEN a workflow file gains `on: push`
- THEN `bash e2e/run.sh` fails and names the file and the trigger

#### Scenario: Tag and version disagree

- WHEN the workflow is dispatched with tag `v0.2.0` while `desktop/pubspec.yaml` says version `0.1.0`
- THEN the first job fails, names both values, and nothing is built

#### Scenario: Cask prepared, not committed

- WHEN the workflow finishes for tag `v0.2.0`
- THEN the draft release carries `installation-helper.rb` with `version "0.2.0"` and the SHA-256 of `installation-helper-0.2.0-macos-universal.zip`, and the repository has no new commit from the workflow

#### Scenario: One artifact fails its smoke test

- WHEN the AppImage smoke test fails
- THEN no artifact is attached to the release and the job log names the failing artifact

### Requirement: A signed Flatpak repository on GitHub Pages

The repository SHALL publish, on its GitHub Pages site, an OSTree repository holding the Flatpak of the newest published release, signed with a GPG key the owner generated, an Ed25519 signing key with the user id `Lukk17 <luksarna@gmail.com>` and no expiry date, plus a `.flatpakrepo` file and a `.flatpakref` file that carry the base64-encoded public key. The private key MUST exist only with the owner and as the GitHub Actions secrets `FLATPAK_GPG_PRIVATE_KEY` and `FLATPAK_GPG_PASSPHRASE` on the `github-pages` environment, never in the repository, a log or an artifact. The public key MUST be committed. The deployment SHALL run in its own workflow whose only trigger is `workflow_dispatch`, SHALL take the release tag as input, MUST refuse a release that is still a draft, MUST import the `.flatpak` asset of that release rather than build again, and MUST fail when the imported key's fingerprint differs from the committed public key. The site MUST stay under the 1 GB GitHub Pages size limit, and the deployment MUST fail before uploading when it is not. The single-file bundle of the Linux artifacts requirement stays. The revocation certificate of the key MUST exist only with the owner, offline, and `desktop/README_DESKTOP.md` SHALL document how the key is revoked and replaced and the commands users run to remove and re-add the remote afterwards.

#### Scenario: Install from the remote

- WHEN a user on a machine with Flatpak and the Flathub remote runs `flatpak remote-add --user --if-not-exists installation-helper https://lukk17.github.io/InstallationHelper/installation-helper.flatpakrepo` and then `flatpak install --user installation-helper io.github.lukk17.InstallationHelper`
- THEN Flatpak verifies the signature with the key from the `.flatpakrepo` file and installs the application

#### Scenario: Update after a new release

- WHEN the owner publishes a newer release and dispatches the Pages workflow for its tag
- THEN `flatpak update` on a machine that installed from the remote installs the newer version

#### Scenario: Draft release

- WHEN the Pages workflow is dispatched for a tag whose release is still a draft
- THEN it fails, names the draft, and deploys nothing

#### Scenario: Signing key replaced after a leak

- WHEN the owner has revoked the old key, made a new one, replaced both secrets and committed the new public key, and dispatches the Pages workflow
- THEN the site's `.flatpakrepo` and `.flatpakref` carry the new public key
- AND a user who removes the remote with `flatpak remote-delete --user --force installation-helper` and adds it again receives updates verified with the new key

#### Scenario: Wrong signing key

- WHEN the secret holds a key whose fingerprint differs from the committed public key
- THEN the workflow fails before signing anything and names both fingerprints

### Requirement: Every artifact passes a smoke test before release

Each artifact SHALL be installed or unpacked on a clean runner of its platform the way the README tells a user to, and the application started with `--self-test`. In that mode the application MUST unpack its payload, run the wizard's JSON listing, decode it with the same strict decoder a normal start uses, write a report, and exit 0 only when every step succeeded, without installing any software.

#### Scenario: Self-test on the Windows runner

- WHEN the installed application runs `--self-test --report <path>` on `windows-latest`
- THEN it exits 0 and the report lists the payload version, the toggle count and the decoder result

### Requirement: The README explains every install route

The repository README.md SHALL contain a section "Install the desktop app" with, for every artifact, the download, the install command and the start command, one command per code block, with a PowerShell form for Windows and a Unix shell form for Linux and macOS. It MUST explain the macOS Open Anyway steps, link https://brew.sh for Macs without Homebrew, give the tap command with its URL and the fully qualified install command of the macOS artifacts requirement and warn that the tap command fails without the URL, explain the AppImage `fusermount` fallback, state that the Flatpak has host access and is not sandboxed, give the commands that add the signed Flatpak remote and install from it, state that the Snap is classic and installed with `--dangerous`, and state that the Windows installer installs for all users by default with `/CURRENTUSER` as the alternative. It MUST explain in plain words that the user never sees a terminal, how the application asks for the sudo password on Linux and macOS through its own dialog, and how Windows asks for administrator rights through its own User Account Control prompt.

#### Scenario: Reader on macOS without Homebrew

- WHEN a reader follows the macOS tap route on a Mac without Homebrew
- THEN the section links https://brew.sh before the `brew tap` command
