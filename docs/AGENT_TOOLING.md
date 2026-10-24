# Agent Standards & OpenSpec

This project imports a central set of AI agent standards from a shared repo:

- Skills in `.agents/skills/`: reusable procedural guidance, read by every supported agent. Claude Code reaches them through the `.claude/skills` symlink.
- Subagents in `.agents/agents/`, the canonical set: specialised agent definitions the main session delegates to. `.opencode/agents` and `.kilo/agents` are symlinks to it, and `.claude/agents/`, `.codex/agents/` and `.github/agents/` carry generated copies in each tool's own format.
- Instructions in `AGENTS.md`: shared rules read by Claude Code, Codex CLI, OpenCode, Kilo Code and GitHub Copilot. Claude Code reads it natively from 2.1.277 as long as no `CLAUDE.md` exists in the project or above it. The root file holds what applies everywhere, and a folder's own `AGENTS.md` holds that folder's rules, as [decisions/0001_split_agents_md.md](decisions/0001_split_agents_md.md) records.
- OpenSpec scaffold for spec-driven feature work.

Where each agent finds its files:

| Agent | Instructions | Subagents | Hooks | MCP servers |
|---|---|---|---|---|
| Claude Code | `AGENTS.md`, and a folder's own when it reads a file there | `.claude/agents/` | `.claude/settings.json` | [.mcp.json](../.mcp.json) |
| Codex CLI | every `AGENTS.md` from the root down to the working directory, up to 32 KiB | `.codex/agents/*.toml` | `.codex/config.toml` | `.codex/config.toml` |
| OpenCode | `AGENTS.md` per directory, plus `.agents/instructions/reply-rules.md` through `opencode.json` | `.opencode/agents`, a symlink | the plugin `./.agents/plugin`, declared in `opencode.json` | [opencode.json](../opencode.json) |
| Kilo Code | `AGENTS.md` per directory | `.kilo/agents`, a symlink | the same plugin | [opencode.json](../opencode.json) |
| GitHub Copilot | `AGENTS.md` per directory | `.github/agents/` | `.github/hooks/preflight.json` | none in this project |

Start every agent from the repository root. Codex keeps its global settings in `~/.codex/config.toml`, beside the project's own `.codex/config.toml`.

The same standards can also be installed once per machine, in `~/.config/agents`, so every project on it gets them, as [GLOBAL_SETUP.md](GLOBAL_SETUP.md) describes.

---

### Agent standards import

The central AI standards are imported into this project via Git selective checkout. Only the production-ready folders
and the one template file are pulled in. The remote is configured as read-only: its push URL is set to an invalid address so
updates can be pulled but pushes are blocked.

#### Step 1: Initial setup

Python 3 runs the hooks. Every script in `.agents/hooks/` is Python, and every wiring throws a failed call away so a broken hook never breaks a session, which means a missing interpreter reads as an allow and the gate enforces nothing. Check that one answers. PowerShell:

```powershell
python --version
```

Unix shell:

```bash
python3 --version
```

Enable symlink support in Git (globally, or just for this repo):

```shell
git config --global core.symlinks true
```

```shell
git config core.symlinks true
```

Add the read-only remote and extract the standards:

```bash
git remote add agent-standards https://github.com/Lukk17/agent-standards
```

```bash
git remote set-url --push agent-standards no_push
```

```bash
git fetch agent-standards
```

```bash
git checkout agent-standards/master -- .agents .claude .opencode .kilo .codex .github/agents .github/hooks .vscode/mcp.json .mcp.json .github/mcp.json opencode.json docs/AGENT_TOOLING.md docs/MCP_SETUP.md docs/GLOBAL_SETUP.md docs/AGENTS-UPDATE.md AGENTS.md.example
```

Rename the one template. PowerShell:

```powershell
Rename-Item AGENTS.md.example AGENTS.md
```

Unix shell:

```bash
mv AGENTS.md.example AGENTS.md
```

