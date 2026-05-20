# AGENTS.md

This file provides shared instructions to all AI coding agents working in this repository (Claude Code, Kilo Code, OpenCode, Codex CLI). Standards and skills are imported from [agent-standards](https://github.com/Lukk17/agent-standards).

## Skills

This project includes agent skills in `.agents/skills/`. Invoke relevant skills before starting implementation work. Examples:

- `/code-reviewer` before reviewing code
- `/security-review` before auditing for vulnerabilities
- `/coding-standards` before writing new code
- `/tdd-workflow` before adding features or fixing bugs

Slash commands may appear as `/name` or `/name.md` in your agent's autocomplete — use whichever your agent shows.

## Subagents

This project ships 26 specialised subagents — narrow-scope agents the main session delegates to. Claude Code reads `.claude/agents/`; OpenCode and Kilo Code both read `.opencode/agents/`. Codex CLI has no per-agent file mechanism — it sees `AGENTS.md` plus skills only.

These files are generated artifacts pulled from agent-standards. Do **not** hand-edit them — changes will be overwritten on the next pull. To modify a subagent permanently, edit its canonical source in the agent-standards repo (`subagents/<name>.md`), regenerate there, and re-import.

A few of the most-used:

- `code-reviewer` — security-aware diff review before merge
- `test-automator` — write missing tests and fix failures without weakening assertions
- `security-auditor` — threat modelling, secure-coding review, compliance gap analysis
- `backend-architect` — contract-first service and API design
- `database-expert` — schema design and query / index optimisation
- `debugger` — root-cause analysis for a single failing test or runtime error
- `devops-troubleshooter` — live incident response with postmortem

Full catalogue: see the agent-standards README's "Subagents catalog" section, or list `.claude/agents/*.md` (or `.opencode/agents/*.md`) in this project.

## MCP servers

This project may expose MCP tools (Context7 docs, MongoDB introspection, Grafana, Playwright, Chrome DevTools, Redis, SonarQube, n8n). Check your tool list at startup and use them when they're a better fit than re-deriving the answer from local files. Human-side setup lives in [`docs/MCP_SETUP.md`](docs/MCP_SETUP.md).

## Working With Agents

All supported agents read this `AGENTS.md` from the project root and auto-discover skills from `.agents/skills/`. Start your agent from the project root:

- **Claude Code** — run `claude`. Reads `.claude/CLAUDE.md`, which imports this file.
- **Kilo Code** — reads `AGENTS.md` automatically. Optional `kilo.jsonc` for extra config.
- **OpenCode** — reads `AGENTS.md` automatically. Optional `opencode.json` at project root.
- **Codex CLI** — run `codex`. Reads `AGENTS.md` automatically. Global settings in `~/.codex/config.toml`.

## Working Principles

Apply these to every task, in order. They govern *how* you work; the `coding-standards` skill governs *what the code should look like*.

### 1. Think Before Coding

State assumptions explicitly. When the prompt is ambiguous, surface the interpretations and ask — do not pick one silently and run with it. If a simpler approach exists, propose it before writing code. Stop and ask when genuinely unsure — a clarifying question costs less than a wrong implementation.

### 2. Simplicity First

Write the minimum code that solves the problem.

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for scenarios that cannot happen.
- If 200 lines could be 50, rewrite it.

Test: would a senior engineer call this overcomplicated? If yes, simplify.

### 3. Surgical Changes

Touch only what the task requires.

- Do not "improve" adjacent code, comments, or formatting.
- Do not refactor code that is not broken.
- Match existing style, even if you would write it differently.
- If you notice unrelated dead code, mention it — do not delete it.
- Remove imports, variables, and helpers that *your* changes orphan. Leave pre-existing dead code alone unless asked.

Test: every changed line should trace directly to the request.

### 4. Goal-Driven Execution

Define success before starting. Convert vague asks into verifiable goals:

| Instead of...       | Transform to...                                                       |
| ------------------- | --------------------------------------------------------------------- |
| "Add validation"    | "Write tests for invalid inputs, then make them pass"                 |
| "Fix the bug"       | "Write a failing test that reproduces it, then make it pass"          |
| "Refactor X"        | "Ensure tests pass before and after, behavior unchanged"              |

For multi-step work, state the plan first:

1. `<step>` → verify: `<check>`
2. `<step>` → verify: `<check>`
3. `<step>` → verify: `<check>`

Then loop until each check passes. Do not claim a task is done without running the verification.

## OpenSpec Workflow

This project uses [OpenSpec](https://github.com/Fission-AI/OpenSpec) for spec-driven development. Specs and changes live under `openspec/`.

The full lifecycle (run inside your agent shell):

1. **Propose a change** — agent generates proposal, design, and `tasks.md` under `openspec/changes/`:
   ```text
   /opsx:propose add dark mode support
   ```
2. **Apply the code** — after reviewing/editing `tasks.md`, agent implements and checks off tasks:
   ```text
   /opsx:apply
   ```
3. **Verify and refine** — pass back logs or bug reports to refine:
   ```text
   /opsx:verify The toggle button is invisible on mobile. Fix it.
   ```
4. **Archive** — once tested, merge delta specs into `openspec/specs/` and archive the change folder:
   ```text
   /opsx:archive
   ```

Some agents render commands as `/opsx-propose.md` instead of `/opsx:propose` — both work; use what appears in your autocomplete.

Use multiline prompts when you need to include logs or detailed context with a command.

## What This Repo Is

A cross-platform Ansible-based system setup and local development toolkit. It has two main parts:

1. **`setup/`** — Ansible playbook to automate OS configuration and software installation across Ubuntu/Debian, Fedora, Arch Linux, macOS, and Windows (via WSL).
2. **`local-dev/`** — Docker Compose stack for local development services (MySQL, PostgreSQL, MongoDB, Keycloak).

## Ansible Architecture

The playbook (`site.yaml`) follows this execution order:

1. **Pre-tasks**: Loads OS-specific group vars (`group_vars/{linux,macos,windows}.yaml`) and the OS translation dictionary (`vars/{Debian,RedHat,Archlinux,Darwin,Windows}.yaml`) as `os_dict`.
2. **OS core roles**: `windows_core`, `macos_core`, `arch_core`, `fedora_core`, `system_core` — bootstrap the specific OS.
3. **Desktop environments**: `kde_plasma_setup`, `gnome_setup` — gated by `install_kde_plasma`/`configure_kde_plasma` and `install_gnome`/`configure_gnome` flags.
4. **Cross-platform settings**: `env_variables`, `shell_zsh`.
5. **Complex roles**: `sdk_manager` (Pyenv, NVM, SDKMAN, FVM, Android SDK, Dart/Flutter), `ai_tools` (Claude Code, Claude Desktop, OpenCode, OpenSpec).
6. **Software router**: `software_installer` — dynamic package dispatch using `os_dict`.
7. **Linux advanced**: `systemd_boot`, `waydroid`, `linux_crypto_hardware`, `linux_security`, `virtualization_config`.

### Configuration Files

| File | Purpose |
|---|---|
| `group_vars/all.yaml` | Master toggle file — enable/disable apps cross-platform |
| `group_vars/linux.yaml` | Linux-only toggles (DEs, system settings, Linux-specific apps) |
| `group_vars/macos.yaml` | macOS-only toggles |
| `group_vars/windows.yaml` | Windows-only toggles |
| `group_vars/versions.yaml` | Pinned version numbers for tools |
| `vars/{OS}.yaml` | Translation dictionaries mapping generic app name → `{manager, package}` |
| `profiles/linux_live.yaml` | Override profile for USB/live installs |
| `SOFTWARE.md` | Complete per-OS software list with installation methods |

### How Software Installation Works

`group_vars/all.yaml` declares intent (`install_chrome: true`). The OS dictionary (`vars/Debian.yaml`, etc.) maps each app to a package manager and package name:

```yaml
chrome: { manager: "apt", package: "google-chrome-stable" }
```

The `software_installer` role (`roles/software_installer/tasks/dynamic_install.yaml`) iterates over enabled toggles, looks up the OS dict, and dispatches to the correct package manager. Supported managers: `apt`, `apt_url`, `dnf`, `dnf_url`, `dnf_repo`, `pacman`, `aur`, `snap`, `flatpak`, `brew`, `brew_cask`, `choco`, `winget`.

**Package manager priority per OS:**
- **Windows:** Official installer > Chocolatey > Winget
- **macOS:** DMG/PKG > Homebrew Cask (GUI) / Formula (CLI) > MAS
- **Debian/Ubuntu:** Official APT repo > Flatpak > Snap > Default APT
- **Fedora:** Official DNF repo > Flatpak > Snap > Default DNF
- **Arch:** Official Pacman > AUR (`yay`) > Flatpak > Snap

### Adding a New Application

1. Add toggle in `group_vars/all.yaml` (or OS-specific file if Linux/macOS/Windows only).
2. Add mapping in each relevant `vars/{OS}.yaml` file under `software_mapping`.
3. If the app requires custom install logic (e.g., SDK management, binary downloads), create a dedicated task file under the appropriate role.

### Workaround: ansible-core 2.19/2.20 deserialization bug

Two parts of this playbook bypass the standard Ansible module mechanism. They look like a code-smell but are intentional defenses against an upstream bug — do NOT "clean them up" without reading this section.

**The bug**

`Module result deserialization failed: No start of json char found` — raised by the controller when it tries to deserialize a module's result. Introduced in ansible-core 2.19 by the new `_internal/_json` lazy-import system. Root cause: the ansiballz zip payload (Python module wrapper) gets cleaned up or becomes unreadable before `_return_formatted()` lazy-imports the JSON profile from it. Race triggers most often on long-running modules (>5-7 min) under heavy `/tmp` activity (dpkg postinst writes, systemd-tmpfiles).

**Affected versions:** ansible-core 2.19.0 through 2.19.9, and 2.20.0 through 2.20.5 (latest stable on both branches as of 2026-05). Fix is in [PR #86739](https://github.com/ansible/ansible/pull/86739) against `devel` — **still open and unmerged**. Pre-bug version: 2.18.x.

**Upstream tracking:** issues [#86738](https://github.com/ansible/ansible/issues/86738) and [#86562](https://github.com/ansible/ansible/issues/86562).

**Mitigations in this repo**

1. **`ansible.builtin.raw` for APT and Flatpak batched installs on Debian/Ubuntu** (`roles/software_installer/tasks/dynamic_install.yaml`). `raw` bypasses the entire Python module subsystem — no ansiballz, no JSON round-trip — so the bug class can't trigger. Gated to Debian-only because Arch/Fedora batches are small enough that they never crossed the duration threshold in past runs and the native modules stayed clean for them.

2. **Ansible tmp dirs moved out of `/tmp`** (`ansible.cfg`): `local_tmp`, `remote_tmp`, and `fact_caching_connection` all point to `~/.ansible/...` instead of `/tmp/ansible-*`. The ansiballz zip lives in `local_tmp`; moving it away from `/tmp` removes the path contention with dpkg and systemd-tmpfiles. Works on live USB too since Ubuntu Live's `$HOME` is writable.

**When this can be reverted**

Once ansible-core ships a release that contains the fix from PR #86739 — both 2.19.x and 2.20.x branches will need a patched point release. After that:
- The `raw` flatpak/apt tasks can go back to `ansible.builtin.apt` / `community.general.flatpak` with `name: <list>`.
- The `~/.ansible/tmp` paths in `ansible.cfg` can stay (better default anyway) or revert to the older `/tmp` paths.

**Mandatory recurring check (every time this playbook is touched):**

Before recommending changes to the `raw` callsites or claiming the workaround is "still needed", verify the upstream status:

1. Check the current ansible-core release that this repo's `requirements.yaml` / target hosts will use. The version is in `ansible --version` on the dev machine.
2. Confirm PR #86739 status: https://github.com/ansible/ansible/pull/86739 — merged or still open?
3. If merged, find the first release tag containing it: https://github.com/ansible/ansible/releases — both `stable-2.19` and `stable-2.20` need a patched point release.
4. If the target ansible-core version is on a release that includes the fix, schedule the revert: replace the 3 `raw` tasks (apt-batch, flatpak-batch, apt-full-upgrade) with the native modules in one change, drop `apt_raw_env` / `apt_raw_flags` from `group_vars/linux.yaml`, and update this section.
5. If still unmerged, leave the workaround in place and note the upstream status in the commit message of any related change.

The check is cheap (one `gh pr view 86739` or a `WebFetch` of the PR URL) and prevents the workaround from outliving its reason.

## Running the Ansible Playbook

All commands are run from `setup/ansible/`. Install required collections first (one-time):

```bash
cd setup/ansible
ansible-galaxy collection install -r requirements.yaml

# Standard run (any OS)
ansible-playbook site.yaml -i localhost, -c local -K

# Linux Live / USB profile
ansible-playbook site.yaml -i localhost, -c local -e "@profiles/linux_live.yaml" -K
```

The `-K` flag prompts for the sudo password. Windows must run from within WSL.

## Local Dev Stack

Start all services from the project root:

```bash
docker-compose -f ./local-dev/local-dev-docker-compose.yaml up -d
```

| Service | Port | Credentials |
|---|---|---|
| MySQL | 3306 | root / local, DB: `test-spring` |
| PostgreSQL | 5432 | postgres / local |
| MongoDB | 27017 | No auth, DB: `articles` |
| Keycloak | 9443 (HTTPS) | admin / admin; test user: lukk / test1234 (realm: `local`) |

PostgreSQL and Keycloak use custom Dockerfiles (`local-dev/postgresql/Dockerfile`, `local-dev/auth/Keycloak/Dockerfile`). Keycloak realm configs are in `local-dev/auth/Keycloak/export/`.

## KDE Plasma Profile Management

```bash
konsave -s lukk_desktop_profile          # Save current config
konsave -e lukk_desktop_profile -f       # Export to .knsv (use -f to overwrite)
konsave -i config/lukk_desktop_profile.knsv && konsave -a lukk_desktop_profile  # Import & apply
```

## Windows Development: All Ansible via WSL

**On Windows, ALL Ansible operations MUST be run via WSL (not PowerShell or Git Bash):**
- Ansible does not run natively on Windows — it requires a Linux environment
- The playbook uses POSIX-shell conditionals and path structures
- Use `wsl -d Ubuntu bash -c "..."` to avoid Git Bash path munging

**Do NOT:**
- Run `ansible-playbook` directly in PowerShell or Git Bash
- Test `setup/setup.sh` in Git Bash or PowerShell — it is a Linux-only script
- Use WSL's `/etc/os-release` to test OS detection — WSL configs differ from real Linux installs

Syntax check command:
```bash
wsl -d Ubuntu bash -c "ansible-playbook --syntax-check /mnt/d/Development/projekty-IT/InstallationHelper/setup/ansible/site.yaml"
```

**Always run this check after:**
- Making any YAML edits to playbook files
- Adding new roles or tasks
- Installing collections from requirements.yaml
- Modifying any file in `setup/ansible/`

## How to be compatible with IDE

Always output file edits using strict SEARCH/REPLACE blocks.
Ensure exact matching of existing indentation and formatting for the diff viewer to parse correctly.
Never use the built-in read tool.
If you need to read a file, use the bash tool to execute cat, head, or grep on the file path instead.

## OpenSpec Project Conventions

Project-specific rules layered on top of the canonical OpenSpec lifecycle above. When working on OpenSpec changes (in `openspec/changes/`), follow these rules:

### Before Starting Implementation
- **Never start coding automatically** - if there are questions or considerations in planning mode, always ask clarifying questions first
- Read the existing `proposal.md`, `design.md`, `spec.md`, and `tasks.md` to understand what needs to be done
- If something is unclear, ask questions before proceeding with implementation

### Detailed Planning Requirements
- The `proposal.md` file should be **very detailed-oriented** and contain all necessary information
- Include all commands, file paths, links, and specific implementation steps
- All research must be done **while planning** and creating the documentation
- The implementer should know exactly how to implement without guessing or needing additional research

### Keeping Documentation Updated
- Always keep `design.md`, `spec.md`, `tasks.md`, and `proposal.md` up to date
- Update progress in `tasks.md` immediately after completing each task or subtask
- Mark completed tasks in the markdown file as `[x]` for done, `[ ]` for pending

### Applying Tasks from OpenSpec
- When applying a task from an OpenSpec change, follow the detailed specifications in the proposal.md
- Do not deviate from the documented approach without first updating the documentation
