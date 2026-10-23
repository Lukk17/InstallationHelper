# Plex Media Server

> Films and series from the USB data disk, played on TVs, phones and browsers at home, with the free Plex account, no Plex Pass, no graphics card, and video conversion kept off this mini PC as far as Plex allows.

---

### The rule this page is built around

The mini PC has six CPU cores and no graphics card handed to Plex. Converting video on the fly, which Plex calls transcoding, would eat most of that and starve AdGuard, which answers DNS for the whole house. So the plan is:

1. Store only files that the players here can play as they are, which Plex calls Direct Play. The formats are listed below.
2. Turn off every Plex setting that starts a conversion on its own.
3. Cap the Plex container at 1.5 CPU cores in [compose.yaml](compose.yaml), so even a conversion Plex insists on cannot take over the machine.

Plex has no single switch that turns all conversion off. The details, with Plex's own wording, are under Transcoding settings below.

---

### Placeholders

| Placeholder | Meaning |
|---|---|
| `<docker-vm-ip>` | Address of the Ubuntu VM running the Compose stack |
| `<claim-token>` | A one-time token from `https://www.plex.tv/claim`, valid for a few minutes |

Concrete example, the lab these documents were written from:

```text
<docker-vm-ip>   192.168.1.12
```

---

### Before you start

The data disk has to be attached and mounted at `/mnt/data`, with a `media` folder at its top, `/mnt/data/media`, owned by `1000:1000`. That is all in [lan_storage.md](lan_storage.md), for a new disk and for an existing NTFS disk. Plex will not start without it, on purpose, because its library mount uses `create_host_path: false`.

---

### Adding films

The library is the `media` folder at the top of the shared disk from [lan_storage.md](lan_storage.md), so films go in the same way as any other file:

1. Over the network drive, copy them to `\\drive.internal\files\media` on Windows, or `smb://drive.internal/files/media` on macOS and Linux.
2. In a browser, open `http://drive.internal`, go into the `media` folder and upload them in File Browser.

Keep the folders the library points at, for example `media\films` and `media\series`. New files appear in Plex after a library scan. To scan at once, open the library in the web app and choose Scan Library Files.

This layout has a cost. Anyone with the Samba login or a File Browser account can rename or delete a film, because both of those write to the whole shared disk. Plex mounts the folder read only, so Plex itself can never delete a file, but that does not protect anything from the people who share the drive. If someone deletes or renames the `media` folder itself, Plex will not start until it is back, see When it misbehaves below.

---

### The container

The image is `plexinc/pms-docker:1.43.4.10903-e5521bd8c`, the official one published by Plex on Docker Hub from the `plexinc/pms-docker` GitHub repository. That tag was the newest on 2026-10-10, pushed on 10 September 2026. A version tag has the server built in and does not update itself. The README warns that only the `beta` and `public` tags fetch a new version on every restart, which is exactly the floating behaviour this stack avoids.

| Setting | Value | Why |
|---|---|---|
| `network_mode` | `host` | See the next section |
| `cpus` | `1.5` | Hard limit, see below |
| `PLEX_UID`, `PLEX_GID` | `1000` | Same user as the files on the disk |
| `PLEX_CLAIM` | from `.env`, empty after the first start | Links the server to your Plex account once |
| `/config` | `/opt/docker-stack/plex/config` | The Plex database, metadata and settings |
| `/transcode` | `/opt/docker-stack/plex/transcode` | Temporary files, if a conversion happens anyway |
| `/data` | `/mnt/data/media`, read only | The library. Plex can read it and never change or delete a file |

Create the two Plex folders:

```bash
mkdir -p /opt/docker-stack/plex/config /opt/docker-stack/plex/transcode
```

---

### Why host networking

Every other container in this stack sits on the `proxy-tier` bridge network. Plex does not, because on a bridge network Plex sees home devices as coming from another network, and with a free account that blocks playback.

