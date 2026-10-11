## Context

See [proposal.md](proposal.md) for why. The behaviour contracts are in [specs/desktop-app/spec.md](specs/desktop-app/spec.md), [specs/wizard-machine-output/spec.md](specs/wizard-machine-output/spec.md) and [specs/desktop-distribution/spec.md](specs/desktop-distribution/spec.md). This document carries the research and the technical decisions, so an implementer does not have to look anything up. Every external fact below was measured on 2026-10-10 by the command or page named next to it, or was given by the owner in the decision list of 2026-10-10, and says which. Facts added on 2026-10-11, together with the owner's answers to the open questions given that day, say so next to them. Where something could not be established it says so.

### What the two wizards already offer, read from the code

[setup/setup.sh](../../../setup/setup.sh), 1563 lines, documents its options in its header, lines 5 to 49:

| Option | What it does | Where |
|---|---|---|
| `--non-interactive` | group_vars defaults, no prompts | parse_args, line 194 |
| `--profile <name>` | applies `setup/ansible/profiles/<name>.yaml`, refused with `--software` | lines 192, 239 |
| `--desktop-environment skip\|kde\|gnome` and `--desktop-action full\|install\|configure` | screen 1 choices, the action needs kde or gnome | lines 198 to 231 |
| `--software defaults\|all\|none`, `--enable <keys>`, `--disable <keys>` | the checklist without the checklist, `--disable` wins, unknown keys exit 2 | software_override_vars line 851, assert_known_keys line 826 |
| `--list-software` | prints `%-32s %-4s %s` per toggle: key, ON or OFF, label | list_software line 883 |
| `--print-command` | prints the resolved `ansible-playbook` command and exits | line 1529 |
| `--verify-only` | runs only the verification | line 1545 |
| `--skip-system-upgrade`, `--no-color`, `--passwordless-sudo` | as named | lines 195 to 197 |

Exit codes: 0 success, 1 bootstrap or playbook failure, 2 bad usage, 3 playbook succeeded and the verification found something missing, 130 cancelled (header lines 43 to 48).

The order of the entrypoint matters to the application, lines 1475 to 1563: `parse_args`, then the root refusal at line 1485 ("ERROR: Do not run this script as root or with sudo. Run it as your normal user: ./setup.sh. It asks for your sudo password itself when a step needs it."), `check_requirements`, `detect_os`, `preload_toggles`, then `--list-software` exits, then `validate_selection_options`, then `--print-command` exits, then `prepare_become_password` at line 1526, then Ansible, the system upgrade and the run. So listing and preview never ask for a password and never change the machine, which is what the application relies on.

`prepare_become_password`, line 1406, first asks `sudo -n -k true`, and a machine with passwordless sudo is never asked. Otherwise it prints `  [sudo] password for <user>: ` with `read -r -s -p`, up to three tries, proves each with `printf '%s\n' "${password}" | sudo -S -k -p '' true`, and on success writes the password into a mode 0600 file in a `mktemp -d` directory that an EXIT trap removes, handing Ansible `--become-password-file`. The script's own `sudo` calls outside Ansible, for example `sudo apt-get` in `ensure_prereqs` line 584 and the system upgrade at line 535, use plain `sudo`, which can ask again with sudo's own prompt, because `-k` on the proving call does not leave a cached credential. The application therefore has to handle more than one password prompt per run. That is decision 7.

`offer_reboot`, line 1079, asks `Reboot now? [y/N] ` only when standard input is a terminal, not on macOS and not in a container. Inside the application's hidden pseudo terminal standard input is a terminal, so the question will appear. Decision 7 turns it into Yes and No buttons.

On macOS the script needs bash 4 before any of the above, lines 71 to 84: it searches `/opt/homebrew/bin/bash`, `/usr/local/bin/bash` and `PATH`, re-execs into the first bash 4 or newer, and otherwise exits 2 telling the user to `brew install bash`. A fresh Mac has only `/bin/bash` 3.2, so even `--list-software` fails there. Decision 10.

[setup/setup.ps1](../../../setup/setup.ps1), 1497 lines, `#Requires -Version 7` on line 2, parameters at lines 78 to 97: `-Profile` (accepted, does nothing on Windows and says so), `-NonInteractive`, `-NoColor`, `-SkipSystemUpgrade`, `-Software defaults|all|none`, `-EnableKey`, `-DisableKey`, `-ListSoftware`, `-PrintPlan`, `-AllowAdministrator`, plus `-WhatIf` from `SupportsShouldProcess`. `Invoke-Main`, line 1384, calls `Assert-NotAdmin` first (line 603), then builds the list with `Get-SelectableToggle` (line 984, all.yaml and windows.yaml, state through `Get-WindowsGroupVarToggle`), answers `-ListSoftware` with `Show-SoftwareList` (line 1111, same `{0,-32} {1,-4} {2}` format as bash), refuses unknown keys with exit 2, answers `-PrintPlan`, and only then upgrades and installs. Every elevated step elevates itself with `Start-Process -Verb RunAs`, in [setup/windows/WindowsSettings.ps1](../../../setup/windows/WindowsSettings.ps1) line 263 and [setup/windows/WindowsSoftware.ps1](../../../setup/windows/WindowsSoftware.ps1) line 632. The non-interactive path has no `Read-Host`, so the application never has to answer a Windows prompt other than User Account Control, which Windows shows itself. Exit codes: 0, 1 any item failed, 2 bad usage, 3 verification found something missing.

Both wizards hide the same keys from the checklist (`EXCLUDED_VARS` in setup.sh line 124, `$ExcludedVars` in setup.ps1 line 128), and [e2e/tier1/wizard_parse.sh](../../../e2e/tier1/wizard_parse.sh) already fails when they disagree. [e2e/tier1/list_software.sh](../../../e2e/tier1/list_software.sh) already proves the text listing names exactly the toggles group_vars declares.

The verification reports are human tables. Unix: [setup/ansible/verify_install.yaml](../../../setup/ansible/verify_install.yaml) lines 932 to 953 print `[verify] %-30s %-14s %s` rows with verdicts `installed`, `MISSING`, `not requested`, `UNREACHABLE` and `UNREACHABLE (login shell only)` (line 910), which `run_verification` in setup.sh lifts out of `~/installation_verify.log` with awk. Windows: `Invoke-WindowsVerification` in [setup/windows/WindowsVerify.ps1](../../../setup/windows/WindowsVerify.ps1) line 212 returns objects with `Key`, `Source`, `Package`, `Verdict`, `Detail` (line 282) and verdicts including `installed`, `MISSING`, `UNVERIFIABLE`, `not requested`, `not applicable`.

### Constraints from this repository

1. One source of truth. The application must not read group_vars, keep a toggle list, or decide anything the wizards decide. Defect classes 2 and 7 in [AGENTS.md](../../../AGENTS.md).
2. No workflow may start on an automatic event, quoted from the header of [.github/workflows/e2e-manual.yaml](../../../.github/workflows/e2e-manual.yaml): "No workflow in this repository may start on push or on any other automatic event".
3. Never elevated. Running per-user installs elevated puts them into the wrong profile. [docs/regression_ledger.md](../../../docs/regression_ledger.md) records Tor Browser as a `Scope: user` winget package installed to `Desktop\Tor Browser` (line 1055), Spotify refusing "The installer cannot be run from an administrator context" (line 1871), and Bruno's per-user installer crashing when run elevated (line 1979).
4. The scripts directory is large. `git archive --format=tar.gz HEAD setup | wc -c` printed 29945449 on 2026-10-10. Without [setup/config/](../../../setup/config/) and [setup/wallpapers/](../../../setup/wallpapers/) it is 308579. [setup/config/lukk_desktop_profile.knsv](../../../setup/config/lukk_desktop_profile.knsv) is 18 MB and the wallpapers 13 MB, and the playbook reads both through relative paths, so they cannot simply be dropped. The owner decided on 2026-10-11 to bundle the whole `setup/` directory, KDE profile and wallpapers included (answer 1 under Open Questions).
5. Every change under `setup/` runs the tier 1 gate, and the table in [AGENTS.md](../../../AGENTS.md) adds container scenarios for `setup.sh`, `verify_install.yaml` and the Windows wizard. Decision 14 maps them.

## Goals / Non-Goals

Goals:

- One application code base, three desktop platforms, every format the owner listed.
- The application is a thin, replaceable shell over the wizards. Deleting [desktop/](../../../desktop/) must leave the wizards exactly as capable as they are today.
- Every external dependency sits behind a small interface, so the pseudo terminal package can be replaced without touching screens or domain code.
- The user never sees a terminal. The run is shown as a progress list, and every question the wizard asks is a dialog or a button in the application.
- Every artifact is launched on a real runner before it is attached to a release.

Non-Goals:

- Store submissions: Microsoft Store, Flathub, Snap Store, Mac App Store, Homebrew's official cask repository.
- Code signing and notarisation on any platform.
- Linux and Windows on arm64. Linux and Windows ship x86_64 only, macOS ships a universal binary.
- Automatic updates inside the application. A new version is a new download.
- The interactive gum and Out-ConsoleGridView screens. The application uses only the non-interactive options.
- Remote machines. The application configures the machine it runs on.
- A terminal emulator, a terminal widget, or any screen where the user types into the wizard directly.
- Adding Snap and Flatpak makers to Fastforge upstream. This would be a useful later contribution to https://github.com/fastforgedev/fastforge, and the snapcraft.yaml and Flatpak manifest written here would be the starting point, but it is out of scope now.

## How the app asks for passwords and administrator rights

This section is for the owner. It says in plain words what happens on screen. Decisions 7 and 8 hold the technical detail.

You never see a terminal, on any platform. The app shows a list of steps and packages, each with its status, and asks every question in its own window.

On Linux and macOS:

1. The app runs `setup.sh` as the normal user, never as root. It connects to the script through a hidden pseudo terminal, which is a connection the script sees as a terminal but which the app never shows. The script needs it because it reads the sudo password from a terminal. To `setup.sh` this looks exactly like a normal terminal, so the script behaves as it does when you start it by hand.
2. While the script runs, the app shows a progress list: one row per step and per package, each with its status: running, installed, skipped with the reason, or failed with the reason. At the end it shows the summary.
3. When the script needs administrator rights, it prints its own prompt, `[sudo] password for <user>:`, on the hidden connection. Later in the same run `sudo` itself can print the same prompt again, and on macOS `sudo` prints `Password:`.
4. The app recognises the prompt and shows its own password dialog: a password field, OK and Cancel.
5. When you press OK, the app writes what you typed to the hidden connection, exactly as if you had typed it into a terminal. The app never stores or logs the password: not in a file, not in the log files, not in its settings, and it drops it from memory as soon as it is written.
6. One run can ask more than once, so each new prompt opens the dialog again. After a wrong password the dialog opens again with the message that the password was not accepted.
7. When you press Cancel in the password dialog, the app stops the run cleanly and the summary says the run was cancelled at the password question.
8. When the script asks `Reboot now?` at the end, the app shows Yes and No buttons.
9. If the script ever asks something the app does not know, the app does not wait silently. It shows the question in a dialog with a text field for the answer and a button that stops the run. Decision 7 has the details.
10. The full text the script printed is kept in memory and in the log files on disk. A "Show details" button shows it as plain text you can read and copy but not type into.

On Windows:

1. The app starts `setup.ps1` as the normal user, never as administrator.
2. Each step that needs administrator rights asks Windows for them itself. Windows shows its standard administrator permission prompt (User Account Control), the same prompt you see when you install any program. One run can show this prompt several times, once per step that needs it.
3. If your account is an administrator, the prompt asks you to confirm. If it is a standard account, Windows asks for the administrator's password in its own prompt.
4. The app never sees, handles or stores an administrator password on Windows. It has no password dialog there at all.
5. If you refuse the prompt, that step fails, the script reports it, and the summary screen shows it.
6. The progress list, the "Show details" button and the summary are the same as on Linux and macOS.

Tasks 6.10 and 6.11 hold the acceptance checks for both flows.

## Decisions

### Decision 1: The project lives in a new top-level directory, `desktop/`

The Flutter project root is [desktop/](../../../desktop/), with `desktop/pubspec.yaml` at its top. The repository already has three top-level parts with one job each, `setup/`, `local-dev/` and `homelab/`, listed in "What This Repo Is" in [AGENTS.md](../../../AGENTS.md), and the application is a fourth part that consumes `setup/`.

