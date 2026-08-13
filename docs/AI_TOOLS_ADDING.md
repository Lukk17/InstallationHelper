# Adding a new npm-based AI / CLI tool

This is the recipe for adding any tool that's published as a global npm package
(Claude Code, OpenCode, OpenSpec, Bruno CLI, etc.). For tools shipped only as
a brew formula, OS package, or AppImage, use the existing `software_installer`
dispatcher instead — see [setup/software.md](../setup/software.md).

---

### When to use this path

Use the npm-install pattern when **all** of these are true:

- The tool's primary distribution is `npm install -g <pkg>`.
- It must work on Linux + Windows (and optionally macOS).
- It has no native package on Linux distros (no apt / dnf / pacman / AUR).

If macOS has a Homebrew formula (e.g. `bruno-cli`), prefer that path on macOS
and use npm only on Linux + Windows. See the "Mixed macOS path" section below.

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
# This file covers Linux + Windows via npm.
- name: Include <tool> Unix tasks
  ansible.builtin.include_tasks: <tool>_unix.yaml
  when:
    - ansible_facts['os_family'] != 'Windows'
    - ansible_facts['os_family'] != 'Darwin'
    - install_<tool> | default(false) | bool

- name: Include <tool> Windows tasks
  ansible.builtin.include_tasks: <tool>_windows.yaml
  when:
    - ansible_facts['os_family'] == 'Windows'
    - install_<tool> | default(false) | bool
```

If the tool has no macOS brew formula (i.e. macOS goes through npm too),
drop the `os_family != 'Darwin'` guard on the Unix include.

#### 4. Create the per-OS wrappers

`setup/ansible/roles/ai_tools/tasks/<tool>_unix.yaml`:

```yaml
---
- name: Install <Tool> CLI via npm helper
  ansible.builtin.include_tasks: npm_install_unix.yaml
  vars:
    npm_pkg: "<npm-package-name>"
    npm_display_name: "<Tool>"
```

`setup/ansible/roles/ai_tools/tasks/<tool>_windows.yaml`:

```yaml
---
- name: Install <Tool> CLI via npm helper (Windows)
  ansible.builtin.include_tasks: npm_install_windows.yaml
  vars:
    npm_pkg: "<npm-package-name>"
    npm_display_name: "<Tool>"
```

Both helpers handle: nvm/npm probe, warn-skip on missing, idempotent
`npm list -g` check, install with secure `chdir`, async + retry on flaky
network. You inherit all of that for free.

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

### Mixed macOS path (npm on Linux/Windows, brew on macOS)

This is the pattern Bruno CLI uses. Same toggle drives two install paths:

| OS | Path | Tag that triggers it |
|---|---|---|
| macOS | `software_installer` → `vars/Darwin.yaml` mapping → `brew install <formula>` | `--tags brew` or `--tags software` |
| Linux | `ai_tools` role → npm helper | `--tags <tool>` or `--tags ai` |
| Windows | `ai_tools` role → npm helper | `--tags <tool>` or `--tags ai` |

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

#### `npm_install_windows.yaml`

| Var | Required | Description |
|---|---|---|
| `npm_pkg` | yes | Full npm package spec |
| `npm_display_name` | yes | Human label |
| `npm_install_extra_args` | no | Extra args appended to `npm install -g` |

Behaviour:

- Probes `where.exe npm`. Skips with debug message if not on PATH.
- Anchors `chdir` at `{{ ansible_env.USERPROFILE }}`.
- Idempotent via `npm list -g <pkg>`.

---

### Windows administrator posture

`npm install -g` on Windows writes to `%AppData%\Roaming\npm` when run from
an unprivileged shell, and to `%ProgramFiles%\nodejs\node_modules` when run
elevated. Lifecycle scripts in transitive dependencies execute with the
invoking shell's privileges. **Always run this playbook from a non-elevated
PowerShell**; the rest of the playbook does not need Administrator for the
npm path. Chocolatey tasks that legitimately need elevation prompt via UAC
on their own.

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

All six go through the helpers — look at any of their `*_unix.yaml` /
`*_windows.yaml` files (each is 5 lines) for a working reference.
