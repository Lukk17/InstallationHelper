# Syncthing

> Continuous file sync between your own machines, with no cloud account in the middle. Here it also feeds the notes site described in [perlite_notes.md](perlite_notes.md).

---

### What it is doing here

Syncthing keeps a folder identical across every device you pair with it. There is no server in the sense of somewhere your files are uploaded to. Each device holds the real files, and they gossip changes directly to each other.

On this stack it plays two roles. It is the sync target for whatever you want mirrored off your own machines, and the directory it writes into is the same directory the notes site reads from, which is what turns a folder of markdown into a website nobody had to publish.

---

### The paths that matter

Get these wrong and nothing works, so they are worth stating plainly.

| Inside the container | On the host | Holds |
|---|---|---|
| `/config` | `/opt/docker-stack/syncthing/config` | Device identity, keys, folder list |
| `/data` | `/opt/docker-stack/syncthing/data` | The files themselves |

Every path you type into the Syncthing interface is a container path. When you add a folder and it asks where it lives, the answer starts with `/data`, never with `/opt`. Typing the host path creates a folder the container cannot see, and the interface will happily let you do it.

The notes folder used by the site is therefore `/data/notes` inside the container, which is `/opt/docker-stack/syncthing/data/notes` on the host.

`/config` holds the device identity. Lose it and this machine becomes a different device to every peer, and you get to accept every pairing again. It is inside `/opt/docker-stack/`, which is what [backup_restore.md](backup_restore.md) tells you to copy off the box.

---

### Ports

| Port | Protocol | For |
|---|---|---|
| 7780 | TCP | The web interface, mapped to 8384 inside the container |
| 22000 | TCP and UDP | The sync protocol itself, how devices actually move data |
| 21027 | UDP | Local discovery, how devices find each other on the same network |

Only 7780 goes through the reverse proxy. The other two are peer to peer and must reach the container directly, which is why they are published in the Compose file rather than proxied.

---

### First run

Open the interface at `http://<docker-vm-ip>:7780`, or `http://syncthing.internal` once the proxy entry from [nginx_proxy_manager.md](nginx_proxy_manager.md) exists.

There is no login by default. On a private network that is survivable, but set one anyway under Actions, then Settings, then the GUI tab, because anything on your LAN can otherwise reconfigure your file sync.

Under the same settings, give the device a name you will recognise from the other end.

---

### Pair two devices

Pairing is symmetric. Each side has to accept the other, and the order below is the one with the fewest confusing moments.

1. On your own machine, open Syncthing at `http://localhost:8384`, choose Actions, then Show ID, and copy the identifier.
2. On the server, choose Add Remote Device, paste the identifier, and save.
3. Wait. Discovery takes anywhere from a few seconds to a few minutes, and nothing you do speeds it up.
4. On your own machine, accept the pairing prompt when it appears.

The two devices are now aware of each other but share nothing yet. Folders are shared one at a time, deliberately.

---

### Share a folder

1. On the machine that holds the real files, choose Add Folder and point it at the directory you want synced.
2. On the Sharing tab of that folder, tick the server.
3. Wait again for the server to notice.
4. On the server, accept the offered folder, and set its path to a location under `/data`. For the notes vault that is `/data/notes`.

Send and receive is the right folder type on both ends for a vault you edit from either side. If one side should never write, set that side to Receive Only, which is a much friendlier failure than two devices arguing over the same file.

---

### Ownership, the thing that actually bites

The container runs as the user and group identifiers set in the Compose file, both `1000` here. Everything it writes on the host is owned by that pair.

If the container cannot write to a directory you created as root, the folder sits in an error state and the message points at permissions.

Fix the ownership of the data root on the virtual machine:

```bash
sudo chown -R 1000:1000 /opt/docker-stack/syncthing
```

`1000` is the first user created on most Linux installs, so on the Ubuntu virtual machine it is usually your own login and no further work is needed. Check with `id -u` if you are unsure, and change the Compose values rather than fighting the ownership if yours differ.

---

### File versioning

Sync is not backup. A file deleted on one device is deleted everywhere, promptly and faithfully.

For anything you would miss, open the folder, then Versioning, and choose a policy. Simple File Versioning keeping a handful of copies is enough to survive the usual mistake, and it stores the old copies inside a hidden directory in the folder itself.

This does not replace [backup_restore.md](backup_restore.md). It replaces the specific panic of having deleted the wrong file five minutes ago.

---

### What not to sync

Anything with an active writer on both ends at once. Databases, virtual machine disks and application state directories all corrupt cheerfully when two devices write to them.

Syncthing is for documents, notes, photos, code and configuration. For a database, back it up to a file and sync the file.

---

### When it misbehaves

The folder shows Out of Sync and stays there. One of the devices is offline, or is paused. Check the remote device panel on the right of the interface.

Devices never find each other. Local discovery uses UDP 21027, and the sync protocol uses 22000. If they are on different networks, one of them also needs to reach the internet for the discovery servers.

The folder shows a permission error. Ownership, covered above.

The notes site is empty but the folder syncs fine. The site reads `/data/notes` specifically, and the folder path is set to something else. This is by far the most common version of the problem, and [perlite_notes.md](perlite_notes.md) has the rest of it.

The address `syncthing:8384` works from other containers but not from your browser. That name only resolves on the Docker network shared by the stack. From your own machine use `<docker-vm-ip>:7780`.