Alternatives rejected:

1. `setup/desktop/` or `setup/gui/`. The application bundles `setup/` as its payload, so living inside it would put the application inside its own payload, and every tier 1 check that walks `setup/` (shell syntax, toggle coverage, line endings, control characters) would start walking Dart code and generated build output.
2. A separate repository. The scripts and the application must be released from the same commit so the payload matches the tag, and two repositories make that a manual promise instead of a fact.

Layout:

```text
desktop/
  pubspec.yaml                 package installation_helper, Flutter pinned in environment.flutter
  analysis_options.yaml
  README_DESKTOP.md            hub page for the directory
  lib/
    main.dart                  composition root and argument parsing (--self-test, --allow-administrator, --report)
    domain/                    immutable models and pure logic, no Flutter or dart:io imports
    ports/                     abstract interfaces
    adapters/                  dart:io, pseudo terminal, payload, platform probes
    ui/                        screens and widgets
  test/                        unit and widget tests
  integration_test/            tests that start real processes
  tool/build_payload.dart      writes assets/payload/setup.tar.gz and manifest.json from git archive
  assets/payload/              generated, listed in desktop/.gitignore
  windows/ linux/ macos/       Flutter platform runners, plus Fastforge configs under */packaging/
  packaging/
    flatpak/io.github.lukk17.InstallationHelper.yaml
    flatpak/io.github.lukk17.InstallationHelper.metainfo.xml
    flatpak/installation-helper.gpg           public signing key of the Flatpak repository, never the private key
    flatpak/installation-helper.flatpakrepo   template, GPGKey filled from the public key by the Pages workflow
    flatpak/installation-helper.flatpakref    template, same
    snap/snapcraft.yaml
    winget/                    manifest templates
    homebrew/installation-helper.rb   cask template, filled by the release workflow, decision 12.5
  distribute_options.yaml      Fastforge release definitions
```

One path outside [desktop/](../../../desktop/) belongs to the application as well: `Casks/installation-helper.rb` at the top level of this repository, the live cask of the Homebrew tap (decision 12.5). It does not exist until the follow-up commit of the first published release creates it.

Identifiers, used everywhere and decided here once:

| Thing | Value |
|---|---|
| Dart package | `installation_helper` |
| Display name | `Installation Helper` |
| Flatpak and Linux application id | `io.github.lukk17.InstallationHelper` |
| macOS bundle id | `io.github.lukk17.InstallationHelper` |
| Snap name | `installation-helper` |
| winget PackageIdentifier | `Lukk17.InstallationHelper` |
| Homebrew cask token | `installation-helper` |
| Homebrew tap | `Lukk17/installationhelper`, tapped from this repository with its URL, the cask in `Casks/installation-helper.rb` (decision 12.5) |
| Flatpak remote name | `installation-helper` |
| Flatpak repository site | `https://lukk17.github.io/InstallationHelper/`, the GitHub Pages project site of this repository, with the repository itself under `repo/` |
| Inno Setup AppId | a GUID generated once with `[guid]::NewGuid()` in task 6.1 and never changed afterwards |

### Decision 2: A layered application with every outside dependency behind a port

```text
ui (screens, widgets)
  |  reads state from controllers (ChangeNotifier), sends intents
  v
application controllers: PrerequisiteController, CatalogController, SelectionController, RunController, SummaryController
  |  depend only on ports and domain
  v
domain (pure Dart, immutable)                ports (abstract classes)
  ToggleCatalog, Toggle, Profile               WizardGateway        listSoftware, listProfiles, preview, startRun
  Selection, DesktopChoice                     PtySession           output stream, write, interrupt, kill, exitCode
  WizardArguments (one builder per wizard)     PtyLauncher          start(executable, args, env, workdir) -> PtySession
  PromptDetector (pure)                        PayloadStore         ensureUnpacked() -> ScriptsLocation
  OutputLines (pure, ANSI stripping)           PlatformProbe        isElevated, findPwsh, findBash4, findBrew, findWinget
  ProgressParser (pure) -> ProgressList        ResultReader         read(path) -> RunResult
  RunResult, Verdict, ExitCodeMeaning          Clock, FileSystem
  EnvironmentSanitizer (pure)
  ^
adapters
  BashWizardGateway (setup.sh)    PowerShellWizardGateway (setup.ps1)
  NativePtyLauncher               FlatpakHostPtyLauncher (wraps the command in flatpak-spawn --host)
  ArchivePayloadStore             IoPlatformProbe            JsonResultReader
```

The pseudo terminal is a hidden channel between the application and the wizard, never a screen. The application has no terminal emulator and no terminal widget, decided by the owner on 2026-10-11 (answer 19.1 under Open Questions). Decision 7 says what the user sees instead.

State is held in `ChangeNotifier` controllers from the Flutter SDK. No third-party state library: five controllers do not need one, and every extra dependency is one more package that can go unmaintained, which is exactly the risk already hanging over the pseudo terminal packages.

The composition root in `lib/main.dart` picks adapters once from the platform and from `FLATPAK_ID` (set by Flatpak inside the sandbox). Nothing below the root asks which platform or package format it runs in.

`WizardArguments` is the one place a selection becomes arguments, one pure function per wizard, so the preview and the run cannot be built differently (spec requirement "The command is built in one place").

### Decision 3: Machine-readable output is added to the wizards, not parsed out of them

The application needs the catalogue, the profiles and the outcome of a run. Parsing the existing text would tie the application to column widths and wording, and reading group_vars directly would be a second reader of the same files, which is defect class 2. So both wizards gain additive options, and the format is pinned by JSON Schemas in a new [setup/contract/](../../../setup/contract/) directory, which ships in the payload with the scripts that produce it.

1. `--json` (bash) and `-Json` (PowerShell), accepted only with `--list-software`, `--list-profiles` or `-ListSoftware`. Anything else exits 2. One flag that changes the format of listings, rather than a second listing option per format, keeps one list per wizard.
2. Catalogue document, schema `setup/contract/catalog.schema.json`:

   ```json
   {
     "schema_version": 1,
     "wizard": "setup.sh",
     "os_family": "Debian",
     "toggles": [
       { "key": "install_chrome", "label": "Chrome", "default": true, "group": "Browsers" }
     ]
   }
   ```

   Produced from the same arrays the text listing prints: `PRELOADED_KEYS` and `PRELOADED_ITEMS` in setup.sh, `Get-SelectableToggle` in setup.ps1. `wizard` is `setup.sh` or `setup.ps1`. `os_family` is `OS_FAMILY` from `detect_os` in bash and the literal `Windows` in PowerShell.
3. Groups. The comment headings in group_vars (for example `# Browsers` above `install_chrome` in [setup/ansible/group_vars/all.yaml](../../../setup/ansible/group_vars/all.yaml)) are the only grouping the files have, and a WinUtil-style screen without groups is a list of over a hundred rows. Both wizards record, while reading a file, the last standalone comment line that is not a rule line (only `#`, `-` and spaces) and attach it to each following toggle. Implemented once per wizard, in `read_boolean_toggles` in bash and `Read-Toggles` in PowerShell, with a parity assertion in tier 1, the same way [e2e/tier1/wizard_parse.sh](../../../e2e/tier1/wizard_parse.sh) already guards `EXCLUDED_VARS`. The owner accepted groups, with the parity check, on 2026-10-11 (answer 2).
4. JSON from bash without new dependencies. `jq` is not on a fresh machine, so setup.sh gains one small `json_string` function that escapes backslash, double quote and control characters, and builds the document with `printf`. PowerShell uses `ConvertTo-Json -Depth 5 -Compress` on `[ordered]` hashtables.
5. `--list-profiles` (bash only). The profile names, descriptions and overrides are already computed by `load_profiles`, line 745, for the interactive screen. The function is split so the computing half is shared by the screen and the new listing, and the counting half stays with the screen. `overrides` lists every selectable key the profile file sets, read the way `load_profiles` already reads it (`grep -m1 "^${key}:"`). PowerShell gets no profile listing, because `-Profile` changes nothing on Windows and [setup/setup.ps1](../../../setup/setup.ps1) says so.
6. `--result-file <path>` and `-ResultFile <path>`, schema `setup/contract/result.schema.json`:

   ```json
   {
     "schema_version": 1,
     "wizard": "setup.sh",
     "exit_code": 3,
     "install_exit_code": 0,
     "verification_exit_code": 2,
     "logs": { "verification": "/home/u/installation_verify.log", "errors": "/home/u/installation_errors.log" },
     "applications": [
       { "key": "install_jq", "verdict": "missing", "raw_verdict": "MISSING", "detail": "pacman: jq" }
     ]
   }
   ```

   The parent directory is checked in `parse_args` and `Invoke-Main` before anything runs, exit 2 when it does not exist.

   Unix: setup.sh passes `ih_verify_result_path=<private temp file>` to the verification play as an extra variable, and [setup/ansible/verify_install.yaml](../../../setup/ansible/verify_install.yaml) gains one task after "Build the per-application verdict" that writes the rows it already builds to that path with `ansible.builtin.copy` and `content: "{{ rows | to_json }}"`, `delegate_to: localhost`, `when: ih_verify_result_path is defined`. `finish_run` then composes the outer document from that file and the two exit codes, writes `<path>.tmp` and renames it to `<path>`. An `EXIT` trap writes the document with the exit code and an empty list when the run stops earlier. The trap is added to the existing `remove_become_password_dir` cleanup chain rather than as a second `trap ... EXIT`, because a second `trap` on the same signal replaces the first.

   Windows: `Invoke-Main` already holds `$phases`, `$failed` and `$verification`. A new `Write-RunResultFile` function in [setup/windows/WindowsVerify.ps1](../../../setup/windows/WindowsVerify.ps1) converts them and writes atomically with `Move-Item -Force`. Every `exit` in `Invoke-Main` after the parameter checks goes through one `Exit-Wizard -Code <n>` function that writes the file first, so no exit path forgets it.

   Verdict normalisation lives in one table per wizard, and the schema's `enum` is the list both tables must map onto. A tier 1 check greps every verdict literal in both producers and fails on one the table does not map.
7. Alternative rejected: a separate `desktop-helper` script that reads group_vars and prints JSON. It would be a third reader of the same files, which is the exact shape of defect class 2.

### Decision 4: Flutter version and Dart packages

Flutter 3.47.7 stable, released 2026-10-08 with Dart 3.13.5, measured from https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json. Pinned once in `desktop/pubspec.yaml` under `environment: flutter: 3.47.7`. The release workflow passes `flutter-version-file: desktop/pubspec.yaml` to `subosito/flutter-action@v2`, which reads that field, so there is one pin. Locally `fvm use 3.47.7` is the documented route, FVM being what this repository's `sdk_manager` role installs.

Runtime packages, versions measured from https://pub.dev/api/packages/<name> on 2026-10-10:

| Package | Version | Published | Use |
|---|---|---|---|
| flutter_pty2 | 2.0.0 | 2026-09-19 | first candidate for the hidden pseudo terminal channel, see the table below |
| archive | 4.4.0 | 2026-10-10 | unpacking the payload |
| crypto | 3.0.7 | 2025-11-04 | SHA-256 of the payload |
| path_provider | 2.1.6 | 2026-06-15 | per-user data directory |
| window_manager | 0.5.2 | 2026-07-04 | intercepting window close during a run |

Pseudo terminal candidates, measured the same way:

| Package | Latest | Published | Platforms | How it spawns | Notes |
|---|---|---|---|---|---|
| flutter_pty | 0.4.2 | 2025-01-06 | all five | native C plugin, forkpty and exec on Unix, ConPTY on Windows | the owner's candidate, 150 points, 8222 downloads in 30 days, unmaintained for 21 months |
| flutter_pty2 | 2.0.0 | 2026-09-19 | all five | native plugin, "a poll-based reactor with bounded output credit" on Unix, "ConPTY with dedicated reader, writer, waiter, and close workers" on Windows | its page: "a maintained fork of the original flutter_pty package ... The original package is no longer maintained." MIT. New `Pty.spawn` session API, `Pty.start` removed |
| pty2 | 0.5.6 | 2026-09-30 | Linux, macOS, Windows | pure Dart FFI, `forkpty` on Unix, ConPTY on Windows | 160 points, 33470 downloads in 30 days. Calling `forkpty` from Dart FFI forks a multithreaded VM, which is only safe if the child execs immediately, unverified for this package |
| kyroon_pty | 1.0.6 | 2026-08-02 | all five | native plugin | 172 downloads in 30 days |
| flutter_pty_new | 1.0.0 | 2026-07-10 | all five | native plugin | 120 downloads in 30 days |
| portable_pty | 0.0.5 | 2026-05-02 | all plus web | Dart | pre-1.0, 575 downloads in 30 days |

