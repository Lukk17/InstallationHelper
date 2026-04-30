# Agent Tooling

This project integrates with multiple AI coding agents (Claude Code, Kilo Code, OpenCode, Codex) and uses [OpenSpec](https://github.com/Fission-AI/OpenSpec) for spec-driven development.

## Agent Standards Import

To import the central AI standards into this project without overwriting existing files, we use Git Selective Checkout. This approach extracts only the required AI folders and template files directly into the project root.

To protect the central repository, we configure the remote as a read-only source in your local workspace by setting the push URL to an invalid address. This ensures you can pull updates from the central repository, but Git will block any accidental pushes of your project-specific changes back to the global standards.

### Step 1: Initial Setup

Enable symlink support in Git:

Globally:
```shell
git config --global core.symlinks true
```

Locally for this repository only:
```shell
git config core.symlinks true
```

Run these commands in the root of this project to add the remote, disable pushing, and extract the specific payload files into your workspace.

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
git checkout agent-standards/master -- .agents .claude .kilocode .opencode .codex AGENTS.md.example kilo.jsonc.example opencode.json.example
```

```bash
git commit -m "Import central agent-standards"
```

### Step 2: Pulling Future Updates

When the central standards repository is updated, pull the latest files into this project by running the following commands.

```bash
git fetch agent-standards
```

```bash
git checkout agent-standards/master -- .agents .claude .kilocode .opencode .codex
```

```bash
git commit -m "Update AI standards from central repository"
```

---

## OpenSpec Integration

[OpenSpec](https://github.com/Fission-AI/OpenSpec) is a spec-driven development framework that installs skills and commands into each agent's native directories.

### How the symlinks work with OpenSpec

The `.kilocode/skills/`, `.opencode/skills/`, and `.codex/skills/` directories are all symlinked to `.agents/skills/`. When `openspec init` writes skills to any of these directories, they land in `.agents/skills/` — the canonical location already read by all agents.

Commands are tool-specific (different formats per agent) and cannot be centralized. OpenSpec creates them in each tool's native commands directory, which is expected and correct.

### Using OpenSpec in a project that imports agent-standards

After running Step 1 above, initialize OpenSpec in your project:

```bash
# Install OpenSpec globally
npm install -g @fission-ai/openspec@latest

# Initialize with all agents
# Skills land in .agents/skills/ via existing symlinks
# Commands are created in each tool's native commands directory
openspec init --tools "claude,kilocode,opencode,codex"
```

What `openspec init` creates:

```text
openspec/
  config.yaml              # OpenSpec project config
  specs/                   # Living documentation of your system
  changes/                 # Active feature work
    archive/               # Completed changes

# Skills (via symlinks, all land in .agents/skills/):
.agents/skills/openspec-workflow/SKILL.md
.agents/skills/openspec-specs/SKILL.md

# Commands (tool-specific, not symlinked):
.claude/commands/opsx/propose.md
.kilocode/workflows/opsx-propose.md
.opencode/commands/opsx-propose.md
```

Restart IDE and terminal after openspec initialization.

### OpenSpec tool directories reference

| Tool | Skills written to | Commands written to |
|---|---|---|
| Claude Code | `.claude/skills/openspec-*/` -> `.agents/skills/` | `.claude/commands/opsx/*.md` |
| Kilo Code | `.kilocode/skills/openspec-*/` -> `.agents/skills/` | `.kilocode/workflows/opsx-*.md` |
| OpenCode | `.opencode/skills/openspec-*/` -> `.agents/skills/` | `.opencode/commands/opsx-*.md` |
| Codex | `.codex/skills/openspec-*/` -> `.agents/skills/` | `$CODEX_HOME/prompts/opsx-*.md` |

### Command Syntax Variations

Because the AI coding landscape is fragmented, OpenSpec generates files for two different architectures. Depending on your specific agent UI, your commands will appear in one of two ways:
* **Standalone Markdown Commands**: Agents that read flat files will show commands with extensions in their dropdowns (e.g., `/opsx-propose.md`).
* **Agent Skills**: Agents that parse semantic SKILL.md metadata or have native integration will use standard slash syntax (e.g., `/opsx:propose`).

Use the syntax that appears in your agent's autocomplete menu.

### The Full OpenSpec Workflow

Once initialized, invoke OpenSpec skills from your agent using the full artifact-driven lifecycle:

#### 0. Run Coding Agent

You need to start coding agent first - for example, by running in terminal:
```shell
claude
```

#### 1. Propose the change

Use multiline prompts to include logs or detailed context. Inside coding agent shell run your specific command variation:

```text
/opsx:propose add dark mode support
```

```text
/opsx-propose.md add dark mode support
```

The agent creates the proposal, design, and implementation tasks under `openspec/changes/`.

#### 2. Apply the code

Review the generated `tasks.md` by manually editing md files or just telling agent what is wrong with it.

After plan approval agent can start implementation:

```text
/opsx:apply
```

```text
/opsx-apply.md
```

The agent writes the code and checks off the boxes in your `tasks.md`.

#### 3. Verify and refine

If bugs occur or tests fail, pass the logs back to refine the implementation.

```text
/opsx:verify The toggle button is invisible on mobile. Fix it.
```

```text
/opsx-verify.md The toggle button is invisible on mobile. Fix it.
```

#### 4. Archive the change

Once the code is working and tested, merge the documentation.

```text
/opsx:archive
```

```text
/opsx-archive.md
```

The agent merges the delta specs into `openspec/specs/` and moves the change folder to `openspec/changes/archive/`.