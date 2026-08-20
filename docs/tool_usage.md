# Using what the playbook installed

The catalogue in [setup/software.md](../setup/software.md) says what gets installed and how. This page
says what to do with the ones that are not obvious: the tools you would otherwise install, never run,
and forget you have.

One section per tool, and nothing here changes a machine unless it says so.

---

### Lynis, a security audit of the machine you are on

Installed on every Linux family and on macOS. It reads the machine, scores it, and tells you what to
do about it. Nothing is changed, so it is safe on a working laptop, and running it after the playbook
is how you find out whether the playbook improved anything.

The full audit:

```bash
sudo lynis audit system
```

```powershell
wsl -d Ubuntu bash -c "sudo lynis audit system"
```

It walks roughly 300 tests across accounts, SSH, the kernel, file permissions, firewalls, malware
scanning, logging and package hygiene. Each finding prints as a warning or a suggestion with a test
code beside it, and the run ends with a hardening index out of 100.

Treat the index as a comparison against your own previous run rather than as a target. What matters
is whether it moves. A machine scoring 100 has usually been configured for the score rather than for
the person using it.

Without `sudo` it still runs and silently cannot see the things that need root, which is the usual
reason two runs on the same machine disagree.

Reading one finding properly, where TEST-ID is the code printed beside it:

```bash
lynis show details TEST-ID
```

The full report of the last run, which is longer than what the terminal showed:

```bash
sudo cat /var/log/lynis-report.dat
```

Two habits worth having. Run it once before you change anything, so the first number is a baseline
rather than a verdict. And treat every suggestion as a question: Lynis does not know which of its
findings matter on a personal machine.

---

### Verifying what actually installed

Not a tool you installed, but the thing people look for after a run. The wizard verifies by itself as
its last step, so a normal install needs none of this. To ask again later, on a machine the playbook
touched weeks ago:

```bash
ANSIBLE_CONFIG=setup/ansible/ansible.cfg ansible-playbook -i localhost, -c local -K setup/ansible/verify_install.yaml
```

```powershell
wsl -d Ubuntu bash -c "cd /mnt/d/Development/projekty-IT/InstallationHelper && ANSIBLE_CONFIG=setup/ansible/ansible.cfg ansible-playbook -i 'localhost,' -c local -K setup/ansible/verify_install.yaml"
```

It changes nothing, it reports every application it was asked about, and it exits non-zero when
something requested is missing. The header of that file explains the flags and why `ANSIBLE_CONFIG`
is not optional.
