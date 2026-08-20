# Adding a new npm-based AI / CLI tool

This is the recipe for adding any tool that's published as a global npm package
(Claude Code, OpenCode, OpenSpec, Bruno CLI, etc.). For tools shipped only as
a brew formula, OS package, or AppImage, use the existing `software_installer`
dispatcher instead — see [setup/software.md](../setup/software.md).

---

### When to use this path

Use the npm-install pattern when **all** of these are true:

- The tool's primary distribution is `npm install -g <pkg>`.
- It must work on Linux and Windows (and optionally macOS).
- It has no native package on Linux distros (no apt / dnf / pacman / AUR).

If macOS has a Homebrew formula (e.g. `bruno-cli`), prefer that path on macOS
and use npm only on Linux and Windows. See the "Mixed macOS path" section below.

Windows is not part of the playbook at all. Ansible never runs there, so the
Windows half of every tool below lives in
[setup/windows/WindowsNpmTools.ps1](../setup/windows/WindowsNpmTools.ps1) and is
driven by [setup/setup.ps1](../setup/setup.ps1). Adding a tool means adding it in
both places, and
[e2e/tier1/windows_npm_parity.sh](../e2e/tier1/windows_npm_parity.sh) fails the
gate if you add it to one and forget the other.

---

### Step-by-step

#### 1. Add the toggle

In [setup/ansible/group_vars/all.yaml](../setup/ansible/group_vars/all.yaml),
add `install_<tool>: true` in the relevant block (e.g. under IDEs / Editors
for IDE-adjacent tools, or alongside the existing AI toggles).

```yaml
install_<tool>: true
```

#### 2. (Optional) Add the macOS brew mapping

If the tool has a Homebrew core formula, add it to
[setup/ansible/vars/Darwin.yaml](../setup/ansible/vars/Darwin.yaml) under the
appropriate section. The `software_installer` role will pick it up
automatically from the `install_<tool>` toggle:

```yaml
<tool>: { manager: "brew", package: "<formula-name>" }
```

If not, skip this step — `software_installer` silently no-ops on macOS for
this tool and the npm path below handles it via brew-installed Node.

#### 3. Create the dispatcher

Path: `setup/ansible/roles/ai_tools/tasks/<tool>.yaml`. Mirror this template:

```yaml
---
# macOS install (if any) handled by software_installer via vars/Darwin.yaml.
# This file covers Linux via npm. Windows installs it natively through
# setup/windows/WindowsNpmTools.ps1.
- name: Include <tool> Unix tasks
  ansible.builtin.include_tasks: <tool>_unix.yaml
  when:
    - ih_family != 'Darwin'
    - install_<tool> | default(false) | bool
```

If the tool has no macOS brew formula (i.e. macOS goes through npm too),
drop the `ih_family != 'Darwin'` guard and leave the toggle as the only
condition. Branch on `ih_family`, never on Ansible's own `os_family`:
[e2e/tier1/os_family_derivation.sh](../e2e/tier1/os_family_derivation.sh) fails
the gate for any task that reads the raw fact.

#### 4. Create the Unix wrapper

`setup/ansible/roles/ai_tools/tasks/<tool>_unix.yaml`:

```yaml
---
- name: Install <Tool> CLI via npm helper
  ansible.builtin.include_tasks: npm_install_unix.yaml
  vars:
    npm_pkg: "<npm-package-name>"
    npm_display_name: "<Tool>"
```

The helper handles: nvm/npm probe, warn-skip on missing, idempotent
`npm list -g` check, install with secure `chdir`, async + retry on flaky
network. You inherit all of that for free.

#### 4a. Add the Windows entry

In [setup/windows/WindowsNpmTools.ps1](../setup/windows/WindowsNpmTools.ps1),
add one line to the `$script:NpmToolPackages` table. The key is the toggle name
without its `install_` prefix, so it lines up with the software mapping keys:

```powershell
<tool> = @{ Package = '<npm-package-name>'; Display = '<Tool>' }
```

That table is the whole Windows path. `Invoke-WindowsNpmToolInstall` reads it,
applies the same idempotency check, the same two retries and the same
user-profile working directory the Unix helper does, and reports one result row
per tool. Skipping this step is a gate failure rather than a silent gap:
[e2e/tier1/windows_npm_parity.sh](../e2e/tier1/windows_npm_parity.sh) compares
that table against the `*_unix.yaml` files package by package.

#### 5. Wire the dispatcher into `main.yaml`

In [setup/ansible/roles/ai_tools/tasks/main.yaml](../setup/ansible/roles/ai_tools/tasks/main.yaml),
add the import block:

```yaml
- name: Install <Tool>
  ansible.builtin.import_tasks: <tool>.yaml
  when: install_<tool> | default(false) | bool
  tags: [<tool>]
```

