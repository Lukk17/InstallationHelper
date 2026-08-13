# Perlite Notes Site

> Serving the Syncthing notes folder as a plain website, so an old phone or tablet with no Obsidian client can still
> read the vault.

---

### How it fits together

Two containers do the work. `perlite` is the PHP engine that renders the markdown, and `perlite-web` is its own
nginx in front of it. They share a filesystem through `volumes_from`, which is why nginx can serve the engine's CSS
and JavaScript without a second copy of the files.

The notes themselves arrive over Syncthing. The Syncthing container mounts the host directory
`/opt/docker-stack/syncthing/data` as `/data` inside itself, so a Syncthing folder configured at `/data/notes`
writes to `/opt/docker-stack/syncthing/data/notes` on the host. That is exactly the directory Perlite mounts, read
only, as its notes root.

Nothing writes back. Perlite has no editor, no login, and the mount is read only.

---

### Prepare the directories

Create the notes directory and the one holding the nginx config:

```bash
sudo mkdir -p /opt/docker-stack/perlite /opt/docker-stack/syncthing/data/notes
```

Perlite ships its own nginx configuration, and the container will not serve anything sensible without it:

```bash
sudo curl -fsSL https://raw.githubusercontent.com/secure-77/Perlite/main/web/config/perlite.conf -o /opt/docker-stack/perlite/perlite.conf
```

---

### Start the two containers

Move into the stack directory:

```bash
cd /opt/docker-stack/InstallationHelper/homelab
```

Bring up only these two:

```bash
docker compose up -d perlite perlite-web
```

---

### Pair Syncthing with the machine that holds the notes

Open both interfaces. On the machine with the vault, Syncthing runs at `http://localhost:8384`. On the server, the
container is published at `http://<docker-vm-ip>:7780`.

1. On your own machine: Actions, then Show ID, and copy it.
2. On the server: Add Remote Device, paste the ID, save.
3. On your own machine: accept the pairing prompt.
4. On your own machine: Add Folder, point it at the vault directory, and tick the server under Sharing.
5. On the server: accept the folder and set its path to `/data1/notes`.

Put a `README.md` at the top of the folder. Perlite uses it as the landing page, which is what `HOME_FILE=README`
in the Compose file means.

---

### Add the proxy entry

In Nginx Proxy Manager, add one more proxy host following
[nginx_proxy_manager.md](nginx_proxy_manager.md).

| Domain name | Scheme | Forward hostname | Port | Websockets |
|---|---|---|---|---|
| `notes.internal` | http | `perlite-web` | 80 | on |

No DNS change is needed. The `*.internal` wildcard rewrite in AdGuard already covers every new name.

Then open `http://notes.internal`.

---

### Things that will bite you

`NOTES_PATH` has to match the directory name inside the container, not the host path. The Compose file mounts the
notes at `/var/www/perlite/notes` and sets `NOTES_PATH=notes`. Change one without the other and the site renders
empty.

`volumes_from: perlite` on the web container is required. Drop it and every CSS and JavaScript request returns 404,
because nginx is then serving from a filesystem that has no Perlite assets in it.

The address `syncthing:8384` only resolves between containers on the `proxy-tier` network. From a browser on your
own machine, use `<docker-vm-ip>:7780` instead.

The Syncthing folder path is the container path `/data/notes`, not the host path. Typing the host path into the
Syncthing interface creates a folder the container cannot see.