Recommendation: flutter_pty2 first, because it keeps flutter_pty's native spawn model, which avoids running Dart in a forked child, and it is maintained. flutter_pty 0.4.2 is the fallback, with the known risk that nobody will fix it. Spike 4 (task 1.4) decides, on all three operating systems, before any screen is written. Either way the package sits behind `PtyLauncher` and `PtySession`, so changing it later is one adapter.

No terminal rendering package. An earlier version of this decision listed xterm 4.0.0 to draw the output as a terminal. The owner decided on 2026-10-11 that the user never sees a terminal (answer 19.1), so xterm is not a dependency, and the output is turned into plain lines by the pure `OutputLines` function of decision 7. The pseudo terminal package stays, because `setup.sh` reads the sudo password with `read -s` and plain `sudo` opens `/dev/tty`, and both need a terminal on the other end.

### Decision 5: The scripts are a payload archive, unpacked per user and per version

At build time `dart run tool/build_payload.dart --tag <tag>` runs `git archive --format=tar.gz --prefix=setup-payload/ -o assets/payload/setup.tar.gz <tag> setup` and writes `assets/payload/manifest.json` with `tag`, `commit` (from `git rev-list -n 1 <tag>`) and `sha256`. `git archive` takes only tracked files at that exact commit, so untracked files on the build machine can never leak into a release. Both files are declared under `flutter: assets:` in `desktop/pubspec.yaml` and ignored in `desktop/.gitignore`.

At start `ArchivePayloadStore.ensureUnpacked()`:

1. Resolves `<user data>/InstallationHelper/scripts/<tag>/`: `%LOCALAPPDATA%` on Windows, `~/Library/Application Support` on macOS, `$XDG_DATA_HOME` or `~/.local/share` on Linux. Inside the Flatpak `XDG_DATA_HOME` is `~/.var/app/io.github.lukk17.InstallationHelper/data`, a real path under the user's home that the host can read, which is what `flatpak-spawn --host` needs (the host cannot see `/app`, per the owner's research).
2. Returns at once when `<dir>/.payload-sha256` equals the manifest's `sha256`.
3. Otherwise hashes the asset, refuses on mismatch, extracts into `<dir>.partial-<random>`, sets the executable bit on `setup/setup.sh` and every `*.sh` the archive marks executable (tar keeps the mode, `archive` exposes it), writes `.payload-sha256`, renames the directory into place, and deletes every sibling version directory.

One code path for every format. It also solves three problems at once: the AppImage's squashfs mount is read-only, the macOS bundle must not be modified after signing, and the Flatpak host cannot see `/app`. The wizards write their logs to the user's home, not their own directory, so a writable copy is not strictly needed there, but Ansible collections, retry files and fact caches have changed location before, and a writable directory removes the question.

The application always starts the wizard as `bash <dir>/setup-payload/setup/setup.sh` or `pwsh -File <dir>\setup-payload\setup\setup.ps1`, so the executable bit is a convenience for a user who wants to run the copy by hand, not something the application depends on.

### Decision 6: How each platform starts the wizard

The working directory is always `<dir>/setup-payload/setup`. Every run passes `--result-file <user data>/InstallationHelper/runs/<timestamp>/result.json` and writes the transcript to `<home>/installation_gui_transcript.log`, next to the wizard's own `installation_*.log` files.

| Platform and format | Executable and arguments |
|---|---|
| Linux tar, AppImage, Snap | `bash <payload>/setup.sh <selection> --result-file <path>` through `NativePtyLauncher` |
| Linux Flatpak | `flatpak-spawn --host --watch-bus --directory=<payload> --env=TERM=xterm-256color bash <payload>/setup.sh ...` through `FlatpakHostPtyLauncher`, which wraps the same `NativePtyLauncher`. If spike 1 shows the host side gets no controlling terminal, the command becomes `flatpak-spawn --host ... script --quiet --return --flush --command "<quoted command>" /dev/null`, decision 6.2 |
| macOS | `/bin/bash <payload>/setup.sh ...`, which re-execs into Homebrew's bash 4 itself (setup.sh line 77) |
| Windows | `<pwsh.exe> -NoLogo -NoProfile -File <payload>\setup.ps1 <selection> -ResultFile <path>` through the same launcher on a ConPTY |

The pseudo terminal is opened with a fixed size of 200 columns and 50 rows and is never resized, because nothing on screen draws it. The width keeps long Ansible task names and package names on one line, which the progress parser of decision 7 relies on.

Selection arguments, from `WizardArguments`:

| Choice | setup.sh | setup.ps1 |
|---|---|---|
| Checklist | `--software none --enable <comma-separated ticked keys>` | `-Software none -EnableKey <comma-separated ticked keys>` |
| Profile (Linux, macOS) | `--profile <id>` | not offered |
| Desktop environment (Linux) | `--desktop-environment kde --desktop-action full`, omitted for skip | not offered |
| Skip system upgrade | `--skip-system-upgrade` | `-SkipSystemUpgrade` |

`--software none` with the full ticked set rather than `defaults` with differences, so the arguments describe the whole selection on their own, the preview shows every key, and the run does not depend on which per-OS file the wizard layers over all.yaml. Every one of these options already implies `--non-interactive` (setup.sh header line 18), and the PowerShell options imply `-NonInteractive` (setup.ps1 `.PARAMETER Software`). A comma-separated `-EnableKey` string through `-File` arrives as one string, which `Split-KeyList` (setup.ps1 line 1025) already splits on commas.

#### 6.1 The environment handed to the wizard

`EnvironmentSanitizer` is a pure function from the application's environment to the wizard's. It removes the variables the spec lists, restores any `<NAME>_ORIG` value an AppRun or snap launcher saved, sets `TERM=xterm-256color`, and leaves everything else alone. Reason: AppImage `AppRun` scripts and snap launchers commonly set `LD_LIBRARY_PATH` and GTK module paths for the application itself, and a host `python3`, `apt` or `ansible-playbook` loading bundled libraries is a classic, hard to diagnose breakage. Which variables each format really sets is measured in task 2.6 rather than assumed, and the list in the spec is the minimum.

#### 6.2 Flatpak, and the fallback if the pseudo terminal does not reach the host's sudo

The Flatpak needs `--talk-name=org.freedesktop.Flatpak` to use `flatpak-spawn --host`, which gives the application full host access. That defeats the sandbox, and the README says so plainly. It is acceptable for a self-hosted bundle and would be rejected by Flathub, which is not a goal.

Untested, and therefore spike 1: whether a host process started through `flatpak-spawn --host` with the pseudo terminal's slave as its standard streams gets that terminal as its controlling terminal. Three things depend on it and each is checked separately: `read -s` (needs standard input to be a terminal to turn off echo), `sudo -S` (reads standard input, needs nothing more), and plain `sudo` later in the run (opens `/dev/tty`, needs a controlling terminal).

Fallback A, used if plain `sudo` fails: create the pseudo terminal on the host side with util-linux `script`, which is part of util-linux on every supported distribution: `flatpak-spawn --host script --quiet --return --flush --command "<command>" /dev/null`. The host `script` allocates a pseudo terminal, makes it the controlling terminal of the wizard, and relays it over the streams `flatpak-spawn` forwards, which the application still reads through its own hidden pseudo terminal. `--return` makes `script` exit with the wizard's code. Fallback B, if neither works: drop the Flatpak from the release, both the single-file bundle and the repository of decision 12.6, and record the measured output of both attempts in [docs/regression_ledger.md](../../../docs/regression_ledger.md). The owner agreed to this on 2026-10-11 (answer 6).

### Decision 7: The hidden channel, the progress list and the dialogs

The owner decided on 2026-10-11 (answer 19.1) that the application never shows a terminal. The pseudo terminal of decisions 2 and 6 stays, only as a hidden channel between the application and the wizard, because `setup.sh` reads the sudo password with `read -r -s -p` and plain `sudo` opens `/dev/tty`. Nothing on screen draws it, and the user never types into it.

#### 7.1 From bytes to lines

Every byte from `PtySession.output` goes through one pure function, `OutputLines`, in `lib/domain/output_lines.dart`. It decodes UTF-8, removes ANSI escape sequences (colours, cursor movement, the `ESC ] ... BEL` title sequences), treats a carriage return without a newline as "replace the current line", and emits complete lines plus the current partial line (the text after the last newline). Its output feeds three consumers and nothing else:

1. The raw output log. Every complete line is kept in memory for the "Show details" view and appended, as it arrives, to `<home>/installation_gui_transcript.log`, next to the wizard's own `installation_*.log` files. That is the only file the application writes for a run apart from the lock file. The application never writes anything it sends to the channel into this log or any other file.
2. `ProgressParser`, section 7.2.
3. `PromptDetector`, section 7.3.

#### 7.2 The progress list

The main run screen is a list, not a log. `ProgressParser` is a pure function from the lines so far to an immutable `ProgressList`: one row per step and one row per package, each with a status of running, installed, skipped with its reason, or failed with its reason. It recognises only these line formats, each read from the code that prints it:

| Line format | Printed by | Row |
|---|---|---|
| `  >> <text>` | `say` in [setup/setup.sh](../../../setup/setup.sh) | a step row, running until the next step row starts |
| `TASK [<name>]` | `_display_and_log` in [setup/ansible/callback_plugins/dual_logger.py](../../../setup/ansible/callback_plugins/dual_logger.py) | the current step's detail text, not a row of its own |
| `<status>: [<host>] <item>` with status `INSTALLED`, `present` or `absent` | `v2_runner_item_on_ok` in the same file | a package row, installed |
| `FAILED: [<host>] <item> -- <reason>`, and `TOLERATED` the same way | `v2_runner_item_on_failed` | a package row, failed with that reason, or for `TOLERATED` skipped with that reason |
| `skipped: [<host>] <item> [<reason>]` | `v2_runner_item_on_skipped` | a package row, skipped with that reason |
| `  ... [<i>/<n>] <key> (<package>)` then `      <status> after <s>s...` | the winget loop in [setup/windows/WindowsSoftware.ps1](../../../setup/windows/WindowsSoftware.ps1) | a package row, running, then the status from the second line |
| `  ... [<i>/<n>] <key> skipped` | the same loop | a package row, skipped |

The status words are padded with `{status:>10}` in the callback plugin, so the parser trims leading spaces. The exact Windows step lines, and the Chocolatey lines (`  ... choco install <package>`), are read from [setup/setup.ps1](../../../setup/setup.ps1) and [setup/windows/](../../../setup/windows/) in task 4.7 and added to this table there. A unit test reads each format string from the file that prints it, the same way the prompt test of 7.3 does, so a change of wording in a producer fails a test rather than silently emptying the list.

Any line the parser does not recognise is not lost: it stays in the raw output behind "Show details". The list is live feedback only. When the run ends, the summary takes every per-application verdict from the result file of decision 3, which is the one source of truth, and a package row whose live status disagrees with the result file is shown with the result file's verdict. So a parser that misses a line can make the live list less detailed, never make the summary wrong.

"Show details" opens the raw output as plain read-only text in a scrolling, selectable, monospaced text widget from the Flutter SDK: no cursor, no input, no colours, and no terminal emulation. The user can read and copy it, and a second button opens the folder that holds the log files.

#### 7.3 Prompts and dialogs

`PromptDetector` is a pure function over the current partial line and the last complete line, matched only when no new output has arrived for 150 milliseconds, so a prompt is detected once it has been fully printed and the program is waiting. Its table lives in `lib/domain/prompt_detector.dart`:

