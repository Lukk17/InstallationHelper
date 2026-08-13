# Home Assistant Backup and Restore

> Home Assistant's own backups, which are the ones that bring your automations, add-ons and Zigbee network back. Separate from the whole machine image described in [backup_restore.md](backup_restore.md), and neither replaces the other.

---

### Two backups, two jobs

A `vzdump` archive of the virtual machine is bare metal recovery. It restores the disk exactly as it was, including a broken state if that is what you captured. It is large, it only restores onto Proxmox, and it is the right tool when the host disk dies.

A Home Assistant backup is a portable archive of your setup. It restores through the Home Assistant interface, onto a fresh machine, onto different hardware, even onto a completely different kind of install. It is the right tool when you have broken your configuration, are moving to new hardware, or are rebuilding the machine on purpose.

Keep both. They fail in different ways.

---

### Where it lives

Settings, then System, then Backups.

That page is the whole feature. Everything below happens there.

---

### The encryption key comes first

Every backup is encrypted. Home Assistant generates an encryption key for you and shows it once, as part of what it calls the backup emergency kit.

Save it somewhere that is not Home Assistant. A password manager is the obvious place. Printed and put in a drawer is also fine.

Without that key an encrypted backup is a pile of noise. There is no recovery path, no support address that can unlock it, and you will discover this at exactly the moment you need the backup. This is the single most common way people lose a Home Assistant install that they thought was backed up.

You can generate a new key later under Settings, then System, then Backups, then the automatic backup settings, under Encryption key. Doing so does not re-encrypt the archives you already have, so old backups still need the key that was current when they were written. Keep the old one until you have deleted the last backup that uses it.

Version 2026.4 modernised the encryption, moving to Argon2id for deriving the key and XChaCha20-Poly1305 for the data, with tamper detection on by default. Backups written before that still restore, using the key they were made with.

---

### Turn on automatic backups

A backup you have to remember to take is a backup you do not have.

On the Backups page, open the automatic backup settings and choose three things.

The schedule, which can be daily or specific days, at a fixed time or whenever Home Assistant judges the system to be idle.

How many to keep, after which the oldest are deleted for you.

Where they go. Local storage is the default, and it writes into `/backup` on the machine itself. Home Assistant Cloud gives you 5 GB at no extra cost on a subscription. Network storage covers a NAS or a mounted share.

Pick at least one location that is not the machine being backed up. A backup sitting in `/backup` on a virtual machine whose disk has just failed is not a backup.

---

### Take a full backup by hand

Before an upgrade, before touching add-ons, before anything you might regret.

On the Backups page, create a backup, give it a name that says why you took it, and choose Full rather than Custom.

A full backup contains `config`, `share`, `addons`, `ssl` and `media`.

The word full matters for Zigbee. A partial backup that skips add-ons leaves Zigbee2MQTT and its data behind, which means the network key and the device list are gone. Restoring that gets you a Home Assistant with no Zigbee devices and no way to re-adopt them without re-pairing every one of them by hand. Take full backups.

---

### Get a copy off the machine

From the Backups page, open a backup and download it. The file lands in your browser's download folder.

Do this for anything you would be upset to lose, even with automatic backups going to another location, because the copy you control is the one that survives a mistake in the automation.

---

### Restore onto a running system

On the Backups page, select the backup, choose what to restore from it, and confirm.

Home Assistant restarts to apply it. A large install can take around three quarters of an hour, most of which is add-ons being reinstalled, so start it when you do not need the house to respond.

---

### Restore during onboarding

This is the path after a rebuild, when Home Assistant comes up asking you to create an account.

On the onboarding screen, choose to restore from a backup rather than starting fresh. Upload the file, or pull it from Home Assistant Cloud if that is where it went.

You will be asked for the encryption key, then for the login of the original install, since user accounts come back with the backup rather than being recreated.

If you are restoring onto a rebuilt virtual machine, attach the Zigbee dongle before you start, as described in [home_assistant_vm.md](home_assistant_vm.md). A restored Zigbee2MQTT config points at a serial device path, and if that device is not there the add-on fails to start and it looks like the restore went wrong when it did not.

---

### What to check afterwards

Open Settings, then Devices and Services, and confirm the integrations came back.

Open Settings, then Add-ons, and confirm Zigbee2MQTT and the broker are running rather than merely installed.

Look at a Zigbee device that reports frequently, a temperature sensor or a power plug, and confirm the value updates. Entities can exist and still be stale if the broker chain has not reconnected.

Confirm the machine has the address you expect, since a restored Home Assistant with a new address breaks everything pointing at it, including the dashboard tiles in [homepage_dashboard.md](homepage_dashboard.md) and the checks in [uptime_kuma.md](uptime_kuma.md).
