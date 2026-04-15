# Installation Helper

Welcome to the unified, cross-platform Installation Helper! This project automates the setup, installation, and configuration of development environments, utilities, and desktop settings across multiple operating systems.

## 🚀 Getting Started

The entire installation logic has been modernized and migrated to **Ansible**. It now supports a dynamic, data-driven approach allowing it to easily scale across different Linux distributions, macOS, and Windows.

For full instructions on how to use, configure, and run the new setup, please refer to the dedicated documentation:

👉 **[View the Setup Documentation](setup/README_SETUP.md)**

---

### Supported Operating Systems
* **Ubuntu / Debian**
* **Fedora**
* **Archlinux / Manjaro**
* **macOS**
* **Windows** (via WSL)

---

## 🐳 Local Development Docker Compose Setup

This repository also includes a comprehensive Local Development setup utilizing `docker-compose`. It instantly spins up pre-configured databases and authentication services needed for local software development, ensuring you don't need to install them directly on your host machine.

To start the setup, run the following command from the project root:
```bash
docker-compose -f ./local-dev/local-dev-docker-compose.yaml up -d
```

The stack currently includes:
* MySQL
* PostgreSQL
* MongoDB
* Keycloak (with HTTPS/SSL setup)

For instructions, database credentials, and port configurations, please refer to the dedicated documentation:

👉 **[View the Local Dev Documentation](local-dev/README_LOCAL_DEV.md)**

---

### Agent standards import

To import the central AI standards into this project without overwriting existing files, we use Git Selective Checkout. 

This approach extracts only the required AI folders and template files directly into the project root.

To protect the central repository, we configure the remote as a read-only source in your local workspace by setting the push URL to an invalid address. 

This ensures you can pull updates from the central repository, but Git will block any accidental pushes of your project-specific changes back to the global standards.

### Step 1: Initial Setup

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
git checkout agent-standards/master -- .agents .claude kilo.jsonc.example opencode.json.example AGENTS.md.example
```

```bash
git commit -m "Import central agent-standards (.agents and .claude)"
```

### Step 2: Pulling Future Updates

When the central standards repository is updated, pull the latest files into this project by running the following commands.

```bash
git fetch agent-standards
```

```bash
git checkout agent-standards/master -- .agents .claude
```

```bash
git commit -m "Update AI standards from central repository"
```