| Pattern | Line | Source | Dialog |
|---|---|---|---|
| `^\s*\[sudo\] password for \S+: $` | partial | `prepare_become_password`, and sudo's own default prompt on Linux | password dialog |
| `^Password:\s*$` | partial | sudo's default prompt on macOS | password dialog |
| `^\s*That password was refused by sudo\.$` and `^Sorry, try again\.$` | complete | `prepare_become_password`, and sudo itself | marks the next password dialog as a retry |
| `Reboot now\? \[y/N\] $` | partial | `offer_reboot` | Yes and No buttons |
| `^Press RETURN/ENTER to continue or any other key to abort:$` | complete | `wait_for_user` in Homebrew's `install.sh` | Continue and Cancel buttons |
| `^Press any key when the installation has completed\.$` | complete | the Command Line Tools step in Homebrew's `install.sh` | one Continue button, with the text that Apple's own installer window must finish first |

The two Homebrew lines were read on 2026-10-11 from `install.sh` in https://github.com/Homebrew/install (last commit 2026-10-01). Both are printed with `echo` and end in a newline, which is why the table matches complete lines as well as partial ones. They matter only to the Homebrew button of decision 10.

The password dialog has a password field that never shows the characters, OK and Cancel:

1. OK writes the password and `\r` to the channel, which the terminal line discipline turns into the newline `read` expects, then clears the field and drops the reference. The password goes to the channel and nowhere else: not to the raw output log, which records output only, not to the transcript, the result file, the settings or any other file. With echo off the wizard prints nothing back.
2. After a refusal line from the table, the next password prompt opens the dialog again with the message "The password was not accepted. Try again." After the script's third refusal it exits 1 on its own, and the summary says so.
3. Cancel writes Ctrl+C (`\x03`) to the channel, which ends `read -s` and makes the wizard exit 130, then follows the Cancel procedure of the desktop-app spec (wait up to 30 seconds, then end the process tree). The summary says the run was cancelled at the password question.
4. One run can ask more than once, so the detector keeps watching for the whole run, and every new prompt opens the dialog again.

The reboot question becomes Yes and No buttons that write `y\r` or `n\r`. After Yes, `sudo reboot` may ask for the password again, which the password dialog handles.

On Windows there is no password dialog. Every administrator step elevates itself and Windows shows its own User Account Control prompt (decision 8). The non-interactive path of `setup.ps1` has no `Read-Host`, so the table above never matches there, and only the safeguard of 7.4 applies.

#### 7.4 A prompt nobody expected

A question the table does not know must never leave the run waiting silently. Two rules, on every platform:

1. A partial line that has not changed for 3 seconds while the process is alive is treated as a question. The application opens the "The setup is asking a question" dialog, which shows the last 5 lines of output and the partial line, a text field, Send and "Stop the run". Send writes the text and `\r` to the channel. "Stop the run" follows the Cancel procedure. When new output arrives while the dialog is open, the dialog closes by itself, because the program was not waiting after all. When nobody answers for 15 minutes, the application stops the run the same way, and the summary names the unanswered question. The answer is not written to any log, because the application cannot know whether it is secret.
2. A question printed as a complete line, the way Homebrew's two lines are, cannot be told apart from a slow step that prints nothing. So when there has been no output for 2 minutes, the current row shows "No output for 2 minutes" with a button "Answer a question", which opens the same dialog.

The table is complete for `setup.sh`, and a mechanical check proves it, in two links:

1. A new file, `setup/contract/interactive_prompts.json`, lists every prompt `setup.sh` itself can print and wait on: an `id`, the exact prompt text with `<user>` for the user name, the answer kind (`password`, `password_refused` or `yes_no`), and the function that prints it. It sits next to the schemas of decision 3 because it is part of the same contract between the wizard and the application.
2. A new tier 1 check, `e2e/tier1/wizard_prompts.sh`, reads [setup/setup.sh](../../../setup/setup.sh) with Python, finds every `read` statement, and fails, naming the line, when a `read` with `-p` has a prompt text the inventory does not list, when the inventory lists a prompt no `read -p` or `echo` in setup.sh prints, or when a `read` without `-p` is not one of the two non-interactive shapes the script uses today, a `while ... read` loop fed by a redirection or a pipe, and `read ... <<<`. Measured on 2026-10-11, setup.sh has two interactive reads, `read -r -p "Reboot now? [y/N] "` in `offer_reboot` and `read -r -s -p "  [sudo] password for $(id -un): "` in `prepare_become_password`, plus the refusal line `  That password was refused by sudo.`, and every other `read` is one of the two non-interactive shapes.
3. A unit test, `desktop/test/domain/prompt_inventory_test.dart`, reads `setup/contract/interactive_prompts.json` from the repository at test time and fails when `PromptDetector` does not match an entry with the dialog its kind names.

So a new `read -p` in setup.sh fails tier 1 until it is in the inventory, and an inventory entry fails `flutter test` until the application knows it. The gum screens are not in the inventory, because every option the application passes implies `--non-interactive` (decision 6) and no gum screen runs on that path.

Alternative rejected: changing setup.sh to read the password from a file descriptor or `SUDO_ASKPASS`. The owner decided no script change on this path, and a pseudo terminal makes the existing code behave exactly as in a terminal.

### Decision 8: Privileges

1. Windows: Flutter's runner manifest, `desktop/windows/runner/runner.exe.manifest`, keeps `requestedExecutionLevel level="asInvoker"`. `IoPlatformProbe.isElevated` asks the same question `Assert-NotAdmin` asks, through `whoami /groups` looking for the `S-1-16-12288` high mandatory level, which needs no FFI.
2. Linux and macOS: `id -u` equal to 0 is refused.
3. The Inno Setup installer installs for all users by default and offers the current user only as a choice, decided by the owner on 2026-10-11 (answer 8), because some of the software the setup installs is machine-wide and a machine-wide tool belongs in a machine-wide location. This changes only where the application's files go. The application itself still runs as the normal user, see item 1, and the administrator prompt appears only while the installer runs. Decision 12.1 gives the exact `[Setup]` directives, quoted from the Inno Setup 6 documentation.
4. `--allow-administrator` exists only for `--self-test` on a hosted Windows runner, mirroring `-AllowAdministrator` in setup.ps1 and for the same reason: GitHub's hosted Windows runners run every process elevated with User Account Control disabled, as the header of [.github/workflows/e2e-manual.yaml](../../../.github/workflows/e2e-manual.yaml) records.
5. The installer's "Launch Installation Helper" checkbox on its last page must start the application as the normal user even after an administrator install. Inno Setup's `postinstall` flag does that by default, see decision 12.1, with one exception Inno Setup documents itself: when the installer was started with Run as administrator, it has no normal user to return to. The application then starts elevated and shows its own refusal from item 1, which is the correct outcome.

### Decision 9: Windows bootstraps PowerShell 7 before anything else

A fresh Windows has only Windows PowerShell 5.1 and setup.ps1 has `#Requires -Version 7`. `IoPlatformProbe.findPwsh` checks, in order, `pwsh.exe` on `PATH`, `%ProgramFiles%\PowerShell\7\pwsh.exe`, and `%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe` (the Store alias), and accepts one whose `-NoProfile -Command $PSVersionTable.PSVersion.Major` prints 7 or more. The known paths matter because a `PATH` change made by the MSI is not visible to an already running process.

When none is found, the prerequisite screen offers one button that runs the command below through the hidden channel of decision 7, shown as one progress row with its output behind "Show details":

```powershell
winget install --id Microsoft.PowerShell --exact --source winget --accept-package-agreements --accept-source-agreements
```

The MSI is machine scope, so Windows shows its own User Account Control prompt. The application stays unelevated. When `winget` is missing too (it can be absent on a brand-new install until App Installer updates from the Store), the screen links https://learn.microsoft.com/windows/package-manager/winget/ and https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows and runs nothing.

Execution policy: the application writes the scripts itself, so they carry no Mark of the Web and the default `RemoteSigned` policy of PowerShell 7 lets them run. Spike 4 confirms this on a fresh Windows 11 virtual machine. If it does not hold, the fix is adding `-ExecutionPolicy RemoteSigned` to the `pwsh` command line, which applies to that process only, and never `Bypass`.

### Decision 10: macOS

