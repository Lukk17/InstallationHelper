# AGENTS.md

Shared instructions for every AI coding agent in this repository: Claude Code, Codex CLI, OpenCode, Kilo Code and GitHub Copilot. Skills, subagents and hooks are imported from [agent-standards](https://github.com/Lukk17/agent-standards). This file holds only what applies everywhere. A folder's own `AGENTS.md` holds that folder's rules and loads when work reaches the folder. The table below says what to read before working anywhere.

### What this repository is

1. `setup/`: OS configuration and software installation. An Ansible playbook covers Ubuntu, Debian, Fedora, Arch Linux and macOS. Windows is provisioned natively by `setup/setup.ps1` and `setup/windows/` from the same toggles and mappings.
2. `local-dev/`: a Docker Compose stack of local development services.
3. `homelab/`: documentation and one Compose file for an always-on Proxmox home server.
4. `e2e/`: the test harness that proves `setup/` before it ships.

### Where to read before working

| Working in | Read first |
|---|---|
| `setup/ansible/` | [setup/ansible/AGENTS.md](setup/ansible/AGENTS.md) |
| `setup/windows/` or `setup/setup.ps1` | [setup/windows/AGENTS.md](setup/windows/AGENTS.md) |
| `setup/setup.sh`, `setup/pinned_values/` or anything else under `setup/` | [setup/README_SETUP.md](setup/README_SETUP.md), and [e2e/AGENTS.md](e2e/AGENTS.md) for which run the change owes |
| `e2e/` or `.github/workflows/` | [e2e/AGENTS.md](e2e/AGENTS.md). No workflow may start on an automatic event |
| `local-dev/` | [local-dev/AGENTS.md](local-dev/AGENTS.md) |
| `homelab/` | [homelab/AGENTS.md](homelab/AGENTS.md) |
| `openspec/` | [openspec/AGENTS.md](openspec/AGENTS.md) |
| fixing any defect | the defect classes at the top of [docs/regression_ledger.md](docs/regression_ledger.md) |
| the agent tooling: `.agents/`, `.claude/`, `.codex/`, `.opencode/`, `.kilo/`, `.github/agents/`, `.mcp.json`, `opencode.json` | [docs/AGENT_TOOLING.md](docs/AGENT_TOOLING.md) and [docs/MCP_SETUP.md](docs/MCP_SETUP.md) |
| a decision about how the whole repository is worked on | [docs/decisions/README.md](docs/decisions/README.md) |
| the KDE Plasma profile, konsave | "Konsave profile management (KDE)" in [setup/README_SETUP.md](setup/README_SETUP.md) |

### MANDATORY: never run anything on the owner's computer for testing

This repository installs and removes software, so a test that escapes onto the real machine changes the real machine. It has happened three times, and once an agent inspected the machine without being asked: entries 10.64, 10.98, 10.124 and 10.143 of [docs/regression_ledger.md](docs/regression_ledger.md).

1. Every test, check, gate, test suite, experiment and probe runs only inside a container or a throwaway virtual machine, even when it only reads files. Here that is the gate container `bash e2e/run.sh` builds from [e2e/gate/Dockerfile](e2e/gate/Dockerfile), and every check refuses to start anywhere else. Tier 3 never runs on the owner's computer, not even inside the gate container, because its privileged scenario containers changed his kernel four times, entries 10.126 to 10.129. It runs only on a GitHub-hosted runner, dispatched through `.github/workflows/e2e-manual.yaml` or `.github/workflows/e2e-matrix.yml` (owner decision 79). No other virtual machine counts, a local one, WSL 2, Docker Desktop and a self-hosted runner alike. `e2e/tier1/throwaway_machine_only.sh` fails the gate if the refusal is weakened.
2. Never run a downloaded program, an installer, a vendor binary, an IDE or an app on the owner's computer, not even to read its help. Read its documentation or its files instead.
3. Never run a package manager install, remove or upgrade, a playbook or a role against the owner's computer unless the owner asks for that exact change in the conversation.
4. Never test, check, probe or inspect the owner's computer, not even with a read-only command such as grep, cat, ls or a package query, and not to find out whether a defect affects it. If that matters, ask the owner and give him the exact command to run himself. The only things an agent does on the host are git and file edits inside this repository, Docker commands that start and watch the test containers, and reading the test logs under `e2e/runs`.
5. A test that runs a play or a command with fakes belongs in a container, and its fakes must be proven to resolve before anything runs, defect class 16. That proof does not replace the container.
6. If something on the owner's computer was changed by mistake, stop, tell the owner at once exactly what changed, and restore it from a backup before anything else.
7. A container on the owner's computer runs as the real root of his kernel, because Docker there does not remap users. Never start one with `--privileged`, any `--security-opt`, `--cap-add`, `--pid host`, `--network host` or `--userns host`, never run `unshare`, `nsenter` or another namespace tool inside one, and never write to `/proc`, `/proc/sys` or `/sys` inside one. `e2e/tier1/host_container_privileges.sh` checks the scripts under `e2e/`, not the commands you type.

### MANDATORY: run the e2e gate before calling playbook work done

Every regression in [docs/regression_ledger.md](docs/regression_ledger.md) reached a real machine because nothing ran the playbook before it shipped.

1. After any change under `setup/`, run the tier 1 gate from the repository root. It runs inside its own container, never on your machine:

   ```bash
   bash e2e/run.sh
   ```

2. A non-zero exit means the work is not done. Do not report success, do not commit, and do not explain the failure away. Fix it.
3. Many changes owe more than tier 1: tier 2, or a tier 3 scenario dispatched to a GitHub-hosted runner. [e2e/AGENTS.md](e2e/AGENTS.md) says which. Before telling the owner something is verified, read [e2e/manual_test_matrix.md](e2e/manual_test_matrix.md), which lists what no run can prove.

### MANDATORY: record every defect you introduce or find

[docs/regression_ledger.md](docs/regression_ledger.md) is the record of every defect this project has suffered. Adding to it is part of finishing the work.

1. A defect you find gets an entry before you call the fix done, not after the sweep and not in the commit message alone.
2. A defect you introduce yourself gets an entry too, and says so. Those are the entries a future agent is most likely to repeat.
3. Every entry states the cause in one sentence, the effect with the actual error text or numbers, how it was proven rather than reasoned about, and where the fix lives.
4. If a hypothesis along the way was wrong, keep it and say it was wrong.
5. If the defect could have been caught mechanically, add the check as well, prove it fails against the defect before trusting it, and name the check in the entry.

Do not copy ledger entries into any `AGENTS.md`. The defect classes, the shapes of the mistakes already made here, are at the top of the ledger. Read them before fixing a defect.

### Skills

1. `.agents/skills/` is the one skills folder, and `.claude/skills` is a symlink to it. Do not add a second copy anywhere.
2. Invoke the relevant skills before the work, for example `/code-reviewer` before a review, `/security-review` before a security audit, `/coding-standards` before new code, `/python-patterns` or `/ai-regression-testing` before a feature or a fix, and `/arch-linux`, `/cachyos`, `/kde-plasma`, `/windows` or `/macos` before changing or diagnosing a machine of that kind outside the playbook.
3. Slash commands show as `/name` or `/name.md`. Use whichever your agent shows.
4. The full list, each linked to its `SKILL.md`, is "Skills this project uses" in [docs/AGENT_TOOLING.md](docs/AGENT_TOOLING.md#skills-this-project-uses).

### Subagents

1. The canonical definitions are `.agents/agents/*.md`. `.opencode/agents` and `.kilo/agents` are symlinks to that folder, and `.claude/agents/`, `.github/agents/` and `.codex/agents/` carry generated copies in each tool's own format. Count them with `ls .agents/agents/*.md` rather than trusting a number in prose.
2. They are generated from agent-standards. Never edit them here, because the next pull overwrites the change. Change `subagents/<name>.md` in agent-standards, regenerate there and import again. A read-only subagent carries `edit` and `bash` deny entries in its OpenCode and Kilo Code copy, and `permissionMode: plan` in its Claude Code copy.
3. The most used: `code-reviewer` for a diff review before merge, `test-automator` for missing tests and failures without weaker assertions, `security-auditor` for threat modelling, `e2e-runner` for one end-to-end capability test, `error-detective` for patterns across logs, `debugger` for one failing test or error, `devops-troubleshooter` for a live incident.

### Hooks

The Python scripts in `.agents/hooks/` run on every agent surface and are not advisory. Read them before wondering why a tool call was refused. Like the subagents, they are generated from agent-standards, so change them there.

1. `preflight_gate.py` runs before every tool call. The main thread may not write any file, through an edit tool or the shell, and delegates the change to a subagent that owns the area. A subagent whose definition declares no skills may not act. The main thread may not run a web fetch or web search, and spawns a subagent to research instead. The main thread may not run a script or a module, `bash e2e/run.sh` included, unless it matches the gate's built-in list of read-only checks or a line of `main-thread-allowlist.txt` at the root, which this project does not have. So e2e runs are delegated to a subagent.
2. Every rule fires only on a caller positively identified as the main thread, so GitHub Copilot is ungated. Any parse error or unexpected payload allows the call, because a broken gate must never break a session. The one exception is a write to a path it cannot place, which counts as inside the repository and is denied.
3. `no_ai_markers_check.py` blocks a reply whose prose holds an em dash, an en dash, a semicolon or a bold marker. Code is exempt, prose is not.
4. `task_list_sync.py` mirrors the task list into `tasks.md` at the root, which is git-ignored and the one file the main thread may write. Beside it run the markdown lint, status block, question numbering and task watchdog hooks.
5. OpenCode 1.x and 2.x and Kilo Code reach every hook through one plugin, `.agents/plugin/index.js`, whose default export is `{ id, server, setup }`: OpenCode 1.x and Kilo Code call `server`, and 2.x calls `setup`. OpenCode 2.x ignores the `instructions` key, so the plugin hands it the reply rules too. Which file each agent reads is in [docs/AGENT_TOOLING.md](docs/AGENT_TOOLING.md).

### MCP servers

1. [.mcp.json](.mcp.json), [opencode.json](opencode.json) and [.codex/config.toml](.codex/config.toml) declare six servers: `context7`, `grafana`, `playwright`, `chrome-devtools`, `redis` and `n8n`. Setup is in [docs/MCP_SETUP.md](docs/MCP_SETUP.md).
2. Use `context7` whenever the user asks about a library or its API, even a well-known one, instead of your training data. Not for refactoring, business-logic debugging or general programming concepts.
3. A server whose variable is unset still starts, then cannot connect or authenticate. If one answers nothing, check its variable in [docs/MCP_SETUP.md](docs/MCP_SETUP.md) before assuming the service is down.

### Instruction files

1. This file stays under 200 lines and 32 KiB, every other `AGENTS.md` under 60 lines, and no `CLAUDE.md`, `.claude/CLAUDE.md` or `CLAUDE.local.md` exists anywhere, because any of them switches off Claude Code's native loading of these files. `e2e/tier1/agents_md_size.sh` fails the gate otherwise. The reasons are in [docs/decisions/0001_split_agents_md.md](docs/decisions/0001_split_agents_md.md).
2. A folder's `AGENTS.md` holds links written as "before X, read Y" and only the rules no check catches. Explanations, history, measured numbers and file trees go into the docs it links.
3. Claude Code needs 2.1.277 or later to read `AGENTS.md` natively. Start every agent from the repository root.

### Working principles

1. Think before coding. State your assumptions. When a request is ambiguous, name the readings and ask rather than picking one silently. If a simpler approach exists, propose it before writing code.
2. Simplicity first. Write the least code that solves the problem: no features, abstractions, options or error handling that nobody asked for or that cannot be needed.
3. Surgical changes. Touch only what the task requires, match the existing style, and do not improve or refactor neighbouring code. Mention unrelated dead code rather than deleting it. Remove only what your own change made unused.
4. Goal-driven execution. Turn a task into a check that proves it, such as a failing test that reproduces a bug, then make it pass. For work in several steps, state each step with the check that verifies it, and never claim the work is done without running the checks.

### Documentation conventions

1. Markdown filenames are lowercase with underscores, such as `setup/software.md` and `homelab/adguard_dns.md`. Two kinds keep their capitals and are never renamed to match: any name starting with `README`, and the agent tooling documents that follow agent-standards naming, `AGENTS.md`, `SKILL.md`, the files in `.agents/agents/` and `.agents/hooks/`, `docs/AGENT_TOOLING.md`, `docs/MCP_SETUP.md` and `docs/AI_TOOLS_ADDING.md`.
2. Renaming a document means updating every link to it in the same change.
3. Every documentation folder has one hub page that links to all its pages: [README.md](README.md) at the root, [setup/README_SETUP.md](setup/README_SETUP.md), [local-dev/README_LOCAL_DEV.md](local-dev/README_LOCAL_DEV.md), [homelab/README_HOMELAB.md](homelab/README_HOMELAB.md), [e2e/README_E2E.md](e2e/README_E2E.md) and [docs/decisions/README.md](docs/decisions/README.md). A new page goes into its hub's documentation map.
