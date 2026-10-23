# MCP setup

> The six Model Context Protocol servers this project declares, what each one needs on your machine, and how to give it a key.

This page is for the person setting up the machine. An agent reads [AGENTS.md](../AGENTS.md) and uses whatever MCP tools its own client exposes, and never runs any of this.

---

### What this project declares

| Server | What it is for | What it needs |
|---|---|---|
| `context7` | Current documentation for libraries, frameworks, SDKs and APIs | nothing, it is hosted, and the free tier needs no key |
| `grafana` | Dashboards, metrics and alert rules on a Grafana instance | `uv`, a running Grafana and a service account token |
| `playwright` | Driving a browser for end-to-end web testing | Node.js, and about 500 MB of browsers on the first run |
| `chrome-devtools` | Reading console output, network requests and the page from Chrome | Node.js and a local Chrome |
| `redis` | Querying a Redis instance | `uv` and a running Redis, for example the one in [local-dev/README_LOCAL_DEV.md](../local-dev/README_LOCAL_DEV.md) |
| `n8n` | Reading and building n8n automation workflows | Node.js, and an n8n instance and API key to manage workflows rather than only read node documentation |

A server whose backing service is not running still starts, then fails to connect, and the other servers keep working.

---

### Where they are declared

All three files are committed, so a checkout is enough. Each tool reads its own:

| File | Read by | How it fills in a variable |
|---|---|---|
| [.mcp.json](../.mcp.json) | Claude Code | `${VAR:-default}`, so every server resolves with nothing set |
| [opencode.json](../opencode.json) | OpenCode and Kilo Code | no references at all, because one `{env:VAR}` makes Kilo Code reject the whole file. The addresses are written in, and a token reaches a server only through the environment the agent was started from |
| [.codex/config.toml](../.codex/config.toml) | Codex | no substitution, the addresses are written in and the two tokens are empty strings |

The defaults written into those files:

| Variable | Server | When it is not set |
|---|---|---|
| `CONTEXT7_API_KEY` | `context7` | sent empty from [.mcp.json](../.mcp.json), and not sent at all from the other two, so Context7 serves its free tier |
| `GRAFANA_URL` | `grafana` | `http://localhost:3000` |
| `GRAFANA_SERVICE_ACCOUNT_TOKEN` | `grafana` | empty, so Grafana refuses the connection |
| `REDIS_URL` | `redis` | `redis://localhost:6379/0` |
| `N8N_API_URL` | `n8n` | `http://localhost:5678` |
| `N8N_API_KEY` | `n8n` | empty, so the server only answers questions about n8n nodes |

`playwright` and `chrome-devtools` read no variable.

When a server answers nothing, check its variable before deciding the service is down.

---

### Install what the servers run

Node.js runs `context7` under Codex, `playwright`, `chrome-devtools` and `n8n`. Check it is there. PowerShell or Unix shell, same command:

```bash
node --version
```

`uv` runs `grafana` and `redis`. Install it on Windows:

```powershell
winget install --id=astral-sh.uv
```

On Linux or macOS:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

---

### Get the keys you need

Only for the servers you use.

| Key | Where to get it |
|---|---|
| `CONTEXT7_API_KEY` | [Context7 dashboard](https://context7.com/dashboard), only for higher rate limits than the free tier |
| `GRAFANA_SERVICE_ACCOUNT_TOKEN` | Grafana, Administration, Service accounts, add an account, then add a token. The `Viewer` role is enough for reading dashboards |
| `N8N_API_KEY` | n8n, Settings, API, Create API key |

---

### Set the variables for every program

Set them for your whole login rather than for one shell, so every agent and editor inherits them. The examples set `GRAFANA_SERVICE_ACCOUNT_TOKEN`, and the other variables work the same way.

#### Windows

For your user. New processes see it after a restart of the terminal:

```powershell
[Environment]::SetEnvironmentVariable('GRAFANA_SERVICE_ACCOUNT_TOKEN', 'glsa_xxxxxxxxxxxx', 'User')
```

Check it in a new PowerShell window:

```powershell
$env:GRAFANA_SERVICE_ACCOUNT_TOKEN
```

#### Linux

For your user only, then log out and back in:

```bash
echo 'GRAFANA_SERVICE_ACCOUNT_TOKEN=glsa_xxxxxxxxxxxx' >> ~/.profile
```

#### macOS

For Terminal and anything started from it:

```bash
echo 'export GRAFANA_SERVICE_ACCOUNT_TOKEN=glsa_xxxxxxxxxxxx' >> ~/.zprofile
```

For applications started from Finder. This does not survive a reboot:

```bash
launchctl setenv GRAFANA_SERVICE_ACCOUNT_TOKEN glsa_xxxxxxxxxxxx
```

Restart your terminal, your editor and every running agent after setting a variable.

---

### Check the servers loaded

Claude Code, from the repository root. Each server shows as connected or failed:

```bash
claude mcp list
```

OpenCode, Kilo Code and Codex each list their servers with `/mcp` typed inside the running agent.

---

### Adding or removing a server

Change all three files in the same change, [.mcp.json](../.mcp.json), [opencode.json](../opencode.json) and [.codex/config.toml](../.codex/config.toml), and update the server table in [AGENTS.md](../AGENTS.md) and on this page. The blocks for other servers are in the MCP setup page of [agent-standards](https://github.com/Lukk17/agent-standards). Every server you declare starts with every agent session, so declare only the ones you use.