Then ignore the agent task list, which `.agents/hooks/task_list_sync.py` writes to `tasks.md` at the project root, with a widget snapshot beside it. Both are per-session working state. PowerShell:

```powershell
Add-Content .gitignore "`n/tasks.md`n/.agents/tasks.widget.json"
```

Unix shell:

```bash
printf '\n/tasks.md\n/.agents/tasks.widget.json\n' >> .gitignore
```

```bash
git commit -m "Import central agent-standards"
```

What this pulls:

- `.agents/skills/`: the canonical skill files, listed in [Skills this project uses](#skills-this-project-uses), including the system ones `arch-linux`, `cachyos`, `kde-plasma`, `windows` and `macos`.
- `.agents/agents/`: the canonical subagent definitions, one markdown file each. Count them with `ls .agents/agents/*.md`.
- `.agents/hooks/`: `preflight_gate.py` and `no_ai_markers_check.py`, wired into every surface, plus the task list, markdown lint, status block and question numbering hooks. See the Hooks section of `AGENTS.md`.
- `.agents/plugin/`: `hooks.js` and `index.js`, the runner that carries those hooks into OpenCode 1.x and 2.x and Kilo Code. `opencode.json` declares it by directory, `./.agents/plugin`.
- `.agents/instructions/reply-rules.md`: the reply rules, loaded through the `instructions` key of `opencode.json` and, on OpenCode 2.x, by the plugin.
- `.claude/settings.json`, `.claude/skills` (symlink), `.claude/agents/`: Claude Code wiring and its generated copy of the subagents.
- `.opencode/agents`, `.kilo/agents`: symlinks to the canonical set.
- `.codex/config.toml`, `.codex/agents/`: Codex wiring, subagents carried as `*.toml`.
- `.github/agents/`, `.github/hooks/preflight.json`: the GitHub Copilot surface.
- `.mcp.json`, `opencode.json`, `.vscode/mcp.json`, `.github/mcp.json`: the MCP server sets, real files rather than templates.
- `docs/AGENT_TOOLING.md`, `docs/MCP_SETUP.md`, `docs/GLOBAL_SETUP.md`, `docs/AGENTS-UPDATE.md`: the shipped documents. This project keeps the first two as its own after the import, see Step 2.
- `AGENTS.md.example`: the one template, renamed to `AGENTS.md` above.

What this does not pull:

- `subagents/` (canonical templates) and `tools/` (generator) live only in the agent-standards repo and are never imported into consumer projects.

This project carries less than that pull brings in. It keeps the subagents listed in `.agents/agents/` and the skills listed under [Skills this project uses](#skills-this-project-uses), and it has no `.vscode/mcp.json`, `.github/mcp.json`, `.kilo/kilo.jsonc`, `.claude/workflows/` or `docs/AGENTS-UPDATE.md`.

#### Step 2: Pulling future updates

The routine refresh follows [AGENTS-UPDATE.md in agent-standards](https://github.com/Lukk17/agent-standards/blob/master/docs/AGENTS-UPDATE.md). It refreshes only what this project already carries, so a skill or subagent that was left out stays out, and nothing new appears behind your back. To adopt a new upstream skill or subagent, check out its path once with `git checkout agent-standards/master -- <path>`, and later refreshes keep it current.

Run everything from the repository root. Fetch upstream first:

```bash
git fetch agent-standards
```

Refresh the shipped document this project does not own. Unix shell or PowerShell, same command:

```bash
git checkout agent-standards/master -- docs/GLOBAL_SETUP.md
```

Refresh the hook scripts, the OpenCode and Kilo Code plugin, and the Copilot hook file. Unix shell:

```bash
for p in .agents/hooks .agents/plugin .github/hooks; do [ -e "$p" ] && git checkout agent-standards/master -- "$p" 2>/dev/null || true; done
```

PowerShell:

```powershell
foreach ($p in '.agents/hooks', '.agents/plugin', '.github/hooks') { if (Test-Path $p) { git checkout agent-standards/master -- $p 2>$null } }
```

Refresh every skill this project carries. A skill that does not exist upstream, such as the `openspec-*` ones, is skipped. Unix shell:

```bash
for d in .agents/skills/*/; do [ -d "$d" ] || continue; git checkout agent-standards/master -- "$d" 2>/dev/null || true; done
```

PowerShell:

```powershell
if (Test-Path .agents/skills) { foreach ($d in Get-ChildItem -Directory .agents/skills) { git checkout agent-standards/master -- ".agents/skills/$($d.Name)/" 2>$null } }
```

Refresh the reply rules. Unix shell:

```bash
for f in .agents/instructions/*.md; do [ -e "$f" ] || continue; git checkout agent-standards/master -- "$f" 2>/dev/null || true; done
```

PowerShell:

```powershell
if (Test-Path .agents/instructions) { foreach ($f in Get-ChildItem -File .agents/instructions -Filter *.md) { git checkout agent-standards/master -- ".agents/instructions/$($f.Name)" 2>$null } }
```

Refresh every subagent this project carries, in all four generated trees. Unix shell:

```bash
for f in .agents/agents/*.md .claude/agents/*.md .codex/agents/*.toml .github/agents/*.agent.md; do [ -e "$f" ] || continue; git checkout agent-standards/master -- "$f" 2>/dev/null || true; done
```

PowerShell:

```powershell
foreach ($base in '.agents/agents', '.claude/agents', '.codex/agents', '.github/agents') { if (Test-Path $base) { foreach ($f in Get-ChildItem $base -File) { git checkout agent-standards/master -- "$base/$($f.Name)" 2>$null } } }
```

Review the result before committing:

```bash
git diff --staged --stat
```

```bash
git commit -m "Update AI standards from central repository"
```

Three kinds of file stay out of the refresh:

1. This tooling document and `docs/MCP_SETUP.md`. This project owns both after the first import. This page keeps its own "Skills this project uses" section, and the upstream `docs/MCP_SETUP.md` describes the upstream server set and two MCP files this project does not carry.
2. `AGENTS.md`, which belongs to the project once renamed.
3. The four configuration files `.mcp.json`, `opencode.json`, `.codex/config.toml` and `.claude/settings.json`. Their MCP servers and any permissions belong to this project. The gate wiring in them tracks upstream: the `hooks` block of `.claude/settings.json`, the `[[hooks.*]]` tables of `.codex/config.toml`, and the `plugin` and `instructions` arrays of `opencode.json`. Merge an upstream change to that wiring by hand, after reading what upstream would change:

```bash
git diff agent-standards/master -- .mcp.json opencode.json .codex/config.toml .claude/settings.json
```

`opencode.json` carries the top-level `permission` block of agent-standards, taken from its commit a28f240 with the owner's approval: `external_directory`, `edit`, `bash` and `read` are all `allow`, so OpenCode runs those without asking. Kilo Code gets the same block, because it reads a project `opencode.json` as its legacy configuration file, "./kilo.json[c], legacy ./opencode.json[c], or config inside ./.kilo/" in the [Kilo Code CLI documentation](https://kilo.ai/docs/cli), checked on 2026-10-23. A read-only subagent keeps its own `edit` and `bash` deny entries, because "Agent permissions are merged with the global config, and agent rules take precedence", as the [OpenCode permissions page](https://opencode.ai/docs/permissions/), last updated 2026-10-23, says. The same page names shell commands `shell` rather than `bash`, and says: Most permissions default to `"allow"`. `doom_loop` and `external_directory` default to `"ask"`. `read` is `"allow"`, but `.env` files are denied by default. So two entries change what OpenCode does: `external_directory` stops asking before a tool touches a path outside the repository, and `read` as one plain `allow` replaces the default rule that denies `*.env` files, so an agent can read an `.env` file, `~/.local/state/agents/workspace/homelab.env` included, without asking. That last point is read from the documentation and was not measured. The preflight gate in the plugin still checks every call.

---

### Skills this project uses

The skills present in [.agents/skills/](../.agents/skills/), each linked to its canonical `SKILL.md` in agent-standards. The copy an agent loads is the one in [.agents/skills/](../.agents/skills/), and it can be older than the linked one until the next pull in Step 2.

| Skill | What this project uses it for |
|---|---|
| [agentic-engineering](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/agentic-engineering/SKILL.md) | Splitting work between agents and checking what they return |
| [ai-regression-testing](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/ai-regression-testing/SKILL.md) | Choosing tests for the defects recorded in [regression_ledger.md](regression_ledger.md), before a feature or a fix |
| [ansible](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/ansible/SKILL.md) | The playbook under [setup/ansible/](../setup/ansible/) |
| [api-design](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/api-design/SKILL.md) | Designing or reviewing an HTTP API contract |
| [arch-linux](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/arch-linux/SKILL.md) | Changing or diagnosing an Arch Linux machine outside the playbook |
| [architecture-decision-records](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/architecture-decision-records/SKILL.md) | Recording a design decision with its alternatives |
| [ascend-web-hunter](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/ascend-web-hunter/SKILL.md) | Reading a page a plain fetch cannot, through the ascend-web-hunter service in [homelab/ascend_web_hunter.md](../homelab/ascend_web_hunter.md), when `research` meets a block |
| [automation-inventory](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/automation-inventory/SKILL.md) | Listing the hooks under [.agents/hooks/](../.agents/hooks/), the workflows under [.github/workflows/](../.github/workflows/) and the MCP servers in [.mcp.json](../.mcp.json) that are really live |
| [bash](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/bash/SKILL.md) | [setup/setup.sh](../setup/setup.sh) and the checks under [e2e/](../e2e/) |
| [cachyos](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/cachyos/SKILL.md) | Changing or diagnosing a CachyOS machine outside the playbook |
| [code-formatter](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/code-formatter/SKILL.md) | Layout inside function bodies |
| [code-reviewer](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/code-reviewer/SKILL.md) | Reviewing a change before it is committed |
| [coding-standards](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/coding-standards/SKILL.md) | Writing new code |
| [database-migrations](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/database-migrations/SKILL.md) | Changing a database schema or its data |
| [deployment-patterns](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/deployment-patterns/SKILL.md) | The GitHub Actions workflows under [.github/workflows/](../.github/workflows/) |
| [design-system](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/design-system/SKILL.md) | Design tokens and visual consistency of a user interface |
| [docker-patterns](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/docker-patterns/SKILL.md) | [local-dev/local-dev-docker-compose.yaml](../local-dev/local-dev-docker-compose.yaml), [homelab/compose.yaml](../homelab/compose.yaml) and the gate image [e2e/gate/Dockerfile](../e2e/gate/Dockerfile) |
| [e2e-runbooks](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/e2e-runbooks/SKILL.md) | The capability tests indexed by [e2e/testing/README.md](../e2e/testing/README.md) |
| [frontend-design](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/frontend-design/SKILL.md) | The visual direction of a user interface |
| [git-workflow](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/git-workflow/SKILL.md) | Commits, commit messages and branches |
| [github-ops](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/github-ops/SKILL.md) | Dispatching and watching workflow runs with `gh` |
| [home-assistant](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/home-assistant/SKILL.md) | The Home Assistant OS VM in [homelab/home_assistant_vm.md](../homelab/home_assistant_vm.md) |
| [homelab-services](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/homelab-services/SKILL.md) | The services of [homelab/compose.yaml](../homelab/compose.yaml) on the Docker VM, from AdGuard Home and Nginx Proxy Manager to the USB data disk, read through the SSH key in [homelab/agent_access.md](../homelab/agent_access.md) |
| [jetbrains-ide-ops](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/jetbrains-ide-ops/SKILL.md) | The run configuration [.run/local-dev.run.xml](../.run/local-dev.run.xml) |
| [kde-plasma](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/kde-plasma/SKILL.md) | Changing or diagnosing a KDE Plasma desktop outside the playbook |
| [keycloak-patterns](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/keycloak-patterns/SKILL.md) | The `local` realm under [local-dev/auth/Keycloak/](../local-dev/auth/Keycloak/) |
| [machine-health](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/machine-health/SKILL.md) | Checking the health and configuration of a machine this repository set up, only where the owner asks for it, because [AGENTS.md](../AGENTS.md) forbids inspecting his computer otherwise |
| [macos](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/macos/SKILL.md) | Changing or diagnosing a Mac outside the playbook |
| [markdown-writer](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/markdown-writer/SKILL.md) | Every document a person reads |
| [mongodb-patterns](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/mongodb-patterns/SKILL.md) | The MongoDB service in [local-dev/local-dev-docker-compose.yaml](../local-dev/local-dev-docker-compose.yaml) |
| [postgres-patterns](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/postgres-patterns/SKILL.md) | The PostgreSQL image under [local-dev/postgresql/](../local-dev/postgresql/) |
| [powershell](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/powershell/SKILL.md) | [setup/setup.ps1](../setup/setup.ps1) and the modules in [setup/windows/](../setup/windows/) |
| [proxmox](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/proxmox/SKILL.md) | Reading the Proxmox host through the API token in [homelab/agent_access.md](../homelab/agent_access.md) |
| [python-patterns](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/python-patterns/SKILL.md) | Python code such as [setup/pinned_values/pinned_values.py](../setup/pinned_values/pinned_values.py), and its tests |
| [research](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/research/SKILL.md) | Answering a question about a tool or vendor from its documentation or source, quoted and dated, the way `agent-engineer` does it for the main thread |
| [review-duplication](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/review-duplication/SKILL.md) | Finding duplicated logic in a change |
| [security-review](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/security-review/SKILL.md) | Checking a change for leaked secrets and other security defects |
| [syncthing](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/syncthing/SKILL.md) | Reading Syncthing on the Docker VM through the API key in [homelab/agent_access.md](../homelab/agent_access.md) |
| [tdd-workflow](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/tdd-workflow/SKILL.md) | Writing the failing test before a fix, as the Goal-Driven Execution rules in [AGENTS.md](../AGENTS.md) ask |
| [windows](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/windows/SKILL.md) | Changing or diagnosing a Windows machine outside the playbook |

These skills are present only because a subagent in [.agents/agents/](../.agents/agents/) lists them under its preloaded skills. This repository has no code of their kind, so an agent working here directly does not need them:

| Skill | Preloaded by |
|---|---|
| [angular](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/angular/SKILL.md) | `code-archaeologist`, `code-reviewer`, `debugger`, `design-system-architect`, `legacy-modernizer`, `security-auditor`, `test-automator`, `ui-ux-designer` |
| [backend-patterns](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/backend-patterns/SKILL.md) | `code-archaeologist`, `code-reviewer`, `database-expert`, `debugger`, `devops-troubleshooter`, `docs-architect`, `error-detective`, `legacy-modernizer`, `observability-engineer`, `performance-engineer`, `python-pro`, `security-auditor` |
| [build-dependency-management](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/build-dependency-management/SKILL.md) | `code-archaeologist`, `code-reviewer`, `design-system-architect`, `devops-automator`, `flutter-expert`, `home-assistant-engineer`, `legacy-modernizer`, `python-pro`, `release-manager`, `security-auditor`, `test-automator` |
| [dart-flutter-patterns](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/dart-flutter-patterns/SKILL.md) | `code-archaeologist`, `code-reviewer`, `debugger`, `flutter-expert`, `legacy-modernizer`, `performance-engineer`, `test-automator`, `ui-ux-designer` |
| [e2e-testing](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/e2e-testing/SKILL.md) | `test-automator` |
| [golang-patterns](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/golang-patterns/SKILL.md) | `code-archaeologist`, `code-reviewer`, `debugger`, `legacy-modernizer`, `performance-engineer`, `test-automator` |
| [hexagonal-architecture](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/hexagonal-architecture/SKILL.md) | `code-archaeologist`, `code-reviewer`, `database-expert`, `docs-architect`, `legacy-modernizer`, `python-pro` |
| [java-coding-standards](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/java-coding-standards/SKILL.md) | `code-archaeologist`, `code-reviewer`, `debugger`, `legacy-modernizer` |
| [nextjs-app-router-patterns](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/nextjs-app-router-patterns/SKILL.md) | `code-archaeologist`, `code-reviewer`, `debugger`, `design-system-architect`, `legacy-modernizer`, `performance-engineer`, `security-auditor`, `ui-ux-designer` |
| [observability-and-logging](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/observability-and-logging/SKILL.md) | `code-archaeologist`, `code-reviewer`, `debugger`, `devops-automator`, `devops-troubleshooter`, `docs-architect`, `error-detective`, `home-assistant-engineer`, `legacy-modernizer`, `observability-engineer`, `performance-engineer`, `python-pro`, `security-auditor` |
| [performance-optimization](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/performance-optimization/SKILL.md) | `code-archaeologist`, `code-reviewer`, `database-expert`, `debugger`, `devops-troubleshooter`, `docs-architect`, `error-detective`, `observability-engineer`, `performance-engineer`, `python-pro` |
| [react-patterns](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/react-patterns/SKILL.md) | `code-archaeologist`, `code-reviewer`, `debugger`, `design-system-architect`, `docs-architect`, `legacy-modernizer`, `performance-engineer`, `security-auditor`, `test-automator`, `ui-ux-designer` |
| [soap-webservices](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/soap-webservices/SKILL.md) | `security-auditor` |
| [springboot-patterns](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/springboot-patterns/SKILL.md) | `code-archaeologist`, `code-reviewer`, `database-expert`, `debugger`, `legacy-modernizer`, `performance-engineer`, `security-auditor`, `test-automator` |
| [web-accessibility](https://github.com/Lukk17/agent-standards/blob/master/.agents/skills/web-accessibility/SKILL.md) | `design-system-architect`, `ui-ux-designer` |

The four OpenSpec skills come from `openspec init`, not from agent-standards, so the link goes to the copy in this repository:

1. [openspec-propose](../.agents/skills/openspec-propose/SKILL.md)
2. [openspec-apply-change](../.agents/skills/openspec-apply-change/SKILL.md)
3. [openspec-explore](../.agents/skills/openspec-explore/SKILL.md)
4. [openspec-archive-change](../.agents/skills/openspec-archive-change/SKILL.md)

---

### Subagents

Subagents are specialised agents the main session delegates to. The canonical definitions are `.agents/agents/<name>.md`, one markdown file each. `.opencode/agents` and `.kilo/agents` are symlinks to that folder, so OpenCode and Kilo Code read the canonical files themselves. `.claude/agents/<name>.md`, `.codex/agents/<name>.toml` and `.github/agents/<name>.agent.md` are generated copies in each tool's own format, the Codex ones carrying the instructions in a `developer_instructions` block.

These files are generated artifacts. Do not hand-edit them, because your changes will be overwritten on the next pull. To
modify a subagent permanently, change its canonical source in the agent-standards repo (`subagents/<name>.md`), run
`python tools/gen-subagents.py` there, and re-import via Step 2.

The subagents cover code review, architecture, debugging, Python, DevOps, observability, performance,
security, design, docs, Home Assistant, end-to-end test running, legal, the agent tooling and research,
databases, Flutter for the desktop front end planned in `openspec/changes/add-flutter-desktop-frontend/`,
and releases. List them with
`ls .agents/agents/` rather than trusting a count written here, because a number in prose goes stale the
first time somebody adds one, and this sentence said 26 for a while after the set had become 18.

---

### MCP servers

This project declares six MCP servers: `context7`, `grafana`, `playwright`, `chrome-devtools`, `redis` and `n8n`. They are committed as real files, not templates, so a checkout is enough: [.mcp.json](../.mcp.json) for Claude Code, the `mcp` block of [opencode.json](../opencode.json) for OpenCode and Kilo Code, and [.codex/config.toml](../.codex/config.toml) for Codex. The upstream set has more servers, and this project leaves out the ones it does not use.

The human setup, what each server needs, the keys, the environment variables per OS and how to check the servers loaded, is in [MCP_SETUP.md](MCP_SETUP.md). The agent does not run that setup. A person configures the machine once.

---

### OpenSpec integration

OpenSpec writes its skills into `.agents/skills/`, the one skills folder every agent reads, and this project carries four of them: `openspec-propose`, `openspec-apply-change`, `openspec-explore` and `openspec-archive-change`. No per-tool command folder exists here. The rules this project adds to the OpenSpec lifecycle are in [openspec/AGENTS.md](../openspec/AGENTS.md).

#### Initialising OpenSpec

Install it globally. PowerShell or Unix shell, same command:

```bash
npm install -g @fission-ai/openspec@latest
```

Initialise with the vendor-neutral target, and only that one. PowerShell or Unix shell, same command:

```bash
openspec init --tools agents
```

`--tools agents` writes OpenSpec's skills into `.agents/skills/` and creates no per-tool folders. That one target covers every agent here, because Codex, OpenCode, Kilo Code and Copilot read `.agents/skills/` natively and Claude Code reaches the same files through its `.claude/skills` symlink. A per-tool target would split a layout built to have exactly one skills folder. Avoid `--tools kilocode` in particular: OpenSpec 1.10.0 still writes its Kilo target into the old `.kilocode` folder, which Kilo Code no longer reads since it moved to `.kilo`.

What the init creates:

```text
openspec/
  config.yaml              OpenSpec project config
  specs/                   living documentation of your system
  changes/                 active feature work
    archive/               completed changes
.agents/skills/openspec-*/SKILL.md
```

Restart your editor and terminal afterwards, so the new skills are picked up.

#### Command syntax variations

OpenSpec generates files for two agent architectures:

- Standalone Markdown commands: agents that read flat files show commands with extensions
  (e.g. `/opsx-propose.md`).
- Agent skills: agents that parse semantic `SKILL.md` metadata or have native integration use slash syntax
  (e.g. `/opsx:propose`).

Use whichever form appears in your agent's autocomplete menu.

When a command needs logs or other detailed context, write the prompt over several lines after the command.

---

### OpenSpec workflow

#### 0. Run the coding agent

```shell
claude
```

#### 1. Propose a change

```text
/opsx:propose add dark mode support
```

```text
/opsx-propose.md add dark mode support
```

The agent creates the proposal, design, and implementation tasks under `openspec/changes/`.

#### 2. Apply the code

Review the generated `tasks.md` (edit directly or have the agent revise it). Then:

```text
/opsx:apply
```

```text
/opsx-apply.md
```

The agent writes the code and checks off boxes in `tasks.md`.

#### 3. Verify and refine

If bugs occur or tests fail, pass logs back:

```text
/opsx:verify The toggle button is invisible on mobile. Fix it.
```

```text
/opsx-verify.md The toggle button is invisible on mobile. Fix it.
```

#### 4. Archive the change

```text
/opsx:archive
```

```text
/opsx-archive.md
```

The agent merges delta specs into `openspec/specs/` and moves the change folder to `openspec/changes/archive/`.