1. The App Sandbox is off. Flutter's template sets `com.apple.security.app-sandbox` to true in `macos/Runner/Release.entitlements` and `DebugProfile.entitlements`, and a sandboxed app cannot start `bash` against the user's home. Both files set it to false, and a tier 1 check fails if either sets it to true (task 6.8).
2. Ad hoc signing stays (`CODE_SIGN_IDENTITY = "-"` in the Xcode project), which Apple Silicon needs for any native code to run. No Developer ID, no notarisation. The first start after download needs System Settings, Privacy and Security, Open Anyway. Homebrew 5.0.0 deprecated `--no-quarantine` and casks are always quarantined (owner's research), so the tap route needs the same step.
3. Homebrew and bash 4 are prerequisites the application checks for itself (spec requirement on prerequisites). When Homebrew is missing the screen links https://brew.sh, shows the exact command that page publishes, and offers a button that runs that command, only when pressed, through the hidden channel of decision 7, shown as one progress row with its output behind "Show details". Homebrew's own installer asks for the password, which opens the password dialog, and asks its two confirmation questions, which the prompt table of decision 7.3 turns into buttons. The owner accepted the button on 2026-10-11 (answer 4). The command is read from https://brew.sh when task 6.2 is implemented and written into one constant, rather than copied here, because it is Homebrew's to change. When Homebrew is present and bash 4 is not, the button runs `brew install bash`.
4. Universal binary: `flutter build macos --release` builds arm64 and x86_64 together by default.

### Decision 11: Linux runtime libraries

The Flutter Linux bundle carries the engine and the plugins' `.so` files. GTK 3, glib, libblkid, liblzma and glibc come from the host for the tar archive and the AppImage. The owner's research found GTK 3 (`libgtk-3-0`), `libblkid1` and `liblzma5` on fresh Ubuntu 24.04 and 26.04 desktop installs (official ISO manifests) and on Fedora 44 Workstation. That is the meaning of "every runtime library ships inside" for those two formats: everything Flutter adds is inside, and the base desktop libraries every supported desktop already has are not duplicated. The Flatpak gets them from the GNOME runtime, the classic Snap bundles them (decision 12.4).

Build on `ubuntu-24.04`, glibc 2.39, so the binary runs on every supported distribution, all of which ship a newer glibc.

AppImage: the type 2 static runtime no longer needs `libfuse2` but needs a setuid `fusermount` or `fusermount3` on `PATH` (fuse3 on Ubuntu, a dependency of flatpak on Fedora, per the owner's research). The README documents `--appimage-extract-and-run` for a machine without it.

CachyOS and Arch fresh contents are not known, which is spike 3.

### Decision 12: Packaging, format by format

12.1 Fastforge 0.6.12 (pub.dev, published 2026-07-29), installed with `dart pub global activate fastforge 0.6.12`, makes `exe`, `zip`, `appimage`, `dmg` and the macOS `zip`. Config files, paths as its documentation at https://fastforge.dev/makers/exe, https://fastforge.dev/makers/appimage and https://fastforge.dev/makers/dmg states:

- `desktop/windows/packaging/exe/make_config.yaml`: `app_id` (the GUID from decision 1), `publisher: Lukk17`, `publisher_url: https://github.com/Lukk17/InstallationHelper`, `display_name: Installation Helper`, `create_desktop_icon: true`, `locales: [en]`. Needs Inno Setup 6. Inno Setup 7.1.0 exists (tag `is-7_1_0`, 2026-08-12, https://github.com/jrsoftware/issrc/releases), and Fastforge documents 6, so the workflow installs 6 explicitly. The newest 6.x tag in that repository is `is-6_7_3`, dated 2026-05-22, measured on 2026-10-11 with `gh api "repos/jrsoftware/issrc/tags?per_page=100"`. Whether Chocolatey carries 6.7.3 is checked in task 7.2, unverified here, and the workflow pins whatever that task finds with `choco install innosetup --version <found> -y`.
- Install scope, the owner's answer 8 of 2026-10-11. The generated `.iss` must contain these `[Setup]` directives, through Fastforge's `script_template` option if its default template does not produce them:

  ```text
  PrivilegesRequired=admin
  PrivilegesRequiredOverridesAllowed=dialog commandline
  DefaultDirName={autopf}\Installation Helper
  ```

  Quoted from the Inno Setup 6 help source, `ISHelp/isetup.xml` at tag `is-6_7_3` of https://github.com/jrsoftware/issrc, fetched on 2026-10-11 with `gh api "repos/jrsoftware/issrc/contents/ISHelp/isetup.xml?ref=is-6_7_3"`:

  1. `PrivilegesRequired`, valid values "`admin`, or `lowest`", default `admin`: "When set to `admin` (the default), Setup will always run with administrative privileges and in administrative install mode. If Setup was started by an unprivileged user, Windows will ask for the password to an account that has administrative privileges, and Setup will then run under that account."
  2. `PrivilegesRequiredOverridesAllowed`, valid values "One or more of the following, separated by spaces: `commandline` `dialog`": "If override `commandline` is allowed then Setup will support two additional command line parameters to override the script's default PrivilegesRequired setting: /ALLUSERS and /CURRENTUSER." And: "If override `dialog` is allowed then Setup will ask the user to choose the install mode based on the script's default PrivilegesRequired setting using a suppressible dialog. Allowing `dialog` automatically allows `commandline` and when one of the command line parameters is used then Setup will not ask the user." Naming both values is therefore redundant but harmless, and it is kept because it states the intent in the file.
  3. `/CURRENTUSER`: "Instructs Setup to install in non administrative install mode." `/ALLUSERS`: "Instructs Setup to install in administrative install mode." Each entry ends: "Only has an effect when the `[Setup]` section directive PrivilegesRequiredOverridesAllowed allows the `commandline` override."
  4. `{autopf}` maps to `commonpf` in administrative install mode and to `userpf` in non administrative install mode (the constants table in the same file), so one `DefaultDirName` gives `C:\Program Files\Installation Helper` for all users and `%LOCALAPPDATA%\Programs\Installation Helper` for the current user.
  5. `UsePreviousPrivileges` stays at its default `yes`: "at startup Setup will look in the registry to see if the same application is already installed in one of the two install modes, and if so, it will use that install mode and not ask the user." The same entry says it "must be set to `no` when `AppId` includes constants", which does not apply, because the AppId is a fixed GUID.
  6. The `[Run]` entry for "Launch Installation Helper" uses the `postinstall` flag. Of `runasoriginaluser` the help says "This is the default behavior when the `postinstall` flag is used", meaning "the spawned process will execute with the (normally non-elevated) credentials of the user that started Setup initially", and it adds: "If a user launches Setup by right-clicking its EXE file and selecting "Run as administrator", then this flag, unfortunately, will have no effect". Decision 8 item 5 covers that case.

  So a double-click shows the install mode dialog, offered "based on the script's default PrivilegesRequired setting", which is all users. Which button the dialog marks as the default is checked by eye in task 7.2 rather than assumed. Choosing all users shows one User Account Control prompt for the installer, and choosing the current user shows none. Silent installs pick the mode with `/ALLUSERS` or `/CURRENTUSER`.
- `desktop/linux/packaging/appimage/make_config.yaml`: `display_name`, `icon: assets/icon.png`, `generic_name: System setup`, `categories: [System]`, `startup_notify: true`, `include: []`. Needs `appimagetool` and `locate`. On a hosted runner without FUSE, `appimagetool` runs with `APPIMAGE_EXTRACT_AND_RUN=1`.
- `desktop/macos/packaging/dmg/make_config.yaml`: `title: Installation Helper`, `contents` with the app at x 192, y 344 and an `/Applications` link at x 448, y 344. Needs `npm install -g appdmg`.
- `desktop/distribute_options.yaml`: one release `github` with jobs `windows-exe`, `windows-zip`, `linux-appimage`, `macos-dmg`, `macos-zip`, each with `build_args: { build-name: <version>, dart-define: ... }`.

The Linux `.tar.gz` is not a Fastforge target. It is `tar -C build/linux/x64/release/bundle -czf installation-helper-<version>-linux-x86_64.tar.gz .` in the workflow.

12.2 Windows winget manifest. Multi-file manifest, `ManifestVersion: 1.12.0`, in `desktop/packaging/winget/` as templates with `{{VERSION}}`, `{{URL}}` and `{{SHA256}}`, filled by the workflow and attached to the release as `winget-manifest-<version>.zip`. Two installer entries for the same `InstallerUrl` and `InstallerSha256`, both `InstallerType: inno` and `UpgradeBehavior: install`, following the owner's answer 8 of 2026-10-11:

1. `Scope: machine` with `InstallerSwitches: Custom: /ALLUSERS`, listed first.
2. `Scope: user` with `InstallerSwitches: Custom: /CURRENTUSER`.

The custom switch is needed because winget adds no scope switch of its own for Inno installers. Its defaults for `inno`, read on 2026-10-11 from `src/AppInstallerCommonCore/Manifest/ManifestCommon.cpp` in https://github.com/microsoft/winget-cli (last changed 2026-06-10), are only `Silent` `/SP- /VERYSILENT /SUPPRESSMSGBOXES /NORESTART`, `SilentWithProgress` `/SP- /SILENT /SUPPRESSMSGBOXES /NORESTART`, `Log` and `InstallLocation` `/DIR=`. The 1.12.0 installer schema, `schemas/JSON/manifests/v1.12.0/manifest.installer.1.12.0.json` in the same repository, allows `Scope` values `user` and `machine` and an `InstallerSwitches.Custom` string, measured the same day. The user picks with `winget install --manifest <folder> --scope machine` or `--scope user`, the `--scope` option being documented in `hub/package-manager/winget/install.md` of https://github.com/MicrosoftDocs/windows-dev-docs, read on 2026-10-11, as "Allows you to specify if the installer should target user or machine scope". Without `--scope`, which entry winget picks is checked in task 7.3 rather than assumed. The newest schema in https://github.com/microsoft/winget-cli/tree/master/schemas/JSON/manifests is 1.30.0 (measured), and 1.12.0 is chosen because it is old enough for the winget shipped with current Windows 11 to accept, which `winget validate --manifest <dir>` confirms in task 6.3. User steps, as the owner decided: an administrator runs `winget settings --enable LocalManifestFiles` once, then `winget install --manifest <folder>`.

12.3 Flatpak. Two possible routes, owner's research: flatpak-flutter 0.15.0 (https://github.com/TheAppgineer/flatpak-flutter, released 2026-06-12, measured), which builds Flutter from source inside flatpak-builder with offline sources, or a manifest that packages the prebuilt bundle from the Linux job. Chosen: the prebuilt bundle, because the same binary that passed the tar smoke test is then the one inside the Flatpak, and because Flathub's offline-build rule, the reason flatpak-flutter exists, does not apply to a self-hosted bundle. Manifest `desktop/packaging/flatpak/io.github.lukk17.InstallationHelper.yaml`:

```yaml
app-id: io.github.lukk17.InstallationHelper
runtime: org.gnome.Platform
runtime-version: '51'
sdk: org.gnome.Sdk
command: installation_helper
finish-args:
  - --share=ipc
  - --socket=fallback-x11
  - --socket=wayland
  - --device=dri
  - --talk-name=org.freedesktop.Flatpak
modules:
  - name: installation-helper
    buildsystem: simple
    build-commands:
      - cp -r bundle /app/installation_helper
      - install -Dm755 installation_helper.sh /app/bin/installation_helper
      - install -Dm644 io.github.lukk17.InstallationHelper.metainfo.xml /app/share/metainfo/io.github.lukk17.InstallationHelper.metainfo.xml
      - install -Dm644 io.github.lukk17.InstallationHelper.desktop /app/share/applications/io.github.lukk17.InstallationHelper.desktop
      - install -Dm644 icon.png /app/share/icons/hicolor/256x256/apps/io.github.lukk17.InstallationHelper.png
    sources:
      - type: dir
        path: build-input
```

Runtime 51: Flathub's API answered `runtime/org.gnome.Platform/x86_64/51` for the current GNOME runtime on 2026-10-10 (https://flathub.org/api/v2/appstream/org.gnome.Platform). The GNOME runtime is chosen over `org.freedesktop.Platform` because Flutter's Linux embedder needs GTK 3, which the freedesktop runtime does not include. `installation_helper.sh` sits next to the manifest and contains `#!/bin/sh` and `exec /app/installation_helper/installation_helper "$@"`, because flatpak-builder runs build commands with `/bin/sh`, which has no `<<<`. Build and bundle:

```bash
flatpak-builder --user --install-deps-from=flathub --force-clean --repo=flatpak-repo flatpak-build desktop/packaging/flatpak/io.github.lukk17.InstallationHelper.yaml
```

```bash
flatpak build-bundle flatpak-repo installation-helper-<version>.flatpak io.github.lukk17.InstallationHelper --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo
```

The single-file bundle stays even with the repository of decision 12.6, because it installs without adding a remote and it is what the release smoke test checks.

12.4 Snap. snapcraft 9.1.4 (https://github.com/canonical/snapcraft/releases, released 2026-10-08, measured) and its `plugin: flutter`. The `gnome` extension supports only strict and devmode confinement (`snapcraft/extensions/gnome.py`, owner's research), so the classic snap cannot use it and bundles GTK itself. `desktop/packaging/snap/snapcraft.yaml`, starting point for spike 2:

```yaml
name: installation-helper
base: core24
version: '<version>'
summary: Pick what to install and run the Installation Helper setup wizard
description: Desktop front end for setup/setup.sh from Lukk17/InstallationHelper.
grade: stable
confinement: classic
apps:
  installation-helper:
    command: bin/installation-helper-launch
parts:
  app:
    plugin: flutter
    source: desktop
    flutter-target: lib/main.dart
    build-attributes: [enable-patchelf]
    stage-packages:
      - libgtk-3-0t64
      - libblkid1
      - liblzma5
  launcher:
    plugin: dump
    source: desktop/packaging/snap/launcher
```

`enable-patchelf` rewrites the ELF interpreter and run path to the snap's own `core24` libraries, which is what a classic snap needs to use the libraries it bundles instead of the host's. The launcher sets the GTK, GDK pixbuf and GIO module paths to the snap's copies, saves any previous value as `<NAME>_ORIG`, and execs the application, which strips them for the wizard (decision 6.1). Whether this draws a window on Fedora 44 and Debian 13 hosts, and whether host and snap GTK modules collide, is spike 2. Install: `sudo snap install --dangerous --classic ./installation-helper_<version>_amd64.snap`. On Fedora, classic snaps need the `/snap` symlink: `sudo ln -s /var/lib/snapd/snap /snap`, which the README states.

12.5 Homebrew tap. Decided by the owner on 2026-10-11 (answer 3 under Open Questions): route B, no second repository. The cask lives in a `Casks/` folder at the top level of this repository, Lukk17/InstallationHelper, and users tap it with the explicit URL. The owner does not want a `-tap` suffix in the command, and this route has none. What the user types, in this order, after Homebrew is installed:

```bash
brew tap Lukk17/installationhelper https://github.com/Lukk17/InstallationHelper
```

```bash
brew install --cask Lukk17/installationhelper/installation-helper
```

The facts behind the route, read on 2026-10-11 from https://github.com/Homebrew/brew:

1. `docs/Taps.md` (front matter `last_review_date: "2026-07-18"`, last commit 2026-07-19): "`brew tap <user>/<repository>` clones `https://github.com/<user>/homebrew-<repository>` into Homebrew's tap directory." And: "On GitHub, a repository must be named `homebrew-<repository>` to use the one-argument form of `brew tap`. The `homebrew-` prefix can be omitted from the command: `brew tap username/foobar`. This command maps to `https://github.com/username/homebrew-foobar`. The two-argument form does not impose this naming convention because the full URL is explicit." And: "`brew tap <user>/<repository> <URL>` clones a repository from the specified Git URL without assuming GitHub or a particular transport." And: "Homebrew updates the repository during `brew update`."
2. `docs/How-to-Create-and-Maintain-a-Tap.md` (last commit 2026-07-19): "Place any cask files you wish to make available in a `Casks` directory at the top level of your tap." And: "Unlike formulae, casks must have globally unique names to avoid clashes." `Casks/i/installation-helper.rb` does not exist in https://github.com/Homebrew/homebrew-cask, measured on 2026-10-11 with `gh api repos/Homebrew/homebrew-cask/contents/Casks/i/installation-helper.rb` answering 404, so the token is free today.
3. Homebrew 6.0.0, announced at https://brew.sh/2026/06/11/homebrew-6.0.0/, introduced tap trust. `docs/Tap-Trust.md`: "Non-official taps require explicit trust by default since Homebrew 6.0.0", and "Installing a fully qualified formula or cask name trusts only that item", with the example `brew install --cask user/repository/cask`. So the install command uses the fully qualified name `Lukk17/installationhelper/installation-helper` and never asks the user to trust the whole tap.

Consequences the owner accepted with the route:

1. Every user types the URL. Typing the short form `brew tap Lukk17/installationhelper` by habit makes Homebrew look for `https://github.com/Lukk17/homebrew-installationhelper`, which does not exist (`gh api repos/Lukk17/homebrew-installationhelper` answered 404 on 2026-10-11), so it fails. The README says so next to the command.
2. Every release needs a follow-up commit on `master` that updates `Casks/installation-helper.rb` with the new version and SHA-256. The SHA-256 of the release zip exists only after the release workflow ran, so the cask inside the tag's own tree always describes the previous version, and until the follow-up commit lands the tap keeps offering the previous version.
3. Tapping clones this whole repository into Homebrew's tap directory, and every `brew update` fetches every new commit to it. GitHub reports the repository at 92188 KB (`gh api repos/Lukk17/InstallationHelper --jq .size`, 2026-10-11), against a few kilobytes for a repository holding one cask.
4. Homebrew also reads formulae from the repository root when there is no `Formula` folder ("The first available directory is used", `docs/How-to-Create-and-Maintain-a-Tap.md`). The root holds no `.rb` file today, measured, and it must stay that way, which the tier 1 check of task 7.8 enforces.

Cask template in `desktop/packaging/homebrew/installation-helper.rb`. It is the one source of the cask's content, and `Casks/installation-helper.rb` is always this template with only the `version` and `sha256` lines filled:

```ruby
cask "installation-helper" do
  version "<version>"
  sha256 "<sha256 of the zip>"
  url "https://github.com/Lukk17/InstallationHelper/releases/download/v#{version}/installation-helper-#{version}-macos-universal.zip"
  name "Installation Helper"
  desc "Desktop front end for the Installation Helper setup wizard"
  homepage "https://github.com/Lukk17/InstallationHelper"
  app "Installation Helper.app"
  caveats "The app is not notarised. On first start, open System Settings, Privacy and Security, and press Open Anyway."
end
```

How the cask reaches `master`, decided here. Nothing in this repository pushes or commits automatically: the owner's rules forbid any push without his instruction, and the workflow header rule of [.github/workflows/e2e-manual.yaml](../../../.github/workflows/e2e-manual.yaml) makes every run a deliberate action. So the release workflow prepares the change and a human commits it:

1. The `release` job of decision 13 fills the template with the tag's version and the SHA-256 of `installation-helper-<version>-macos-universal.zip` it computed itself, checks that the filled file differs from the template only in those two lines, and attaches it to the draft release as the asset `installation-helper.rb`. A release asset rather than a workflow artifact, because a workflow artifact expires after its retention period while the release asset stays next to the zip it describes. The job does not commit, does not push, and opens no pull request, and its `contents: write` permission is used only for the release.
2. After publishing the release, the owner runs on his own machine, from the repository root on an up-to-date `master`, the commands below, then pushes when he decides to. These go into [desktop/README_DESKTOP.md](../../../desktop/README_DESKTOP.md) under how to cut a release.

```bash
gh release download v<version> --pattern installation-helper.rb --dir Casks --clobber
```

```bash
git add Casks/installation-helper.rb
```

```bash
git commit -m "chore(homebrew): installation-helper <version>"
```

3. A new tier 1 check, `e2e/tier1/homebrew_cask.sh`, keeps the two files from drifting (defect class 7): when `Casks/installation-helper.rb` exists, it must equal the template except for the `version` and `sha256` lines, its `version` must be a plain `X.Y.Z`, and the repository root must hold no `.rb` file (consequence 4). Before the first release the folder is absent, so the comparison reports SKIP with that reason while the root check still runs.

12.6 Signed Flatpak repository on GitHub Pages. In scope since the owner's answer 5 of 2026-10-11, next to the single-file bundle, so a Flatpak user gets `flatpak update`.

Facts, each read on 2026-10-11:

1. A `.flatpakrepo` file adds a remote in one command. From `docs/hosting-a-repository.rst` of https://github.com/flatpak/flatpak-docs (last changed 2026-09-01): "`.flatpakrepo` files are a convenient way to let users add a repository", with the example `flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo`, and ".flatpakrepo files should include the base64-encoded version of the GPG key that was used to sign the repository. This can be obtained with the following command: `base64 --wrap=0 < key.gpg`".
2. From `doc/flatpakrepo.xml` of https://github.com/flatpak/flatpak: `Url` "The url for the remote. This key is mandatory." and `GPGKey` "The base64-encoded gpg key for the remote." From `doc/flatpakref.xml` (last changed 2025-12-08): `Name` "The fully qualified name of the runtime or application. This key is mandatory.", `Url` "This key is mandatory.", `Branch` "If this key is not specified, the "master" branch is used.", `RuntimeRepo` "The url for a .flatpakrepo file for the remote where the runtime can be found."
3. Signing. `doc/flatpak-build-update-repo.xml`: synopsis `flatpak build-update-repo [OPTION...] LOCATION`, "This command generates an OSTree summary file that lists the contents of the repository", `--gpg-sign=KEYID` "Sign the commit with this GPG key.", `--generate-static-deltas` "Generate static deltas for all references. This generates from-empty and delta static files that allow for faster download.", `--prune` "Remove unreferenced objects in repo." `doc/flatpak-build-import-bundle.xml`: synopsis `flatpak build-import-bundle [OPTION...] LOCATION FILENAME`, "Imports a bundle from a file named FILENAME into the repository at LOCATION", with the same `--gpg-sign=KEYID` "Sign the commit with this GPG key."
4. Remote add and install. `doc/flatpak-remote-add.xml`: `--if-not-exists` "Do nothing if the provided remote already exists.", `--user` "Modify the per-user configuration.", and `--from` "is enabled by default if the extension is .flatpakrepo". `doc/flatpak-install.xml`: a `.flatpakref` is accepted directly, `--from` "is assumed if the argument ends with .flatpakref".
5. GitHub Pages limits, from `content/pages/getting-started-with-github-pages/github-pages-limits.md` of https://github.com/github/docs (last changed 2026-07-24): "Published GitHub Pages sites may be no larger than 1 GB.", "GitHub Pages sites have a soft bandwidth limit of 100 GB per month.", "GitHub Pages deployments will timeout if they take longer than 10 minutes." From `using-custom-workflows-with-github-pages.md` in the same folder: the Pages artifact "should be a compressed gzip archive containing a single tar file. The tar file must be under 10GB in size and should not contain any symbolic or hard links.", and "The job must have a minimum of `pages: write` and `id-token: write` permissions." and "The default environment is `github-pages`." Newest releases measured with `gh api repos/<action>/releases/latest`: `actions/upload-pages-artifact` v5.0.0, `actions/deploy-pages` v5.0.1, `actions/configure-pages` v6.0.0.
6. This repository has no Pages site yet: `gh api repos/Lukk17/InstallationHelper --jq .has_pages` printed `false`. The owner enables Pages once, under Settings, Pages, Source "GitHub Actions", which also creates the `github-pages` environment.

The signing key, decided here:

1. The owner generates it on his own machine. Neither an agent session nor a workflow ever generates or sees the private key in clear, so it never appears in a chat, a log or the repository. The commands are task 7.9. The user id is `Lukk17 <luksarna@gmail.com>`, the owner's GitHub user name and the address he gave for this purpose on 2026-10-11 (answer 10). It is written into the public key every user downloads. One Ed25519 key, primary key only, signing:

   ```bash
   gpg --quick-generate-key "Lukk17 <luksarna@gmail.com>" ed25519 sign never
   ```

   The arguments, from `doc/gpg.texi` of https://github.com/gpg/gnupg (last commit 2026-09-22): the synopsis is `--quick-generate-key user-id [algo [usage [expire]]]`, and "If algo or usage are given, only the primary key is created and no prompts are shown." For `algo` it refers to `--quick-add-key`: "Supported algorithms are "rsa", "dsa", "elg", "ed25519", "cv25519", and other ECC curves." For `usage`: "a comma delimited list (or space delimited list) of keywords: "sign" for a signing subkey". For `expire`: "The values "never", "none" can be used for no expiration date."

   Ed25519 works for this repository, measured rather than assumed, because neither the Flatpak nor the OSTree documentation names an algorithm. Flatpak's `--gpg-sign` signs and verifies through libostree, which hands GPG work to GnuPG through gpgme, separate from OSTree's own `ed25519` signature type that Flatpak does not use here. Measured on 2026-10-11 in WSL Ubuntu 24.04, the runner's release, with libostree 2024.5 and GnuPG 2.4.4: a key made with the command above (with a throwaway user id in a throwaway `GNUPGHOME`) listed as algorithm 22, EdDSA, capabilities `scSC`, no expiry. `ostree commit --gpg-sign` and `ostree summary -u --gpg-sign` both exited 0. A second repository with only the exported public key imported into its remote, and `gpg-verify=true` plus `gpg-verify-summary=true`, pulled the commit with exit 0, and `ostree show --gpg-verify-remote` printed "Signature made ... using EdDSA key ID ..." and "Good signature from "Lukk17 <luksarna@gmail.com>"". The negative control, the same pull with a different Ed25519 key imported, exited 1 with "Can't check signature: public key not found". RSA 4096 gave the same results, so it stays the fallback if task 7.12 shows a user's distribution refusing the Ed25519 key. EdDSA signatures need GnuPG 2.1 or newer on the user's machine. The GnuPG version on each supported distribution was not measured here, and task 7.12 records it with `gpg --version` on each virtual machine. The measurement used the `ostree` command line, not the `flatpak` binary, so task 7.12 confirms the full Flatpak path on Fedora 44 and Ubuntu 26.04.

   No expiry, decided by the owner on 2026-10-11 (answer 12 under Open Questions). An expired key stops every user's updates until they import an extended key, measured as recorded under that answer. What replaces the expiry is the revocation procedure below. The owner keeps an offline copy of the private key and of the revocation certificate.
2. The private key, armoured, and its passphrase live only as two GitHub Actions secrets on the `github-pages` environment, so only the Pages job can read them. Their names are `FLATPAK_GPG_PRIVATE_KEY` and `FLATPAK_GPG_PASSPHRASE`, confirmed by the owner on 2026-10-11 (answer 11). The owner sets them with `gh secret set <name> --env github-pages`, which reads the value from standard input (`gh secret set --help` on gh 2.97.0: "-e, --env environment Set deployment environment secret").
3. The public key is committed as `desktop/packaging/flatpak/installation-helper.gpg` (`gpg --export <keyid>`), and the workflow fills `GPGKey=` in both files from it with `base64 --wrap=0`. The Pages job compares the fingerprint of the secret key it imported with the fingerprint of the committed public key and fails when they differ, so a replaced secret cannot silently sign with a key no user trusts.
4. In the job, the passphrase reaches gpg-agent the way the Flatpak documentation's own CI example does it: `echo "allow-preset-passphrase" >> ~/.gnupg/gpg-agent.conf`, `gpg-connect-agent reloadagent /bye`, the preset with `gpg-preset-passphrase --preset <keygrip>`, and `gpg --import --batch <file>` (all quoted from `docs/hosting-a-repository.rst`). The path of `gpg-preset-passphrase` on `ubuntu-24.04` is measured in task 7.11, because the documentation's `/usr/libexec/` path is Fedora's.

Revocation and key rotation, which replace an expiry date. Facts read on 2026-10-11 from https://github.com/gpg/gnupg: `doc/gpg.texi` (last commit 2026-09-22), `g10/keygen.c` and `g10/revoke.c` (last commit 2025-09-02):

1. GnuPG writes a revocation certificate by itself when it makes a key. `doc/gpg.texi` under `--generate-key`: "In addition to the key a revocation certificate is created and stored in the `openpgp-revocs.d` directory below the GnuPG home directory." The same happens for `--quick-generate-key`, read from the source rather than the manual: `do_generate_keypair` in `g10/keygen.c` calls `gen_standard_revoke` for every key it makes, and `gen_standard_revoke` in `g10/revoke.c` names the file after the fingerprint and logs "revocation certificate stored as '%s.rev'". So the file is `~/.gnupg/openpgp-revocs.d/<fingerprint>.rev`. Task 7.9 confirms it exists rather than trusting this reading.
2. The manual on that directory: "It is suggested to backup those certificates and if the primary private key is not stored on the disk to move them to an external storage device. Anyone who can access these files is able to revoke the corresponding key."
3. The automatic certificate carries no reason ("No particular reason" in `g10/revoke.c`) and is protected against accidental use: "To avoid an accidental use of this file, a colon has been inserted before the 5 dashes below. Remove this colon with a text editor before importing and publishing this revocation certificate."
4. A new certificate with a reason is made with `--generate-revocation`, whose older name `--gen-revoke` the manual lists in the same entry: "Generate a revocation certificate for the complete key." And: "To actually revoke a key the created revocation certificate needs to be merged with the key to revoke. This is done by importing the revocation certificate using the `--import` command." The text GnuPG writes into the automatic certificate says when to prefer this: "if the secret key is still accessible, it is better to generate a new revocation certificate and give a reason for the revocation."

The procedure, written into [desktop/README_DESKTOP.md](../../../desktop/README_DESKTOP.md) by task 9.2. Every step runs on the owner's own machine, never in an agent session or a workflow:

1. At key creation (task 7.9): copy `~/.gnupg/openpgp-revocs.d/<fingerprint>.rev` to the same offline storage as the private key, and keep both away from the working disk.
2. When the key leaks, is lost, or has to be retired: if the private key is still available, make a certificate with a reason with `gpg --output installation-helper-revocation.asc --generate-revocation <fingerprint>`. Otherwise take the offline `.rev` file and remove the colon in front of its five dashes. Import the certificate with `gpg --import <file>`, so the owner's own keyring marks the key revoked and it cannot sign by mistake.
3. Generate the new key with the command of task 7.9, export its public key over `desktop/packaging/flatpak/installation-helper.gpg`, and replace both environment secrets with `gh secret set FLATPAK_GPG_PRIVATE_KEY --env github-pages` and `gh secret set FLATPAK_GPG_PASSPHRASE --env github-pages`. The fingerprint check of the Pages job (item 3 of the key decision above) refuses to sign until the committed public key and the secret are the same new key, which is the intended guard against doing only half of this step.
4. Commit the new public key when the owner decides, then dispatch the Pages workflow for the current published tag. The site's `.flatpakrepo` and `.flatpakref` then carry the new key.
5. Tell users, in the notes of the next release and in a short "signing key changed" note in [README.md](../../../README.md), to remove and re-add the remote. Removing is what drops the old key: `flatpak remote-modify --gpg-import=FILE` is documented in `doc/flatpak-remote-modify.xml` of https://github.com/flatpak/flatpak (last changed 2025-12-08) as "Import gpg keys from the specified keyring file as trusted for the new remote", which adds a key and says nothing about removing the old one, so after a leak the old key would stay trusted. The user commands, each its own block in the README:

   ```bash
   flatpak remote-delete --user --force installation-helper
   ```

   ```bash
   flatpak remote-add --user --if-not-exists installation-helper https://lukk17.github.io/InstallationHelper/installation-helper.flatpakrepo
   ```

   ```bash
   flatpak update --user io.github.lukk17.InstallationHelper
   ```

   `--force` is needed because the application is installed from that remote: `doc/flatpak-remote-delete.xml` says "Remove remote even if its in use by installed apps or runtimes." Whether the installed application then updates from the re-added remote of the same name, without a reinstall, is not measured here. Task 7.12 measures it, and the README gives a reinstall instead if it does not.
6. Users of the single-file bundle and of every other artifact are not affected, because nothing else is signed with this key.

Nothing in the Flatpak documentation read for this decision describes a way for a remote to deliver a revocation to its users, so the procedure treats re-adding the remote as the only way the old key leaves a user's machine. That is an inference from what the documentation does not say, not a measurement.

The files on the site:

```text
https://lukk17.github.io/InstallationHelper/
  installation-helper.flatpakrepo   [Flatpak Repo] Title, Url=https://lukk17.github.io/InstallationHelper/repo/, Homepage, Comment, GPGKey
  installation-helper.flatpakref    [Flatpak Ref] Name=io.github.lukk17.InstallationHelper, Branch=master, Url (same as above), SuggestRemoteName=installation-helper, RuntimeRepo=https://dl.flathub.org/repo/flathub.flatpakrepo, IsRuntime=false, GPGKey
  repo/                             the signed OSTree repository
```

A Pages deployment replaces the whole site, so the job builds the repository from nothing each time, holding only the version being deployed: `flatpak build-import-bundle --gpg-sign=<keyid> repo installation-helper-<version>.flatpak`, then `flatpak build-update-repo --gpg-sign=<keyid> --generate-static-deltas --prune --title="Installation Helper" repo`. A user's `flatpak update` still works, because it only needs the newest commit. The cost is that older versions cannot be installed from the remote, which the release assets cover. The job imports the `.flatpak` asset of the published release rather than building again, so the binary in the remote is the one the release smoke test passed. Before upload it fails if `find _site -type l` or `find _site -type f -links +1` prints anything, because of the no-links rule quoted above, and it prints the site size, which must stay under 1 GB. One version of the application plus the GNOME runtime reference is expected to be far below that, measured in task 7.11. At 100 GB per month the soft bandwidth limit allows well over a thousand full installs a month, an estimate from the bundle size that task 8.4 replaces with the measured size.

The workflow is [.github/workflows/desktop-flatpak-pages.yml](../../../.github/workflows/desktop-flatpak-pages.yml), separate from the release workflow and `workflow_dispatch` only, following the rule from the header of [.github/workflows/e2e-manual.yaml](../../../.github/workflows/e2e-manual.yaml) that no workflow starts on push or any other automatic event. It takes the tag as input and refuses a release that is still a draft (`gh release view "$TAG" --json isDraft`), so nothing reaches the public remote before the owner publishes the release. Permissions `contents: read`, `pages: write`, `id-token: write`, `environment: github-pages`, and a `concurrency` group so two deployments never overlap.

What the user types, in the README:

```bash
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
```

```bash
flatpak remote-add --user --if-not-exists installation-helper https://lukk17.github.io/InstallationHelper/installation-helper.flatpakrepo
```

```bash
flatpak install --user installation-helper io.github.lukk17.InstallationHelper
```

Or the one-step form, which adds the remote from `SuggestRemoteName` and finds the runtime through `RuntimeRepo`:

```bash
flatpak install --user https://lukk17.github.io/InstallationHelper/installation-helper.flatpakref
```

The Flathub line is there because a `.flatpakrepo` carries no runtime location, unlike a `.flatpakref`, and the GNOME runtime comes from Flathub. `--user` matches the single-file bundle's `flatpak install --user` and needs no administrator. The owner's sketch of 2026-10-11 had no `--user`. Dropping it from every command installs for all users instead, which the README mentions in one sentence. Whether project site paths on GitHub Pages are case-sensitive, and so whether `InstallationHelper` must be typed with its capitals, is measured with `curl -I` in task 7.11 rather than assumed.

### Decision 13: The release workflow

[.github/workflows/desktop-release.yml](../../../.github/workflows/desktop-release.yml):

```yaml
name: Desktop - build and attach release artifacts
on:
  workflow_dispatch:
    inputs:
      tag:
        description: Existing tag to build, for example v0.1.0
        required: true
        type: string
permissions:
  contents: write
```

The header comment repeats the rule from [.github/workflows/e2e-manual.yaml](../../../.github/workflows/e2e-manual.yaml) that no workflow starts on an automatic event. Tag push was considered and rejected for that reason.

Jobs, all checking out `ref: ${{ inputs.tag }}`:

1. `payload` on `ubuntu-24.04`: fails unless the tag exists (`git rev-parse --verify "refs/tags/$TAG"`), runs `dart run tool/build_payload.dart --tag "$TAG"`, uploads `desktop/assets/payload/` as a workflow artifact. Every build job downloads it, so all artifacts carry the identical payload.
2. `test` on `ubuntu-24.04`, `windows-latest` and `macos-26` as a matrix: `flutter analyze` and `flutter test`, plus `flutter test integration_test` with `xvfb-run -a` on Linux.
3. `windows` on `windows-latest`, needs payload and test: Inno Setup 6, `fastforge package --platform windows --targets exe,zip`, fill the winget templates, then the smoke tests: install with `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /ALLUSERS`, run the installed copy under `C:\Program Files\Installation Helper` with `--self-test --allow-administrator --report report.json`, uninstall, install again with `/CURRENTUSER`, run the copy under `%LOCALAPPDATA%\Programs\Installation Helper` the same way, and the same from the extracted zip. The hosted runner is already elevated with User Account Control off, so neither mode shows a prompt there. The prompt itself is checked by hand in task 7.2.
4. `linux` on `ubuntu-24.04`: `sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev locate xvfb`, appimagetool from https://github.com/AppImage/appimagetool/releases (release 1.9.1 of 2025-11-18 measured as the newest numbered one, the `continuous` tag is newer and is not used), `fastforge package --platform linux --targets appimage`, the tar, then `xvfb-run -a` self-tests of the tar bundle and of the AppImage.
5. `flatpak` on `ubuntu-24.04`, needs linux: download the built bundle, `flatpak-builder` as in decision 12.3, `flatpak install --user -y` the bundle, `xvfb-run -a flatpak run io.github.lukk17.InstallationHelper --self-test --report report.json`.
6. `snap` on `ubuntu-24.04`, needs payload: `snapcore/action-build@v1` with `path: .` and the snapcraft.yaml location, then `sudo snap install --dangerous --classic` and an `xvfb-run -a` self-test.
7. `macos` on `macos-26`: `flutter build macos --release`, `npm install -g appdmg`, `fastforge package --platform macos --targets dmg,zip`, smoke test with `hdiutil attach`, copy to a temporary folder, run `Contents/MacOS/installation_helper --self-test --report report.json`. The runner already has Homebrew bash, as [e2e/tier1/workflow_parity.sh](../../../e2e/tier1/workflow_parity.sh) records for the existing macOS jobs, so the listing works. Without it the self-test would fail at the bash 4 refusal, which the prerequisite screen handles on a real machine.
8. `release` on `ubuntu-24.04`, needs every job above: `gh release create "$TAG" --draft --verify-tag --title "$TAG" --notes-file <generated notes>` when no release exists, otherwise `gh release upload "$TAG" <files> --clobber` onto the existing draft. The files include the filled Homebrew cask `installation-helper.rb` of decision 12.5. It refuses to touch a published release, and it never commits or pushes to any repository, this one included. Publishing stays a click by the owner, and so does the follow-up commit of the cask.

The tag is `vX.Y.Z` and the application version equals it without the `v`, as the owner accepted on 2026-10-11 (answer 7). The `payload` job fails when `version:` in `desktop/pubspec.yaml`, without its `+build` part, differs from the tag.

The Flatpak repository on GitHub Pages is deployed by the second dispatch-only workflow of decision 12.6, after the owner has published the release, never by this one.

Every job sets `timeout-minutes`. Values are estimates until the first run, then recorded in [e2e/run_durations.md](../../../e2e/run_durations.md): payload 10, test 30, windows 60, linux 45, flatpak 60, snap 60, macos 60, release 15, and in the Pages workflow 30 for the build and 15 for the deployment, the last being above the 10 minute deployment timeout GitHub Pages enforces itself.

### Decision 14: Tests and gates

| Layer | What | Where | Runs in |
|---|---|---|---|
| Unit | `WizardArguments`, `OutputLines`, `ProgressParser`, `PromptDetector`, the prompt inventory against `setup/contract/interactive_prompts.json`, `EnvironmentSanitizer`, catalogue and result decoders, exit code meanings, payload checksum logic | `desktop/test/domain/` | `flutter test` |
| Widget | each screen with fake ports: catalogue error, filter, profile disables checklist, preview, progress list rows and statuses, "Show details" as read-only text, password dialog with OK, Cancel and the retry message, reboot buttons, the unexpected question dialog and its 15 minute timeout, cancel, summary with missing result file | `desktop/test/ui/` | `flutter test` |
| Integration | real `NativePtyLauncher` against `desktop/integration_test/fixtures/fake_wizard.sh` and `fake_wizard.ps1`, which print progress lines in the formats of decision 7.2, a sudo-style prompt with `read -s`, a refusal line, an unknown question, echo a marker when the right input arrives, ask the reboot question, honour an interrupt and exit with a requested code | `desktop/integration_test/` | `flutter test integration_test` on all three runners |
| Prompts | every interactive `read` in setup.sh is listed in `setup/contract/interactive_prompts.json`, and every other `read` is a redirected loop or a here-string | new `e2e/tier1/wizard_prompts.sh` | `bash e2e/run.sh` |
| Static | no terminal widget in the application, macOS sandbox off, Windows manifest `asInvoker`, no group_vars read | new `e2e/tier1/desktop_static.sh` | `bash e2e/run.sh` |
| Contract | the real wizards: `--list-software --json` decodes, `WizardArguments` output passed to `--print-command` and `-PrintPlan` resolves to exactly the ticked keys | `desktop/integration_test/wizard_contract_test.dart` | all three runners |
| Script | JSON listing equals text listing, schemas validate, group parity, verdict table complete, result file on success, missing and early exit | new `e2e/tier1/machine_output.sh` and Pester tests in [e2e/tier1/windows/](../../../e2e/tier1/windows/) | `bash e2e/run.sh` |
| Workflow | every workflow is dispatch-only or call-only | new `e2e/tier1/workflow_triggers.sh` | `bash e2e/run.sh` |
| Cask | `Casks/installation-helper.rb` equals the template except `version` and `sha256`, no `.rb` file in the repository root | new `e2e/tier1/homebrew_cask.sh` | `bash e2e/run.sh` |
| Container | result file in a real run and in the forced-failure run | existing scenarios with a result path added | `bash e2e/run.sh --tier 3 --scenario forced-failure` and `--scenario defaults --os debian` |
| Artifact | `--self-test` of every artifact | release workflow | each dispatch |
| Manual | a real run through the GUI on each platform, listed in [e2e/manual_test_matrix.md](../../../e2e/manual_test_matrix.md) | virtual machines | before the first published release |

Schema validation in tier 1 uses the Python `jsonschema` package, imported the same way existing checks import `yaml`, and [e2e/README_E2E.md](../../../e2e/README_E2E.md) gains it in its prerequisites.

The fake wizards are test fixtures that stay in the repository, not throwaway scripts. They exist because a real `setup.sh` run asks for a real sudo password and installs software, which a unit or integration test must never do.

### Decision 15: Documentation

1. [README.md](../../../README.md): a new section "Install the desktop app" after "Quick start", following the README standard in the owner's rules: one command per block, PowerShell and Unix shell forms, every format. Also the docs map gains [desktop/README_DESKTOP.md](../../../desktop/README_DESKTOP.md).
2. [desktop/README_DESKTOP.md](../../../desktop/README_DESKTOP.md): hub page for the directory, architecture diagram from decision 2, how to build each artifact locally, how to run the tests, how a release is cut and the Flatpak repository deployed, the three owner commands of decision 12.5 that commit the filled cask to `Casks/installation-helper.rb` after each published release, how the signing key was made and where it lives (never the key itself), the privilege rule and why, and the section "How the app asks for passwords and administrator rights" from this document in user words.
3. [setup/README_SETUP.md](../../../setup/README_SETUP.md): the new options.
4. [AGENTS.md](../../../AGENTS.md): "What This Repo Is" gains `desktop/` as the fourth part and one sentence saying the top-level `Casks/` folder is the Homebrew tap and no `.rb` file may sit in the repository root, the hub list in "Documentation Conventions" gains its hub page, and the CI section names the release workflow and the Flatpak Pages workflow as the third and fourth dispatch-only workflows, with the two GitHub Actions secrets the Pages workflow reads.
5. [docs/regression_ledger.md](../../../docs/regression_ledger.md): every defect found or introduced, as AGENTS.md requires.

## Risks / Trade-offs

- [The pseudo terminal does not reach the host's sudo through flatpak-spawn] → Spike 1 first, fallback A with host-side `script`, fallback B drop the Flatpak bundle and repository and record the measured output in the ledger, as the owner agreed on 2026-10-11.
- [The Flatpak signing key is lost or leaks] → the owner holds the only offline copy and the revocation certificate, the private key exists elsewhere only as an environment secret, and the Pages job refuses a key whose fingerprint differs from the committed public key. A lost or leaked key means the revocation and rotation procedure of decision 12.6: revoke, a new key, new secrets, and every user removing and re-adding the remote, which the README then says.
- [The key never expires, so a leaked key stays valid for users until they act] → accepted by the owner on 2026-10-11 (answer 12), because an expiry stops every user's updates on a fixed date. The revocation procedure of decision 12.6 is the replacement.
- [The Pages site grows past 1 GB or past the 100 GB per month soft bandwidth limit] → one version per deployment, size printed and checked by the job, bandwidth checked against the measured bundle size in task 8.4.
- [An administrator install puts the application under Program Files, while the application must never run elevated] → the manifest stays `asInvoker`, the post-install launch runs as the original user, and the elevation refusal of decision 8 catches the one case Inno Setup cannot.
- [flutter_pty2 is two weeks old in its 2.0 form, flutter_pty is unmaintained] → Spike 4 on all three systems, everything behind `PtyLauncher`, flutter_pty as the second choice.
- [The progress list misses lines because a producer changed its wording] → the list is live feedback only, the summary comes from the result file, unrecognised lines stay behind "Show details", and the unit test of decision 7.2 reads each format string from the file that prints it.
- [The wizard waits on a question nobody expected, behind a screen with no terminal] → the unexpected question dialog after 3 quiet seconds on a partial line, the "Answer a question" button after 2 minutes without output, the 15 minute stop, and `e2e/tier1/wizard_prompts.sh` keeping the inventory equal to the interactive reads in setup.sh.
- [A classic snap with bundled GTK may clash with host GTK modules or not draw at all] → Spike 2 on Ubuntu, Fedora and Debian hosts before any Snap work beyond the spike.
- [Unknown base libraries on fresh CachyOS and Arch] → Spike 3, and the README claims only what was measured.
- [Packaging environment variables leaking into host tools] → `EnvironmentSanitizer`, measured per format in task 2.6, asserted by the self-test printing the run environment.
- [Artifacts about 29 MB bigger than first estimated because of the KDE profile and wallpapers] → accepted by the owner on 2026-10-11 in exchange for every artifact working offline, measured sizes recorded in task 8.4.
- [The Flatpak has full host access and is not a sandbox] → stated in the README and in the metainfo description, no Flathub submission.
- [An unsigned macOS app and an unsigned Windows installer trigger Gatekeeper and SmartScreen warnings] → accepted by the owner, README walks through both.
- [Prompt patterns drift from the scripts' wording] → the unit test reads the patterns' source lines from setup.sh itself, and the inventory check of decision 7.4 fails on a new interactive `read`.
- [A Windows runner is elevated, which the application refuses] → `--allow-administrator` limited to `--self-test`, refused otherwise, spec scenario.
- [A run is cancelled half way] → the wizards already treat an interrupt as exit 130 and the summary says so. The machine may be half configured, exactly as after Ctrl+C in a terminal, and the summary says that too.
- [Fastforge documents Inno Setup 6 while 7 exists] → install 6 explicitly in the workflow.
- [A user types the short `brew tap Lukk17/installationhelper` without the URL] → it fails, because no `homebrew-installationhelper` repository exists. The README warns next to the command, and task 7.8 confirms the failure so the warning is accurate.
- [The follow-up cask commit is forgotten after a release] → the tap keeps offering the previous version, which still installs and works. The release checklist in [desktop/README_DESKTOP.md](../../../desktop/README_DESKTOP.md) carries the step, and the cask asset on the release makes it three commands.
- [The committed cask drifts from its template, or a `.rb` file lands in the repository root and Homebrew reads it as a formula] → `e2e/tier1/homebrew_cask.sh`.
- [Every tap clones this whole repository, 92188 KB on 2026-10-11] → accepted by the owner with route B.

## Migration Plan

Additive only. The wizards gain options and keep every existing behaviour, proven by the existing tier 1 checks staying green. The application ships first as a draft release the owner tests by hand against [e2e/manual_test_matrix.md](../../../e2e/manual_test_matrix.md), then publishes. Rollback is deleting the release assets, and, if needed, reverting the commits under [desktop/](../../../desktop/), which nothing else depends on. The new script options can stay even then, because they are useful to any caller.

## Open Questions

### Answered by the owner on 2026-10-11

The numbers are the ones the questions had in this document, so earlier references still match, which is why they are written out rather than left to the list numbering.

- Question 1. Payload size. Bundle the whole `setup/` directory, the KDE profile and the wallpapers included. Accepted. No playbook change, every artifact works offline.
- Question 2. Toggle groups from the group_vars comment headings, in the JSON listing of both wizards, with a parity check in tier 1. Accepted.
- Question 3. Where the Homebrew cask lives. Route B, against the earlier recommendation of a second repository `Lukk17/homebrew-installationhelper`: no second repository, the cask in a top-level `Casks/` folder of this repository, tapped with `brew tap Lukk17/installationhelper https://github.com/Lukk17/InstallationHelper` and installed with `brew install --cask Lukk17/installationhelper/installation-helper`. The trade-offs became the accepted consequences listed in decision 12.5, which also decides how the filled cask reaches `master` without any automatic commit.
- Question 4. On macOS without Homebrew, a button that runs Homebrew's official installer after showing the exact command. Accepted, decision 10 item 3.
- Question 5. A signed Flatpak repository on GitHub Pages. Moved into this change, with a generated GPG signing key, decision 12.6. The single-file bundle stays.
- Question 6. If spike 1 and fallback A both fail, drop the Flatpak and record the measured output in the ledger. Accepted, decision 6.2.
- Question 7. Release tags `vX.Y.Z`, equal to the application version. Accepted, decision 13.
- Question 8. Windows installer scope. Changed from the recommendation: install for all users by default, because some of the software the setup installs is machine-wide, with the current user only as a choice in a dialog and through `/CURRENTUSER`. The administrator prompt appears only during installation, and the installed application still runs as the normal user, because setup.ps1 refuses to run elevated. Decisions 8 and 12.1, winget manifest in 12.2.
- Committing this proposal. Approved, with no change to these files.
- Question 10. The user id of the Flatpak signing key: `Lukk17 <luksarna@gmail.com>`, the owner's GitHub user name and the address he gave for this purpose. Decision 12.6, which also records why the key is Ed25519 and the measurement behind it.
- Question 11. The secret names `FLATPAK_GPG_PRIVATE_KEY` and `FLATPAK_GPG_PASSPHRASE`, on the `github-pages` environment. Confirmed, decision 12.6.
- Question 12. The expiry of the Flatpak signing key. No expiry, `never`, as recommended, decided on 2026-10-11. What replaces the expiry is the revocation and key rotation procedure in decision 12.6: the revocation certificate GnuPG writes at key creation, kept offline by the owner, and the steps to rotate the key and tell users to re-add the remote. Task 7.9 is no longer blocked. The measured reason, kept as it was recorded: the owner's example command of 2026-10-11 ended in `2y`, while decision 12.6 had `never`. With an expiry, every user's updates stop verifying on the expiry date, and extending the key does not help them until each user imports the extended public key again. Measured on 2026-10-11 with the same WSL Ubuntu 24.04, libostree 2024.5 and GnuPG 2.4.4 setup as decision 12.6, using a throwaway Ed25519 key made with `seconds=40` as the expiry: a pull before the expiry exited 0. After it, both a fresh client and one that had pulled before exited 1 with "BAD signature from ..." and "Key expired Sun Oct 11 03:11:38 2026". The owner side then ran `gpg --quick-set-expire <fingerprint> never` and signed a new commit and summary, and the existing client still exited 1 with the same message. Only after `ostree remote gpg-import` of the extended public key into that client did its pull exit 0. So a two-year key means every user runs a key import every two years, or updates stop. The recommendation was `never`, with the offline revocation certificate as the way to retire the key, and the owner accepted it.
- Question 19.1. Whether the application shows a terminal. It never does, decided on 2026-10-11. The xterm package and every terminal-style output panel are gone from the design. The pseudo terminal stays only as a hidden channel, because setup.sh reads the sudo password from a terminal. The main run screen is a progress list built from the script's output, the raw output sits behind "Show details" as plain read-only text, the password, the reboot question and any unexpected question are dialogs or buttons of the application, and on Windows the only prompt is Windows' own User Account Control. Decisions 2, 4 and 7, and the section "How the app asks for passwords and administrator rights".

### Still open

None.
