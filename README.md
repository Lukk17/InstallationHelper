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
