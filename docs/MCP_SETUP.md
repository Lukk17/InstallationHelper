# MCP Setup

Human setup guide for the Model Context Protocol (MCP) servers used in this project.

This file is for the **person** configuring the machine. The AI agent reads `AGENTS.md` and uses whatever MCP tools the running agent exposes — it doesn't need this document.

---

## What this project uses

One MCP server is configured here:

| Server     | Purpose                          | External dependency                            |
| ---------- | -------------------------------- | ---------------------------------------------- |
| `context7` | Up-to-date library docs lookup   | none (hosted HTTP, free tier without API key)  |

The agent-standards repo ships seven other servers in its template (`mongodb`, `grafana`, `playwright`, `chrome-devtools`, `redis`, `sonarqube`, `n8n`). This project doesn't use any of them and they've been removed from the local configs. If you ever want them back, copy the relevant block from [agent-standards](https://github.com/Lukk17/agent-standards) into `.mcp.json` and `opencode.json`.

---

## Where it's configured

Both files are committed at the repo root:

- `.mcp.json` — Claude Code project scope. Schema key `mcpServers`. Env-var syntax: `${VAR}` and `${VAR:-default}`.
- `opencode.json` — OpenCode + Kilo Code project scope (shared file). Schema key `mcp` alongside `instructions`. Env-var syntax: `{env:VAR}` (no `$`).

Both contain only the `context7` block. Nothing else to copy — checkout is enough.

---

## Step 1 — Optional: set `CONTEXT7_API_KEY`

Without a key, Context7 still works on the free tier (lower rate limits). Get a key only if you hit those limits.

Source: <https://context7.com/dashboard>

### Linux

System-wide:

```bash
echo 'CONTEXT7_API_KEY=ctx7_xxxxxxxxxxxx' | sudo tee -a /etc/environment
```

Current user only:

```bash
echo 'export CONTEXT7_API_KEY=ctx7_xxxxxxxxxxxx' >> ~/.profile
```

Log out and back in to apply. For interactive shells only, append to `~/.zshrc` or `~/.bashrc`.

### macOS

For Terminal and IDE shells:

```bash
echo 'export CONTEXT7_API_KEY=ctx7_xxxxxxxxxxxx' >> ~/.zprofile
```

For GUI apps launched from Finder (Claude Desktop):

```bash
launchctl setenv CONTEXT7_API_KEY ctx7_xxxxxxxxxxxx
```

`launchctl` resets on reboot. Persist via `~/Library/LaunchAgents/setenv.CONTEXT7_API_KEY.plist` or [direnv](https://direnv.net/) per project.

### Windows

Current user (visible to new processes after restart):

```powershell
[Environment]::SetEnvironmentVariable('CONTEXT7_API_KEY', 'ctx7_xxxxxxxxxxxx', 'User')
```

System-wide (Administrator):

```powershell
[Environment]::SetEnvironmentVariable('CONTEXT7_API_KEY', 'ctx7_xxxxxxxxxxxx', 'Machine')
```

Verify in a fresh PowerShell session:

```powershell
$env:CONTEXT7_API_KEY
```

Restart your terminal, IDE, and any running agent shell after changing system variables. Claude Desktop must be fully quit (system-tray icon) and relaunched.

---

## Step 2 — Verify the MCP loaded

After restarting your agent:

- **Claude Code** — run `claude mcp list`. `context7` should show as connected.
- **OpenCode / Kilo Code** — run `/mcp` inside the agent shell.
- **Claude Desktop** — open the Developer panel; the MCP indicator in the input box shows connected servers.
- **Codex CLI** — `codex` then `/mcp` (Codex 0.20+).

If `context7` fails to connect:

- Claude Code logs the reason to its standard log.
- Claude Desktop logs land in `~/Library/Logs/Claude/` (macOS) or `%APPDATA%\Claude\logs\` (Windows). File: `mcp-server-context7.log`.

The free tier needs nothing. A 401 means your `CONTEXT7_API_KEY` is set but wrong — unset it and Context7 falls back to free tier.

---

## User-global configs (per machine, optional)

The committed `.mcp.json` covers Claude Code's project scope. Three other files run user-global; none ship in this repo.

### Claude Code user-global — `~/.claude.json`

Same `mcpServers` schema. Same `${VAR}` substitution. Used when you're outside any project that defines its own `.mcp.json`. Project file wins on name collisions.

Populate from the project file:

```bash
cp .mcp.json ~/.claude.json
```

If `~/.claude.json` already exists, merge the `mcpServers` block by hand — Claude Code keeps other top-level keys there (`theme`, `editorMode`, etc.).

### Claude Desktop

- macOS: `~/Library/Application Support/Claude/claude_desktop_config.json`
- Windows: `%APPDATA%\Claude\claude_desktop_config.json`
- Linux: no official Claude Desktop build.

Same `mcpServers` schema. **Does not support env-var substitution** — inline the actual API key (the file is per-machine personal, so inlining is acceptable; never commit it).

```json
{
  "mcpServers": {
    "context7": {
      "type": "http",
      "url": "https://mcp.context7.com/mcp",
      "headers": {
        "CONTEXT7_API_KEY": "ctx7_actual_value_or_empty"
      }
    }
  }
}
```

### Codex CLI — `~/.codex/config.toml`

Different format (TOML, not JSON). Global-only, no project scope.

```toml
[mcp_servers.context7]
command = "npx"
args = ["-y", "@upstash/context7-mcp@latest"]
```

Codex has no built-in env-var substitution. If you want the API key out of the file, wrap the command in a small shell script that reads from your secrets manager.

---

## Env-var substitution support matrix

| Tool / config file                              | Substitution syntax            |
| ----------------------------------------------- | ------------------------------ |
| Claude Code, `.mcp.json` and `~/.claude.json`   | `${VAR}`, `${VAR:-default}`    |
| OpenCode / Kilo Code, `opencode.json`           | `{env:VAR}`                    |
| Claude Desktop, `claude_desktop_config.json`    | **not supported** — inline     |
| Codex CLI, `~/.codex/config.toml`               | TOML; no built-in substitution |

---

## Adding more MCP servers later

To add one of the seven removed servers (`mongodb`, `grafana`, `playwright`, etc.) or any other MCP:

1. Copy the relevant block from [agent-standards `.mcp.json.example`](https://github.com/Lukk17/agent-standards) and from `opencode.json.example` into the local files here.
2. Install any external dependency (`uv` for grafana/redis; Docker for sonarqube; a running backing service for mongodb/redis/n8n).
3. Set the relevant env var(s) — see the agent-standards version of this doc for the full key/URL table.
4. Restart your agent and verify with `claude mcp list` / `/mcp`.

The committed `.mcp.json` here is intentionally minimal. Don't add servers you won't actually use — each one spawns a subprocess on every agent launch.