The `tags: [<tool>]` line gives you `--tags <tool>` for surgical re-runs.

#### 6. Document the tag

In [setup/ansible/tags.md](../setup/ansible/tags.md), add a row to the **AI
tools subsystems** table:

```markdown
| `<tool>` | <one-line description> | `nvm` (skips with warning) |
```

#### 7. Run the syntax check

```bash
wsl -d Ubuntu bash -c "ansible-playbook --syntax-check /mnt/d/Development/projekty-IT/InstallationHelper/setup/ansible/site.yaml"
```

```powershell
wsl -d Ubuntu bash -c "ansible-playbook --syntax-check /mnt/d/Development/projekty-IT/InstallationHelper/setup/ansible/site.yaml"
```

---

### Mixed macOS path (npm on Linux and Windows, brew on macOS)

This is the pattern Bruno CLI uses. Same toggle drives two install paths:

| OS | Path | Tag that triggers it |
|---|---|---|
| macOS | `software_installer` → `vars/Darwin.yaml` mapping → `brew install <formula>` | `--tags brew` or `--tags software` |
| Linux | `ai_tools` role → npm helper | `--tags <tool>` or `--tags ai` |
| Windows | `setup.ps1` → `WindowsNpmTools.ps1` | `-EnableKey <tool>`, no Ansible involved |

A surgical `--tags <tool>` re-run is a **no-op on macOS** — the macOS install
sits under `software_installer` tags, not `ai_tools` tags. This is intentional
(matches the rest of `software_installer`) but worth knowing when debugging.

---

### Helpers reference

#### `npm_install_unix.yaml`

| Var | Required | Description |
|---|---|---|
| `npm_pkg` | yes | Full npm package spec, e.g. `@anthropic-ai/claude-code` |
| `npm_display_name` | yes | Human label used in task names and the warn message |
| `npm_install_extra_args` | no | Extra args appended to `npm install -g`, e.g. `--no-audit` |

Behaviour:

- Probes `{{ non_root_home }}/.nvm/nvm.sh`. Emits a `[WARN]` and skips if absent.
- Runs as `{{ non_root_user }}` (never root).
- Anchors `chdir` at `{{ non_root_home }}` so a hostile `.npmrc` in some other
  cwd cannot redirect the npm registry.
- `nvm use --lts` to activate Node before install.
- `timeout 600`, `async: 900`, `retries: 2` on the install task.
- Idempotent: skips install when `npm list -g <pkg>` already finds it.

#### `WindowsNpmTools.ps1`

Not an Ansible helper. Windows has no playbook path at all, so the table in
[setup/windows/WindowsNpmTools.ps1](../setup/windows/WindowsNpmTools.ps1) is
both the declaration and the installer.

| Field | Required | Description |
|---|---|---|
| `Package` | yes | Full npm package spec |
| `Display` | yes | Human label used in the wizard's summary |

Behaviour:

- Probes `Get-Command npm`. Reports every wanted tool as not installed when npm
  is absent, rather than skipping quietly.
- Runs every npm call with `%USERPROFILE%` as the working directory, so an
  `.npmrc` in an ancestor of the launch directory cannot redirect the registry.
- Idempotent via `npm list -g <pkg>`.
- Two attempts per tool, 15 seconds apart, and one failure never stops the rest.

---

### Windows administrator posture

`npm install -g` on Windows writes to `%AppData%\Roaming\npm` when run from
an unprivileged shell, and to `%ProgramFiles%\nodejs\node_modules` when run
elevated. Lifecycle scripts in transitive dependencies execute with the
invoking shell's privileges. **Always run `setup.ps1` from a non-elevated
PowerShell.** The npm path needs no Administrator at all, and the two phases
that genuinely do, the Chocolatey batch and the optional features, raise their
own consent prompt for one elevated child rather than elevating the wizard.

See [setup/README_SETUP.md](../setup/README_SETUP.md) for the canonical
Windows run instructions.

---

### Existing examples

| Tool | Toggle | npm package | macOS brew formula |
|---|---|---|---|
| Claude Code | `install_claude_code` | `@anthropic-ai/claude-code` | none (npm on macOS too) |
| OpenCode | `install_opencode` | `opencode-ai` | none |
| OpenSpec | `install_openspec` | `openspec` | none |
| Bruno CLI | `install_bruno_cli` | `@usebruno/cli` | `bruno-cli` |
| Codex | `install_codex` | `@openai/codex` | none (a `codex` cask exists, npm chosen for one code path) |
| Grok | `install_grok` | `@xai-official/grok` | none (a `grok-build` cask exists, npm chosen for one code path) |

All six go through the Unix helper on Linux and macOS, and all six are rows in
the `WindowsNpmTools.ps1` table on Windows. Look at any of the `*_unix.yaml`
files (each is 5 lines) for a working reference.
