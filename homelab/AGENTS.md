# AGENTS.md for homelab/

Rules for the home lab documents and its one Compose file. What the lab is, and the map of every page, is in [README_HOMELAB.md](README_HOMELAB.md). No Ansible runs here. Tier 1 checks only that the compose files resolve, that every homelab service caps its log, that every list of `.internal` names matches the setup table in [nginx_proxy_manager.md](nginx_proxy_manager.md#every-internal-name), and that the links work.

### Before you work here

1. Before reaching the lab itself, through the Proxmox API, SSH to the Proxmox host, the Docker VM or the router, Syncthing or Uptime Kuma, read [agent_access.md](agent_access.md).
2. Before adding a page here, add it to the documentation map of [README_HOMELAB.md](README_HOMELAB.md).

### Rules no check catches

1. Write instructions against `<angle-bracket>` placeholders so the pages stay reusable, then give this lab's own values in a concrete example block underneath.
2. Never commit a credential, an API token, a token secret, a device key or a MAC address. The credentials live in `~/.local/state/agents/workspace/homelab.env`, outside every repository.
3. Read the lab freely, and ask the owner before any change through any credential, then wait for his yes. The Proxmox token this lab uses can change, stop, roll back and delete virtual machines, so the rule is all that stops a change there.