Plex's support article [Requirements for Remote Playback of Personal Media](https://support.plex.tv/articles/requirements-for-remote-playback-of-personal-media/) (last modified 10 April 2026, read 2026-10-10) says that since 2025-04-29 remote video playback needs a Plex Pass or a Remote Watch Pass, and under What is "Remote" Playback in this Context?: "In this context, "remote" playback would be any time that the player app cannot make a connection to the Plex Media Server on the same subnet of the same local network." Its list of things that break that detection includes "Running apps or servers inside a container/virtualization and not using "host networking"".

Fixing it on a bridge network would need the LAN Networks setting, and the [Network](https://support.plex.tv/articles/200430283-network/) article (last modified 23 September 2025) says of it: "This feature requires an active Plex Pass subscription". Host networking needs nothing paid: Plex listens on `<docker-vm-ip>:32400`, on the same subnet as every TV and phone at home.

With host networking there is no `ports:` list. Plex opens 32400 for the server and its own discovery ports straight on the VM.

---

### The CPU cap

`cpus: 1.5` in [compose.yaml](compose.yaml) is a hard ceiling enforced by the kernel. Plex cannot use more than one and a half cores' worth of time, whatever it is doing.

The number counts the Docker VM's cores, not the host's. The VM has four, from [proxmox_docker_vm.md](proxmox_docker_vm.md), so Plex gets at most 1.5 of them and AdGuard, Nginx Proxy Manager and the rest always keep at least 2.5. On the host's six cores that is a quarter of the machine.

Direct Play sends the file as it is and costs almost nothing, and Direct Stream only repackages it, which Plex's [Direct Play and Direct Stream](https://support.plex.tv/articles/200250387-streaming-media-direct-play-and-direct-stream/) article describes as using "very little processing power without any loss in video quality". Both fit inside 1.5 cores with room to spare. A real video conversion does not: under the cap it simply runs slower than real time and the player buffers, which is the visible sign that a file is in the wrong format. That is the intended failure, a stuttering film rather than the whole house losing DNS.

If you ever give Plex a bigger share, change the number in [compose.yaml](compose.yaml) and recreate the container with `docker compose up -d plex`.

---

### Claim the server

Claiming links this server to your Plex account. Use a free account.

1. Sign in at `https://www.plex.tv/claim` and copy the token. It works only about 4 minutes, so run steps 2 and 3 back to back, with no pause between them.
2. Add it to `/opt/docker-stack/.env`, next to the Samba entries from [lan_storage.md](lan_storage.md). Paste the token at the prompt. It is not shown, and it never reaches the shell history:

```bash
read -r -s -p 'Plex claim token: ' PLEX_CLAIM; echo
```

Write it:

```bash
printf 'PLEX_CLAIM=%s\n' "$PLEX_CLAIM" >> /opt/docker-stack/.env
```

Remove it from the shell:

```bash
unset PLEX_CLAIM
```

Check it without printing any value. This prints each name in the file and the length of its value, and `PLEX_CLAIM` must show a number above 0:

```bash
awk -F= '{print $1, length($2)}' /opt/docker-stack/.env
```

3. Start Plex:

```bash
cd /opt/docker-stack && docker compose up -d plex
```

4. Open `http://<docker-vm-ip>:32400/web` and sign in with the same account. The setup wizard names the server and offers to add a library.
5. Remove the `PLEX_CLAIM` line from `.env`. The README says the claim is a first-run parameter that is ignored once the server is logged in, so leaving a used token behind only leaves clutter.

```bash
sed -i '/^PLEX_CLAIM=/d' /opt/docker-stack/.env
```

Check it. `PLEX_CLAIM` must no longer be in the list:

```bash
awk -F= '{print $1, length($2)}' /opt/docker-stack/.env
```

If the token ran out before the first start, the server comes up unclaimed. Stop it, get a fresh token, remove the old line with the `sed` command from step 5, add the new token with the commands from step 2, and start it again.

Add a library in the wizard or later under Settings, then Manage, then Libraries. Point it at `/data` or a folder under it, for example `/data/films` and `/data/series`, which are `/mnt/data/media/films` and `/mnt/data/media/series` on the VM and `\\drive.internal\files\media\films` and `\\drive.internal\files\media\series` on the network drive. Paths in Plex are paths inside the container.

---

### Reaching it at plex.internal

`http://plex.internal/web` goes through Nginx Proxy Manager like the other names, with an entry in [nginx_proxy_manager.md](nginx_proxy_manager.md). Because Plex is on the host network, that entry forwards to `<docker-vm-ip>` on port 32400, the same way the Proxmox entry forwards to an address.

That name is a convenience for opening the web app. TV and phone apps never use it: they find the server through your Plex account and connect to `<docker-vm-ip>:32400` directly. If the web app opened through `plex.internal` ever says playback needs a Remote Watch Pass, the proxy hop made Plex treat the browser as remote, so open `http://<docker-vm-ip>:32400/web` instead. This was not measured on this lab.

Remote Access stays off. Nothing here is exposed to the internet, and with a free account remote video playback would not work anyway.

---

### Transcoding settings

Open `http://<docker-vm-ip>:32400/web`, then Settings. Sources are Plex's own support articles, each read on 2026-10-10.

Settings, then Transcoder, then Show Advanced:

1. Disable video stream transcoding: on. From [Transcoder](https://support.plex.tv/articles/transcoder/) (last modified 30 September 2026): "Disable transcoding of the video stream in transcoder operations. With this set, the transcoder may still transcode audio as well as remux video. If this option is enabled and the video stream would require transcoding to be compatible for playback, then it can result in playback failing." This is the closest thing to an off switch, and it is not a full one: audio is still converted when needed, and a file that needs video conversion fails to play instead.
2. Maximum simultaneous video transcode: 1. Same article: "Set the maximum number of transcoding sessions that you will allow simultaneously. For instance, if you only want to allow two transcodes to happen at any one time (even if your computer is capable of more), you can set the value to 2." With video conversion disabled this is a second guard, so one mistake cannot become several at once.
3. Transcoder quality: leave on Automatic. [Server Settings, Bandwidth and Transcoding Limits](https://support.plex.tv/articles/227715247-server-settings-bandwidth-and-transcoding-limits/) (last modified 25 May 2023, checked against the newer Transcoder article above, which lists the same settings): "We definitely recommend leaving this set to the default Automatic value."
4. Use hardware acceleration when available: not available here. The Transcoder article says it "Requires an active Plex Pass subscription", and no graphics device is passed into the container.

Settings, then Library, the background jobs that also burn CPU:

1. Generate video preview thumbnails: never. From [Library](https://support.plex.tv/articles/200289526-library/) (last modified 4 May 2025): "Creating these images can take a considerable amount of time, CPU resources, and increase the storage space used."
2. Generate intro video markers and Generate credits video markers are Plex Pass features, so they do nothing on a free account.

In each player app, the client side:

1. Set video quality for home streaming to Original or Maximum. The [Smart TV formats](https://support.plex.tv/articles/203810286-what-media-formats-are-supported/) article (last modified 12 December 2023): "Setting a streaming quality value lower than the content's bitrate will cause the video to be transcoded."
2. Leave Direct Play and Direct Stream on. From [Plex Web App Settings](https://support.plex.tv/articles/200289408-plex-web-app-settings/) (last modified 17 December 2024): "This setting is enabled by default and most users should leave it enabled."

Remote quality limits, "Limit remote video quality" and "Internet upload speed", only apply to remote streams, which this setup does not allow, so they need no change. Per-user stream limits are on the Network page and need a Plex Pass. No per-library or per-user setting to forbid conversion was found in Plex's support articles.

---

### What to store

Store this, and every app here plays it directly:

| Part | Use | Avoid |
|---|---|---|
| Container | MP4 | MKV, AVI, WMV in the browser |
| Video | H.264, 8 bit, up to 1920×1080, level 4.0 or lower, 30 frames per second or lower | HEVC for browsers and older TVs, 10 bit, VC-1, MPEG-2 |
| Audio | AAC, stereo or 5.1 | DTS, TrueHD, FLAC inside a video |
| Subtitles | Separate `.srt` text files | Picture subtitles such as PGS from Blu-ray rips |

Sources, each read on 2026-10-10:

1. Browsers. [Plex Web App Settings](https://support.plex.tv/articles/200289408-plex-web-app-settings/) (last modified 17 December 2024), under Direct Play: "Enabling this will allow the browser to play compatible items without any transcoding. For most browsers, this will mean MP4 files with H.264 video and AAC audio."
2. Smart TVs. [What media formats are supported on Smart TVs?](https://support.plex.tv/articles/203810286-what-media-formats-are-supported/) (last modified 12 December 2023): "Native video support is typically (but not always) limited to the MP4 container, H.264 video encoding, and AAC audio." Its list for safe Direct Play is "Container: MP4, Resolution: 1920×1080 or smaller, Video Encoding: H.264 (level 4.0 or lower), Video Framerate: 30fps, Video Bit Depth: 8, Audio Encoding: AAC". Many LG and Samsung models play more, MKV and HEVC included, but the safe set is the one that plays everywhere.
3. Subtitles. [Direct Play and Direct Stream](https://support.plex.tv/articles/200250387-streaming-media-direct-play-and-direct-stream/) (last modified 27 March 2019, still the current Plex article): "if a subtitle stream is selected and is not compatible with the Plex App, then the Server will "burn in" the subtitle text within the video. This requires a full transcode of the video stream." With video conversion disabled, such a film will not play with those subtitles on.
4. 4K. The same Smart TV article: "4K content not matching the above properties will be transcoded to 1080p. Transcoding 4K content is a very intensive process and will require a powerful computer running Plex Media Server." Keep 4K files only if every TV that will play them is a 4K set that takes HEVC in MP4, and expect browsers to fail on them.

Convert files on your own PC before copying them, never on the server. HandBrake, for example, has an H.264 and AAC preset in MP4 that matches the table above.

To check what Plex will do with a file, play it and open the Dashboard in the web app while it plays. The session shows Direct Play, Direct Stream or Transcode. Anything that says Transcode is a file to convert on your PC.

---

### Verify

The server answers on its own address, without a login, at the `identity` endpoint.

Unix shell:

```bash
curl -s http://<docker-vm-ip>:32400/identity
```

PowerShell:

```powershell
curl.exe -s http://<docker-vm-ip>:32400/identity
```

A short XML reply with the server version means it is up. Then confirm the CPU cap is in place:

```bash
docker inspect plex --format '{{.HostConfig.NanoCpus}}'
```

`1500000000` is 1.5 cores. `0` means no limit, so the container was started from an older `compose.yaml`.

---

### When it misbehaves

Plex will not start and the error mentions `/mnt/data/media`. Either the data disk is not mounted, see [lan_storage.md](lan_storage.md), or the `media` folder was deleted or renamed through the network drive or File Browser. File Browser and Samba keep running in both cases, so run `findmnt /mnt/data`: no output means the disk is not mounted, and a line means it is the folder. Put the folder back, or create it again with `mkdir /mnt/data/media`, then run `docker compose up -d plex`.

A TV app does not find the server. The TV and the VM must be on the same subnet, and Plex must run with `network_mode: host`. Check with `docker inspect plex --format '{{.HostConfig.NetworkMode}}'`, which must print `host`.

A film plays in one app and fails or buffers in another. That app cannot play the format directly and Plex is not allowed to convert the video. Check the Dashboard as above, then convert that file on your PC.

A film fails only with subtitles on. Picture subtitles need burning in, which is a video conversion. Use an `.srt` file instead.

The library is empty although the files are on the disk. The library path in Plex was typed as `/mnt/data/media`. Inside the container the path is `/data`.
