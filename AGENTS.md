# AGENTS.md

This file provides shared instructions to all AI coding agents working in this repository (Claude Code, Kilo Code, OpenCode, Codex CLI, GitHub Copilot). Standards and skills are imported from [agent-standards](https://github.com/Lukk17/agent-standards).

## Skills

This project includes agent skills in `.agents/skills/`. Invoke relevant skills before starting implementation work. Examples:

- `/code-reviewer` before reviewing code
- `/security-review` before auditing for vulnerabilities
- `/coding-standards` before writing new code
- `/python-testing` or `/ai-regression-testing` before adding features or fixing bugs

Slash commands may appear as `/name` or `/name.md` in your agent's autocomplete, use whichever your agent shows.

`.agents/skills/` is the canonical location and `.claude/skills` is a symlink into it, so a skill added once is visible to every agent. Do not add a second copy anywhere.

## Subagents

This project ships 18 specialised subagents, narrow-scope agents the main session delegates to. The canonical definitions live in `.agents/agents/`, one markdown file each, and every agent surface reaches the same set from there. `.opencode/agents` and `.kilo/agents` are symlinks into it. `.claude/agents/`, `.github/agents/` and `.codex/agents/` carry generated copies in each tool's own format, the Codex ones as `*.toml` with a `developer_instructions` block instead of markdown.

Count them rather than trusting this number if it matters to you: `ls .agents/agents/*.md`. A number written in prose goes stale the first time somebody adds an agent, and this one said 26 for a while after the set had become 18.

These files are generated artifacts pulled from agent-standards. Do **not** hand-edit them — changes will be overwritten on the next pull. To modify a subagent permanently, edit its canonical source in the agent-standards repo (`subagents/<name>.md`), regenerate there, and re-import.

A few of the most-used:

- `code-reviewer` — security-aware diff review before merge
- `test-automator` — write missing tests and fix failures without weakening assertions
- `security-auditor` — threat modelling, secure-coding review, compliance gap analysis
- `e2e-runner` — runs one end-to-end capability test against a live stack and reports its verdict
- `error-detective` — pattern hunting across logs and traces rather than a single bug
- `debugger` — root-cause analysis for a single failing test or runtime error
- `devops-troubleshooter` — live incident response with postmortem

Full catalogue: list `.agents/agents/*.md` in this project, which is the canonical set, or see the agent-standards README's "Subagents catalog" section.

## MCP servers

This project declares six MCP servers in [`.mcp.json`](.mcp.json). Human-side setup lives in [`docs/MCP_SETUP.md`](docs/MCP_SETUP.md).

| Server | What it is for |
|---|---|
| `context7` | Up-to-date library, framework, SDK and API documentation |
| `grafana` | Dashboards, metrics and alert rules on a Grafana instance |
| `playwright` | Driving a browser for end-to-end web testing |
| `chrome-devtools` | Reading console output, network requests and the page from Chrome |
| `redis` | Querying a Redis instance |
| `n8n` | Reading and building n8n automation workflows |

Use `context7` whenever the user asks about a library or its API, even a well-known one, instead of relying on your training data. Do not use it for refactoring, business-logic debugging, or general programming concepts.

Every server except `playwright` and `chrome-devtools` reads its endpoint or credential from an environment variable with an empty default, so an unset variable gives you a server that starts and then cannot authenticate rather than an error at startup. If a server answers nothing, check the variable before assuming the service is down: `CONTEXT7_API_KEY`, `GRAFANA_URL` and `GRAFANA_SERVICE_ACCOUNT_TOKEN`, `REDIS_URL`, `N8N_API_URL` and `N8N_API_KEY`.

## Working With Agents

All supported agents read this `AGENTS.md` from the project root and auto-discover skills from `.agents/skills/`. Start your agent from the project root:

- **Claude Code** — run `claude`. Reads `.claude/CLAUDE.md`, which imports this file, plus `.claude/settings.json` for hooks, `.claude/agents/` and the `.claude/skills` symlink.
- **Kilo Code** — reads `AGENTS.md` automatically, plus `.kilo/agents`, which is a symlink to the canonical set. Hooks arrive through the OpenCode plugin below.
- **OpenCode** — reads `AGENTS.md` automatically, plus `opencode.json` at the project root, which loads `.agents/plugin/hooks.js`.
- **Codex CLI** — run `codex`. Reads `AGENTS.md` automatically, plus `.codex/config.toml`, which carries both the MCP servers and the hooks, and `.codex/agents/`. Global settings stay in `~/.codex/config.toml`.
- **GitHub Copilot** — reads `AGENTS.md`, `.github/agents/` and `.github/hooks/preflight.json`.

## Hooks

Two Python scripts under `.agents/hooks/` are wired into every surface above. They are not advisory. Read them before wondering why a tool call was refused.

`preflight_gate.py` runs before a tool call and enforces three rules. The main thread may not write any file, and must delegate the change to a subagent that owns the area. This covers the edit tools and the shell alike, because the gate lexes the command, so a redirection, `sed` or `patch` is not a way around it. A subagent whose own definition declares no skills may not act. And the main thread may not run a web fetch or web search directly, it spawns a subagent to research and report back. Any parse error or unexpected payload allows the call, because a broken gate must never break a session.

`no_ai_markers_check.py` runs when a reply is about to be delivered and blocks prose containing an em dash, an en dash, a semicolon or a bold marker, after stripping fenced code, inline code and link targets. Code is exempt. Prose is not.

Both are generated artifacts from agent-standards, like the subagents. Change them there, not here.

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

## MANDATORY: record every defect you introduce or find

[`docs/regression_ledger.md`](docs/regression_ledger.md) is the record of every defect this project
has suffered. Adding to it is not optional and not a nicety, it is part of finishing the work:

1. A defect you find gets an entry before you call the fix done. Not after the sweep, not in the
   commit message alone, in the ledger.
2. A defect you introduce yourself gets an entry too, and says so. Those are the most valuable
   entries on the page, because they are the ones a future agent is most likely to repeat.
3. Every entry states four things: the cause in one sentence, the effect with the actual error text
   or the actual numbers, how it was proven rather than reasoned about, and where the fix lives.
4. If a hypothesis along the way was wrong, keep it and say it was wrong. Two entries on that page
   are worth more for the wrong turn they record than for the fix.
5. If the defect could have been caught mechanically, add the check as well, prove it fails against
   the defect before trusting it, and name the check in the entry.

Do not copy ledger entries into this file. One record, one place. What lives here is the list below,
which is the shape of the mistakes rather than the instances.

### Defect classes already introduced in this repository

Every one of these was written by an agent working on this project, shipped, and then found by a
pipeline or by the owner. They are listed by shape because the shape is what recurs. Instances,
dates, error text and fixes are in the ledger.

1. Deleting a block at the end of a function took the next statement with it. Removing one product's
   install block took the whole function's `return` with it, so the function handed its caller
   nothing and the wizard died in the reporting code two files away from the deletion. When you
   delete a trailing block, read what is underneath it.
2. The same rule implemented in two places, which then disagreed. Three machine conditions decided
   whether a package can install, and the winget path, the Chocolatey path and the verification each
   decided separately. One phase installed a package the other phase reported as not applicable, in
   the same run, and the run passed. If two phases must agree, they call one function.
3. A vendor's support matrix treated as the installer's behaviour. Razer lists Windows 10 and 11 and
   no Server edition, so the package was marked client-only. It installs on Server and exits 0. A
   support matrix says what the vendor will support, not what the installer refuses to do. Measure
   the installer.
4. `return @($list)` does not survive assignment in PowerShell. A one-element array unrolls to a
   bare string, and `.Count` on a string is a terminating error under `Set-StrictMode -Version
   Latest`. Wrap at the call site, `@(Get-Thing)`, never trust the function's own `@( )`.
5. Two parsers reading the same file with different escaping rules. `vars/Windows.yaml` is read by
   Ansible, which unescapes a double-quoted YAML scalar, and by a PowerShell regex that takes the raw
   text. A path with backslashes arrived as one character in one and two in the other, and every
   `Test-Path` against it answered false. Use a separator that needs no escape.
6. Splatting an array instead of a hashtable in PowerShell. An array splat supplies positional
   arguments with the dashes still attached, so `-NonInteractive` bound to the first positional
   parameter and the error named a parameter nobody had passed. Guarded now by
   `e2e/tier1/powershell_splat.sh`.
7. A second entry point drifting from the primary one. The single-platform workflow could not bind
   its arguments, allowed 60 minutes for work the sweep gives 150, and never freed disk space. All
   three were things the sweep already did correctly, and all three were found within two hours of
   the first time anybody dispatched that workflow. Guarded now by `e2e/tier1/workflow_timeouts.sh`
   and `e2e/tier1/workflow_parity.sh`.
8. A `changed_when` reading stdout for a message the tool writes to stderr. This one has five
   instances. pacman prints ` there is nothing to do` on stdout and `warning: <pkg> is up to date --
   skipping` on stderr, and the condition read the wrong stream, so the task reported a change on
   every rerun. Run the tool twice and look at which stream each line comes out on.
9. Batching independent downloads. A batch is one call with one exit code, so one failure loses the
   whole set and nothing can name the package that broke. It cost twenty-two flatpak applications on
   twenty of forty-eight cells, roughly thirty Homebrew casks twice in two days, and every package in
   a Chocolatey batch. Nothing in this project batches now, and
   `e2e/tier1/batched_managers.sh` fails on any manager that tries.
10. A watcher that could go quiet. A background monitor wrote its state with a bash redirect to
    `/tmp` and read it back from Python, where that path resolves elsewhere, so it caught the
    exception and exited silently. An hour of ten-minute reports never happened and it looked
    identical to a run with nothing to report. Every branch of a watcher must emit, including its own
    failure.
11. Measuring something adjacent to the failure instead of the exact thing it named. A log said one
    URL had timed out. A different Flathub path was fetched instead, answered 503, and that became
    "Flathub is down". The URL the error named answered 200 with 1.6 MB in 0.29 seconds. Take the
    identifier out of the failure and test that.
12. Asserting a benefit without measuring it. Batching apt, dnf and pacman was defended on the
    grounds that the solver and the trigger phase run once instead of N times. Measured, it was worth
    at most about two per cent of a container scenario, inside run-to-run noise of the same size, and
    on one of the two sets looping was faster.
13. Reading a queue state as progress when it was a block. A dispatched sweep sat at `pending` with
    no jobs, which is indistinguishable from a slow start, because `e2e-matrix.yml` has a concurrency
    group and another run of the same workflow was still open. Before dispatching a sweep, check
    whether one is already open and decide deliberately whether it still has anything to prove.
14. Measuring the right thing at the wrong time. Both Windows download caches were listed on a
    developer machine and held 728 and 1,326 directories with no installer in either, which read as
    "nothing to free here". Chocolatey's own log said otherwise: it downloads to
    `%TEMP%\chocolatey\<package>\<version>`, installs from there and leaves the file, and the
    directory was empty only because Windows had cleaned its temporary directory over the following
    nineteen days, which a one hour job never gets. A listing taken days after the run says nothing
    about what the disk held during it.
15. Trusting a subcommand to do what its name suggests. `choco cache remove` sounds like the command
    that empties the download cache and is not: asked directly, `choco cache --help` on 2.7.3 says it
    works on the User HTTP Cache and, when elevated, the System HTTP Cache, which is the NuGet
    metadata. Ask the tool what its own command does before building on the name.

---

## MANDATORY: run the e2e gate before calling playbook work done

This is not optional and it is not advisory. Every regression recorded in [`docs/regression_ledger.md`](docs/regression_ledger.md) reached a real machine because nothing ran the playbook before it shipped. Reading a diff cannot tell you that a group name does not exist on Arch, or that a toggle installs nothing, and both of those have happened here.

**After any change under `setup/`, run the tier 1 gate.** It now takes about six and a half minutes rather than the seconds it used to, measured at 6 minutes 28 seconds from Git Bash on Windows on 2026-08-29, because six of its checks start `setup.sh` as a real process and process creation under Git Bash is what nearly all of that time goes on. It has not been measured on Linux, where those same processes are much cheaper.

```bash
./e2e/run.sh
```

On Windows, prefer Git Bash, because that is the only shell here that can prove every check. Run it from the repository root:

```bash
bash e2e/run.sh
```

WSL runs the gate too, but as measured on 2026-08-20 it does not come back clean, and neither reason is about the tree under test. One check fails because `setup/manifests/generate.py` passes `newline=` to `Path.read_text`, which needs Python 3.13 and WSL has 3.12.3, and three more skip because the Store `pwsh` alias did not answer through interop that time. Both were reproduced against a clean worktree at `HEAD`. The interop route does work when Windows lets it: the Store build's `pwsh.exe` and `winget.exe` under `WindowsApps` have been observed running from inside WSL and answering real queries, which is why those checks report SKIP rather than a pass when nothing runs. This paragraph has now been rewritten twice in both directions, which is itself the lesson: a Store app-execution alias is not a normal executable, whether WSL can run one is a property of the Windows build rather than of this repository, so measure it on the day rather than trusting what is written here. Git Bash remains the better default, because it needs no interop hop and delegates the two Ansible checks to WSL by itself. The gate prints its own tally, and [`e2e/README_E2E.md`](e2e/README_E2E.md) describes the shells without restating a number that goes stale every time a check is added.

```powershell
wsl -d Ubuntu bash -c "cd /mnt/d/Development/projekty-IT/InstallationHelper && ./e2e/run.sh"
```

**The container tiers run from Git Bash as well.** This section used to say WSL was what they needed, which was wrong in the direction that costs coverage. What refused Git Bash was the harness rather than Docker: the guard asked `uname -s`, turned away anything that was not Linux, and pointed the reader at WSL whether or not WSL could reach a daemon. It now asks whether a daemon answers and whether the shell can spell a host path for it, and from Git Bash both answers are yes whenever Docker Desktop is running. Run tiers 2 and 3 exactly as written, from the repository root, with no prefix and nothing exported:

```bash
bash e2e/run.sh --tier 2
```

```bash
bash e2e/run.sh --tier 3 --scenario defaults --os debian
```

The MSYS path rewriting that makes `docker` unusable by hand from Git Bash is handled inside `e2e/lib/common.sh` rather than left to the caller, which is why those two commands are identical to the ones a Linux shell runs. If you ever call `docker` yourself from Git Bash, remember what the harness is doing for you: prefix `MSYS_NO_PATHCONV=1` so container paths such as `-v /sys/fs/cgroup:...` and `-w /work/setup/ansible` survive, and pass every host path through `cygpath -w`.

Whether WSL can also reach the daemon depends on Docker Desktop having integration enabled for that distribution, so measure it rather than assume it either way. Measured on 2026-08-20, the Ubuntu distribution has `/var/run/docker.sock` and `docker info` reports server 29.3.1, so the container tiers run from there too. That integration has been off before, and while it is off there is no socket inside WSL at all, which the guard now reports by name instead of blaming the operating system.

A non-zero exit means the work is not done. Do not report success, do not commit, and do not explain the failure away. Fix it.

**Additionally, when your change touches any of the following, run the container tier as well.** The cheapest scenario there is forced-failure, at a 90 minute ceiling and 46 minutes measured on debian, because it is the only one that never installs the software set. The cheapest that installs anything is defaults, at 180. There is still no cheap container scenario: the smoke scenario used to declare 45 minutes, but every toggle it enabled was already true in defaults, so it proved nothing defaults does not. Tier 1 is still the cheap one at about six and a half minutes, measured at 6 minutes 28 seconds from Git Bash on Windows on 2026-08-29.

| If you changed | Run |
|---|---|
| a toggle in `group_vars/*.yaml` | tier 1 is enough |
| a package mapping in `setup/ansible/vars/*.yaml` | `./e2e/run.sh --tier 2` |
| **any package name written directly into a role task** | `./e2e/run.sh --tier 2`, which resolves them per distribution. Five shipped defects came from here, including two that were themselves earlier fixes that had rotted |
| a pinned value in `setup/pinned_values/pinned_values.toml` | `./e2e/run.sh --tier 2`, which asks every download location whether it still exists |
| the pinned values reader or any of its adapters | tier 1, which runs the Windows Pester suite, then `--tier 3 --scenario defaults` |
| anything in `roles/` that touches groups, systemd units, or per-distro behaviour | `./e2e/run.sh --tier 3 --scenario defaults`, on all four Linux distributions and not just one |
| the desktop environment roles | `./e2e/run.sh --tier 3 --scenario kde-full` and `--scenario gnome-full` |
| `profiles/linux_live.yaml` | `./e2e/run.sh --tier 3 --scenario live-profile` |
| `setup/setup.sh` | tier 1, then any one tier 3 scenario end to end |
| the Windows installer (`setup/setup.ps1` or `setup/windows/`) | tier 1, which runs the Windows Pester suite, then a real install in Windows Sandbox via `pwsh e2e/windows-sandbox/Invoke-WindowsSandbox.ps1`, see `e2e/manual_test_matrix.md`. There is no Windows container tier: it could not install one winget package |
| `setup/ansible/verify_install.yaml` | tier 1, then `--tier 3 --scenario forced-failure`, which is the only scenario that proves the play refuses over a broken machine, then any one passing scenario |
| a task's `changed_when`, a `creates` guard, or anything about whether a task reports work it did not do | `./e2e/run.sh --tier 3 --scenario idempotency`, which applies the defaults configuration twice and fails on any task that reports changed on the second pass without a reason in `e2e/tier3/idempotent_changes_allowed.txt` |
| a rescue, a `failed_when`, an `ignore_errors`, `any_role_failed`, or the callback plugin's failure rendering | `./e2e/run.sh --tier 3 --scenario forced-failure`, which breaks the run on purpose and asserts the failure reaches the exit code, the terminal summary, the error log and the verification |
| a check under `e2e/` | prove the check fails against a copy of the tree carrying the defect, then run the whole gate from Git Bash and from WSL |
| a distribution Dockerfile, or a new distribution | `./e2e/run.sh --tier 3 --scenario defaults --os <name>` |
| anything macOS-only | tier 1 and tier 2, then the `macos` target of the dispatch workflow, which is the only thing that executes on macOS at all |

That table is the short version. The complete map, including what each run still cannot prove, is the "What to run when you change something" section of [`e2e/README_E2E.md`](e2e/README_E2E.md).

What none of it can prove, on any platform, is [`e2e/manual_test_matrix.md`](e2e/manual_test_matrix.md). Read it before telling the owner that something is verified: bootloaders, hibernation, Snapper, Waydroid, VirtualBox and VMware are suppressed in every container, client-edition and hardware-dependent packages are skipped on the hosted Windows runner, and macOS has no container tier at all. The page says for each one whether a virtual machine is enough or real hardware is required, and gives a command that answers the question.

**For a run that must survive you closing the terminal**, drive it from the queue container rather than a shell. A queue tied to a shell is not a queue: one previously started two scenarios of three, exited, and nobody noticed for four hours.

```bash
docker run -d --name e2e-queue -v /var/run/docker.sock:/var/run/docker.sock -v "$PWD:/repo" -w /repo installationhelper-e2e-queue:latest -c './e2e/run.sh --tier 3 --scenario all --jobs 3 > /repo/e2e/runs/queue.log 2>&1; rc=$?; echo "QUEUE_EXIT=$rc" >> /repo/e2e/runs/queue.log; exit $rc'
```

That form is for a Linux shell. From Git Bash the same run needs the two path rules spelled out, because this command is yours rather than the harness's: the rewriting has to be off so the socket mount survives, and the repository mount has to be a Windows path. Verified from Git Bash on 2026-08-20, the container reaches the daemon and finds `e2e/run.sh` under `/repo`.

```bash
MSYS_NO_PATHCONV=1 docker run -d --name e2e-queue -v /var/run/docker.sock:/var/run/docker.sock -v "$(cygpath -w "$PWD"):/repo" -w /repo installationhelper-e2e-queue:latest -c './e2e/run.sh --tier 3 --scenario all --jobs 3 > /repo/e2e/runs/queue.log 2>&1; rc=$?; echo "QUEUE_EXIT=$rc" >> /repo/e2e/runs/queue.log; exit $rc'
```

The `rc=$?` and `exit $rc` are not decoration. Append anything after the run without capturing the status first, an `echo` for instance, and the container exits with the echo's status instead: a sweep where three of the seven scenarios that existed then failed reported `Exited (0)` for exactly that reason, which makes the queue impossible to alarm on or chain behind. Verified both ways, this form writes `QUEUE_EXIT=2` into the log and exits 2.

Roughly 5 GB of memory per concurrent scenario, measured. On a 16 GB WSL ceiling that means three at a time, not six. Three against 12 GB available does not corrupt anything, but it does make `wsl.exe` intermittently answer `Wsl/Service/0x8007274c` and it cost one scenario a failed `docker cp` of `setup/`. Use `--jobs 2` when you want clean timings rather than throughput.

Rules that come out of the ledger and that the gate cannot check for you:

1. A per-distribution fact belongs in `vars/<OS>.yaml` and is read through `os_dict`. Never hardcode a group name, a package name, a path or a service name into a task. The OpenRazer group was hardcoded to Debian's answer and failed every Arch run.
2. Verify a package or group actually exists on every OS family you claim to support, not just the one you tested. Debian's answer does not generalise.
3. Never use `failed_when` or a `rescue` to turn a real failure into a pass. A two-condition `failed_when` is combined with AND, which is how one bad package name silently dropped every Arch package while the run stayed green.
4. A toggle is not implemented until something consumes it. A comment saying another role handles it is not an implementation, and `install_gradle` sat unimplemented behind exactly that comment.
5. An install that cannot function is a bug even when the playbook exits zero. OpenRazer installed cleanly on Arch with no kernel headers, so the driver never built.
6. If you add a toggle that intentionally does nothing on some OS, add it to [`e2e/tier1/documented_no_ops.txt`](e2e/tier1/documented_no_ops.txt) with the reason, or the gate will fail. That is deliberate.

Full harness documentation, including what a container cannot test, is in [`e2e/README_E2E.md`](e2e/README_E2E.md).

## Watch anything that runs long, every ten minutes

A container scenario takes 90 to 300 minutes by declared ceiling and a CI sweep takes hours. Neither tells you it is
stuck, and a run that has hung looks exactly like a run that is working until you go and ask.

So ask, on a timer, roughly every ten minutes, whichever way the work is running:

```bash
docker ps --filter name=e2e --format '{{.Names}}\t{{.Status}}'
```

```bash
tail -5 e2e/runs/queue.log
```

```powershell
gh run list --workflow e2e-matrix.yml --limit 5
```

Watching only for completion is the mistake. A queue that died leaves no notification, and one that
did exactly that started two scenarios of three, exited, and nobody noticed for four hours. Check
progress rather than presence: the same status ten minutes later is a stall, and the container being
alive proves nothing about whether the playbook inside it is still doing anything.

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

A cross-platform Ansible-based system setup and local development toolkit. It has three main parts:

1. **`setup/`** — OS configuration and software installation. An Ansible playbook covers Ubuntu/Debian, Fedora, Arch Linux and macOS. Windows is not covered by Ansible at all: `setup/setup.ps1` and the modules in `setup/windows/` provision it natively from the same toggles and mappings.
2. **`local-dev/`** — Docker Compose stack for local development services (MySQL, PostgreSQL, MongoDB, Keycloak).
3. **`homelab/`** — Docker Compose stack and documentation for an always-on home server: a Proxmox host running a Home Assistant OS VM and an Ubuntu Docker VM (AdGuard Home, Nginx Proxy Manager, Homepage, Uptime Kuma, Syncthing, Perlite). Docs only plus one compose file, no Ansible. Write instructions against `<angle-bracket>` placeholders so the docs stay reusable, then give the LAN addresses of this specific lab as a concrete example block underneath. Never commit credentials, API tokens, device keys, or MAC addresses.

## Documentation Conventions

Markdown filenames are lowercase with underscores: `setup/software.md`, `homelab/adguard_dns.md`, `docs/linux/virt_manager_setup.md`. Two exceptions keep their capitals:

1. Any filename starting with `README` — `README.md`, `setup/README_SETUP.md`, `homelab/README_HOMELAB.md`, `local-dev/README_LOCAL_DEV.md`.
2. The agent tooling docs, which follow upstream agent-standards naming — `AGENTS.md`, `.claude/CLAUDE.md`, `.agents/skills/*/SKILL.md`, `.agents/agents/*.md`, `.agents/hooks/*.py`, `docs/AGENT_TOOLING.md`, `docs/MCP_SETUP.md`, `docs/AI_TOOLS_ADDING.md`.

Do not rename anything in the first two categories to match the lowercase rule. Renaming a doc means updating every markdown link that points at it in the same change.

Every doc directory has one hub page that links to all of its siblings: `README.md` at the repo root, `homelab/README_HOMELAB.md`, `setup/README_SETUP.md`, `local-dev/README_LOCAL_DEV.md`. Adding a page to one of those directories means adding it to that hub's docs map.

## Ansible Architecture

The playbook (`site.yaml`) follows this execution order:

1. **Pre-tasks**: Loads OS-specific group vars (`group_vars/{linux,macos,windows}.yaml`) and the OS translation dictionary (`vars/{Debian,RedHat,Archlinux,Darwin,Windows}.yaml`) as `os_dict`.
2. **OS core roles**: `macos_core`, `arch_core`, `fedora_core`, `debian_core`, `system_core` — bootstrap the specific OS. There is no Windows role: Windows is provisioned natively by `setup/setup.ps1` and the modules in `setup/windows/`, and the playbook never runs there.
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
| `setup/pinned_values/pinned_values.toml` | Pinned versions, download locations and vendor identifiers, read through `setup/pinned_values/pinned_values.py` |
| `vars/{OS}.yaml` | Translation dictionaries mapping generic app name → `{manager, package}` |
| `profiles/linux_live.yaml` | Override profile for USB/live installs |
| `software.md` | Complete per-OS software list with installation methods |

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

**Affected versions:** every ansible-core release from 2.19.0 onwards, on all three live branches. Re-checked 2026-08-20: [PR #86739](https://github.com/ansible/ansible/pull/86739) is still open against `devel`, created 2026-03-27 and last touched 2026-08-18, `merged_at` null. Nothing on `stable-2.19`, `stable-2.20` or `stable-2.21` mentions the fix in its changelog, so 2.19.12, 2.20.8 and 2.21.3, the newest release on each branch as of 2026-08-10, all still carry it. An earlier version of this section named 2.19.9 and 2.20.5 as the end of the affected range, which was only ever the newest release at the time of writing and not a statement that anything later was fixed. Pre-bug version: 2.18.x, which is below this project's floor for other reasons.

**The version this repository runs, and where that is pinned.** ansible-core cannot be pinned to one exact version across the places it arrives from, because four package managers each publish exactly one and they do not agree: Debian trixie carries 2.19.4, Ubuntu 26.04 carries 2.20.1, Fedora 44 carries 2.20.7 and Arch carries 2.21.3. What is pinned is the half-open range 2.19.0 accepted up to but not including 2.22.0, in two places that enforce it rather than merely document it: `setup/setup.sh` reads the version behind `ansible-playbook` and refuses a control node outside `ANSIBLE_CORE_MIN_VERSION` to `ANSIBLE_CORE_MAX_VERSION_EXCLUSIVE`, and each Linux `e2e/tier3/*.Dockerfile` asserts the same two bounds at build time so a rolling distribution moving under the harness fails the image build in seconds instead of a scenario twenty-five minutes in. Widening either bound means running the e2e suite against the new branch first. Note what the range does not buy: no release inside it escapes the bug above, so the mitigations stay whatever version is in use.

**Upstream tracking:** issues [#86738](https://github.com/ansible/ansible/issues/86738), closed as a duplicate on 2026-03-31 and therefore no longer a place to watch for movement, and [#86562](https://github.com/ansible/ansible/issues/86562), still open. The pull request above is the one to watch.

**Mitigations in this repo**

1. **`ansible.builtin.raw` for the APT and Flatpak installs on Debian/Ubuntu** (`roles/software_installer/tasks/dynamic_install.yaml`). `raw` bypasses the entire Python module subsystem, no ansiballz and no JSON round-trip, so the bug class cannot trigger. Note that nothing in that file batches any longer: as of 2026-08-25 every manager installs one package per call, so each `raw` invocation is now short. It stays `raw` because a single large package can still run long enough to meet the race, and because switching mechanism is a change worth making deliberately rather than as a side effect. Arch and Fedora install through a `command` for the reporting rather than through their native modules, which report failure only through the result's `failed` key that this repository forbids reading.

2. **Ansible tmp dirs moved out of `/tmp`** (`ansible.cfg`): `local_tmp`, `remote_tmp`, and `fact_caching_connection` all point to `~/.ansible/...` instead of `/tmp/ansible-*`. The ansiballz zip lives in `local_tmp`; moving it away from `/tmp` removes the path contention with dpkg and systemd-tmpfiles. Works on live USB too since Ubuntu Live's `$HOME` is writable.

**When this can be reverted**

Once ansible-core ships a release that contains the fix from PR #86739 — both 2.19.x and 2.20.x branches will need a patched point release. After that:
- The `raw` flatpak/apt tasks can go back to `ansible.builtin.apt` / `community.general.flatpak` with `name: <list>`.
- The `~/.ansible/tmp` paths in `ansible.cfg` can stay (better default anyway) or revert to the older `/tmp` paths.

**Mandatory recurring check (every time this playbook is touched):**

Before recommending changes to the `raw` callsites or claiming the workaround is "still needed", verify the upstream status:

1. Check the current ansible-core release that this repo's target hosts will use. The version is in `ansible --version` on the dev machine, and the accepted range is the one `setup/setup.sh` enforces.
2. Confirm PR #86739 status: https://github.com/ansible/ansible/pull/86739 — merged or still open?
3. If merged, find the first release tag containing it: https://github.com/ansible/ansible/releases. Every branch this project accepts needs a patched point release before the workaround can go, which today means `stable-2.19`, `stable-2.20` and `stable-2.21`.
4. If the target ansible-core version is on a release that includes the fix, schedule the revert: replace the `raw` tasks (the per-package apt install, the per-application flatpak install, and apt-full-upgrade) with the native modules in one change, drop `apt_raw_env` / `apt_raw_flags` from `group_vars/linux.yaml`, and update this section. Reverting must not reintroduce a batch: `e2e/tier1/batched_managers.sh` fails on any manager that hands its whole set to one call, and the reasoning is in that file.
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
