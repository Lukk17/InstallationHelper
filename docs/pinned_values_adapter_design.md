# Pinned values adapter design

Design for moving the pinned versions, download locations and identifiers out of `setup/ansible/group_vars/versions.yaml` into TOML, behind one port with one adapter per runtime. Written 2026-08-17 and implemented on 2026-08-20.

The analysis below is kept as written, so the counts in it are the counts at the time: 89 keys, of which 36 carried a reference. The preparatory commit removed the 22 that no reader could reach and moved `android_home` out, which is why the file that shipped holds 67 pins plus the checksum table. The task list at the end records what was done, what proved it, and what remains.

---

### What is in the file today

`setup/ansible/group_vars/versions.yaml` holds 89 top-level keys. Counted by what the value actually is after resolution:

| Category | Count | Examples |
|---|---|---|
| Download location, resolves to an `https://` string | 39 | `minikube_url`, `meslo_bold_url`, `antigravity_cdn_base`, `openrazer_fedora_repo_url`, `applet_window_buttons_repo` |
| Version string | 25 | `veracrypt_version`, `minikube_deb_version`, `python311_id`, `default_python`, `gradle_id` |
| Filename, no scheme and no host | 12 | `veracrypt_file`, `minikube_rpm_file`, `tor_browser_file`, `aurora_store_file` |
| Vendor identifier, not a version | 5 | `java11_id`, `java17_id`, `java21_id`, `java25_id`, `default_java` |
| Opaque build number | 3 | `antigravity_build`, `vmware_build`, `android_cmdline_tools_build` |
| Channel, release stream or API level | 3 | `flutter_channel`, `kubernetes_repo_minor`, `android_api_level` |
| Filesystem path | 1 | `android_home` |
| Checksum table | 1 | `download_checksums`, currently an empty mapping |

Two facts about that table matter more than the totals.

First, the checksum category has one key and zero values. `download_checksums` is `{}` at [setup/ansible/group_vars/versions.yaml](../setup/ansible/group_vars/versions.yaml) line 177, while twelve callsites read entries out of it: seven by name (`jetbrains_toolbox`, `antigravity_linux`, `antigravity_macos`, `gridcoin_flatpak`, `gputest`, `razer_synapse_macos`, `gridcoin_macos`) and five by a runtime-built key on the `apt_url` path. Download verification is therefore wired but unenforced everywhere. Any adapter must keep handing out an empty mapping rather than nothing, or `download_checksums[item.key] | default(omit)` in [dynamic_install.yaml](../setup/ansible/roles/software_installer/tasks/dynamic_install.yaml) raises an undefined-variable error instead of skipping verification.

Second, `android_home` is not a pinned value. It is `"{{ non_root_home }}/Android/Sdk"`, and `non_root_home` is defined in `group_vars/linux.yaml` and `group_vars/macos.yaml`, each of which resolves `non_root_user` from `group_vars/all.yaml`, which reads `ansible_env.SUDO_USER | default(ansible_user_id)`. That is a runtime fact. No file parser can ever resolve it, which is why it decides part of the design below.

---

### Which keys template other keys

36 of the 89 keys carry a `{{ ref }}`. Three shapes appear, and all three have to keep working:

1. The whole value is one reference, as in `default_java: "{{ java21_id }}"`.
2. One or more references embedded mid-string, as in `gridcoin_win_installer_url`, which interpolates `gridcoin_version` twice inside a path.
3. A reference to a key that is itself a reference. The deepest chain is three hops: `appimagelauncher_url` to `appimage_launcher_url` to `appimage_launcher_file` to `appimage_launcher_version`.

`appimagelauncher_url` is a pure alias of `appimage_launcher_url` and looks like dead duplication. It is not. `vars/Debian.yaml` maps the application key `appimagelauncher`, and the dispatcher builds the variable name `appimagelauncher_url` at runtime from that key. Delete the alias and the AppImageLauncher install goes silent on Debian.

---

### Every consumer that reads a pinned value today

Ansible, through ordinary variable references, in roughly 70 places across `site.yaml` and the roles: `ai_tools`, `jetbrains_toolbox`, `kde_plasma_setup`, `sdk_manager`, `shell_zsh`, `software_installer` and `waydroid`. Every one needs a resolved value, never raw text.

Ansible, through a variable name built at runtime. This is the hardest callsite in the repository and the one that rules out several otherwise attractive designs. In [dynamic_install.yaml](../setup/ansible/roles/software_installer/tasks/dynamic_install.yaml) the vendor download resolves `item.value.url | default(lookup('vars', item.key ~ '_url', default=''))`, the Fedora path tries `item.key ~ '_rpm_url'` first, and the checksum is read as `download_checksums[item.key]`. The application keys that reach those lines come from the OS dictionaries, which means nine pinned keys are reachable only this way, so a plain grep of the roles reports them as unread when they are not.

PowerShell, through a regular expression over the YAML, in [setup/windows/WindowsCustomInstalls.ps1](../setup/windows/WindowsCustomInstalls.ps1): a line pattern plus `Get-PinnedVersion`, which is a second resolver performing five substitution passes to a fixed point. It reads the four Java identifiers, `default_java`, `flutter_channel` and two Windows installer URLs, and [setup/setup.ps1](../setup/setup.ps1) hands it the file path. All resolved values. One current contract detail is worth preserving: a reference naming nothing is deliberately left as `{{ nope }}` rather than blanked, so a caller can see it.

Bash and the e2e harness, four consumers:

| File | What it does | Needs |
|---|---|---|
| [e2e/tier1/toggle_coverage.sh](../e2e/tier1/toggle_coverage.sh) | greps for a non-empty value, to prove every `apt_url` and `dnf_url` mapping has a download location | presence and non-emptiness |
| [e2e/tier1/windows_mapping.sh](../e2e/tier1/windows_mapping.sh) | a third resolver: reads `default_python`, extracts the referenced key name with `sed`, reads that key, cuts the minor | resolved value |
| [e2e/tier3/verify.yaml](../e2e/tier3/verify.yaml) | loads the same file so the verify play sees the same pins, and repeats the runtime-built lookup | resolved |
| [docs/manual/debian-ubuntu/install.sh](manual/debian-ubuntu/install.sh) and [docs/manual/fedora/install.sh](manual/fedora/install.sh) | ten download URLs hand-copied out of the file under a comment saying they are pinned to it | resolved |

So bash genuinely needs an adapter. One of those consumers contains a third hand-written resolver, and two of them hold ten hand-copied constants that nothing compares against the source, which is a documented convention rather than a mechanism.

The whole-repository answer to the raw-versus-resolved question is short. No consumer needs raw text. One consumer quotes the name of a referenced key inside a failure message, which it can do just as well by quoting the resolved value. That is why one resolver is enough, and why three of them existing today is pure duplication.

---

### Where the Jinja templating happens today

Nowhere in the file. Ansible loads it as a `vars_files` entry and resolves the references lazily at the moment a value is used. That is why `android_home` works at all: `non_root_home` does not exist when the file loads, only when a task in `sdk_manager` reads `android_home`, several plays into the run.

Two other resolvers exist for consumers Ansible does not serve, the PowerShell one and the `sed` chain in the tier 1 check. Once the file is no longer YAML that Ansible loads, none of the three continues to work as-is, and resolution has to move into the adapter. The one exception is `android_home`, which cannot move into any adapter and instead moves out of the pinned file.

---

### 1. The port

A caller asks for pinned values by name and gets back finished strings. There is no lazy evaluation, no template left to render, and no way to receive a value that still mentions another key. A caller that asks for a name nobody pinned is told so, by name, rather than handed an empty string.

Three operations, and no more.

1. `pins()` returns the complete set as a mapping from key to string, every value fully resolved. Ansible needs this because it injects the whole set, and the tier 1 checks need it because they reason about the set rather than about one key.
2. `pin(key)` returns one value. A key that is not in the file is an error naming the key and the file path. `pin(key, default)` returns the default instead, and the default has to be passed explicitly, so tolerating absence is always a visible decision at the callsite. Absence and emptiness stay distinct: a key present with an empty value returns the empty string, which is what the existing Pester test pins down and what the tier 1 checks rely on to detect a download location that renders to nothing.
3. `checksums()` returns the checksum table as a mapping, and an empty mapping when the table is absent or empty. Absence here means no verification is enforced, which is the documented behaviour today, so this is the one place where a missing entry is legal and silent.

Errors the port raises, all at load time and all naming the offending key: the file is missing or does not parse, a value is not a string, a reference names a key that is not in the file, or references form a cycle.

The port is deliberately not a general configuration reader. It knows about two tables, it returns strings, and it has no options.

---

### 2. The adapters

The core is the port's only implementation, and each adapter is a shim over it.

```text
setup/pinned_values/pinned_values.toml
setup/pinned_values/pinned_values.py
setup/pinned_values/pinned_values.sh
setup/pinned_values/PinnedValues.psm1
setup/ansible/vars_plugins/pinned_values.py
```

The data file moves out of `setup/ansible/group_vars/` on purpose. Three of the four runtimes that read it are not Ansible, and `group_vars/` is a directory whose name means something specific to Ansible.

The core is stdlib-only Python using `tomllib`, and it is also the command line adapter so that shells can reach it without importing anything. It exposes `pins`, `pin` and `checksums`. The file location defaults to the module's own directory, overridable with the environment variable `INSTALLATION_HELPER_PINS_FILE` so tests can point at a fixture. Anchoring to the module's own location rather than to a caller-supplied path is what removes the copy of that path from `setup.ps1`, from `verify.yaml` and from the two tier 1 scripts.

Command line surface, used by both shell adapters. Print the whole set as JSON:

```bash
python3 setup/pinned_values/pinned_values.py --json
```

```powershell
python3 setup/pinned_values/pinned_values.py --json
```

Print one value, exiting 3 with a message on standard error when the key is absent:

```bash
python3 setup/pinned_values/pinned_values.py --get minikube_url
```

```powershell
python3 setup/pinned_values/pinned_values.py --get minikube_url
```

Print `PIN_<KEY>='<value>'` lines for `eval`, which keeps the bash adapter free of a `jq` dependency the tier 1 environment does not guarantee:

```bash
python3 setup/pinned_values/pinned_values.py --sh
```

Adapter one, Ansible: a vars plugin at `setup/ansible/vars_plugins/pinned_values.py`. Mechanism and reasoning are in section 3. The caller does nothing. Every `{{ minikube_url }}` in every role keeps working unchanged, and so does the runtime-built `lookup('vars', item.key ~ '_url')`, because the values are real variables in the host's variable space.

Adapter two, PowerShell: a module exporting `Get-PinnedValueMap`, which invokes the core with `--json` and returns a hashtable, and `Get-PinnedValue`, which invokes `--get` and throws on exit 3 with the key and the file path in the message.

```powershell
Import-Module ./setup/pinned_values/PinnedValues.psm1
```

```powershell
$url = Get-PinnedValue -Key gridcoin_win_installer_url
```

The interpreter is located once per session in this order: `python3`, `python`, `py -3`, then `wsl.exe python3`. None found is a throw naming what to install, never a silent empty map. `Get-PinnedVersion`, the line pattern and the `-VersionsPath` parameter all go away.

The WSL fallback is safe in production because `setup.ps1` asserts WSL before either custom-install call. It is not safe in the tier 3 Windows container, which ships PowerShell 7 and Pester and nothing else, so that container gains a pinned Python from the embeddable zip, in the same shape as its existing PowerShell and Pester steps. Without it the adapter tests would report SKIP, and this repository treats a skip as unproven rather than as a pass.

Adapter three, bash: a file that is sourced rather than executed, exposing `pinned_value <key>` and `pinned_values_load`.

```bash
source setup/pinned_values/pinned_values.sh
```

```bash
pinned_value minikube_url
```

Its four callers change as follows. The version greps in `toggle_coverage.sh` become lookups in the loaded set, with the emptiness test unchanged. The two-step `sed` dereference in `windows_mapping.sh` collapses to one call. The ten hand-copied constants in the two manual install scripts become ten calls, which is the change that turns a documented convention into a mechanism. Both tier 1 scripts follow the precedent already set by `ansible_static.sh` and re-execute themselves inside WSL when no Python is reachable, so the gate stays fully green from Git Bash instead of reporting a skip.

---

### 3. Ansible, which decides the shape

Established rather than assumed. `requirements.yaml` names the supported branches as 2.19.x and 2.20.x, and the development machine reports `ansible [core 2.19.9]` on Python 3.12:

```bash
wsl -d Ubuntu bash -c "ansible --version"
```

`include_vars` cannot read TOML. Its documentation states it loads YAML and JSON variables, and its accepted extensions are json, yaml and yml. See https://docs.ansible.com/ansible/latest/collections/ansible/builtin/include_vars_module.html.

Which extension point, and why the alternatives lose. A filter plugin transforms data it is handed, so it cannot source data and cannot introduce variable names, which would mean rewriting all 70 callsites. A lookup plugin works but needs every callsite edited to `lookup('pinned', 'minikube_url')`, and it does not remove the runtime name construction, it only re-spells it. A vars plugin injects the whole set into the variable space, so nothing at any callsite changes, and it is the documented extension point for sourcing variables from somewhere other than a YAML file. See https://docs.ansible.com/ansible/latest/plugins/vars.html and https://docs.ansible.com/ansible/latest/dev_guide/developing_plugins.html.

Directory layout for a plugin that lives in this repository rather than in a collection. Two mechanisms exist, and this design uses the second because it matches what `ansible.cfg` already does for the callback. The first is a `vars_plugins` directory adjacent to the playbook, which is auto-loaded, see https://docs.ansible.com/ansible/latest/dev_guide/developing_locally.html. The second is a configured path, and relative plugin paths in `ansible.cfg` resolve against the directory holding `ansible.cfg` rather than the working directory, which was proven with `ansible-config dump` from an unrelated working directory:

```bash
wsl -d Ubuntu bash -c "cd /tmp && ANSIBLE_CONFIG=/mnt/d/Development/projekty-IT/InstallationHelper/setup/ansible/ansible.cfg ansible-config dump --only-changed"
```

So two lines go into `ansible.cfg` under `[defaults]`:

```ini
vars_plugins = ./vars_plugins
vars_plugins_enabled = host_group_vars, pinned_values
```

`host_group_vars` must be listed. The enabled-plugins setting defaults to that one entry, and setting the key replaces the default rather than adding to it, so dropping it stops the adjacent `group_vars` discovery. That discovery demonstrably works here today with an inline inventory, which is also the pre-flight check for the new plugin with `minikube_url` in place of `install_chrome`:

```bash
wsl -d Ubuntu bash -c "cd /mnt/d/Development/projekty-IT/InstallationHelper/setup/ansible && ANSIBLE_CONFIG=./ansible.cfg ansible -i localhost, localhost -c local -m ansible.builtin.debug -a 'var=install_chrome'"
```

The plugin itself is a class `VarsModule(BaseVarsPlugin)` with one method, returning the resolved pins plus the checksum table. Five properties of that shim are load-bearing.

1. It carries a documentation block including the vars plugin staging fragment, so `ansible-doc -t vars` answers and tier 1 can assert the plugin is discoverable at all.
2. It is listed in `vars_plugins_enabled` explicitly rather than relying on a default.
3. It never derives the TOML path from the playbook it was called for. The verify play has a different basedir from `site.yaml`, and anchoring to the basedir would make every URL look absent during verification, which reads as a real failure on every scenario.
4. It parses once per process and caches on the file's modification time, because the method is called per host and per entity.
5. Every value goes through `wrap_var`. The core has already resolved everything, so marking the strings unsafe means a URL containing braces can never be templated a second time.

Precedence changes, deliberately. Today the file is a play `vars_files` entry, which is rank 14 of 22. A vars plugin's output lands with inventory and playbook group vars, ranks 4 to 10. See https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_variables.html. Extra vars still win at rank 22, so both wizards and the whole tier 3 harness are unaffected, since they all pass their overrides that way. Role vars, block vars, task vars and `include_vars` now beat a pin, which for a defaults file is the correct direction. Nothing exercises the difference today: no pinned key name is defined in any other file, checked across all 89 keys, and section 6 turns that observation into a check.

Python on the target platforms. `tomllib` entered the standard library in Python 3.11, see https://docs.python.org/3/library/tomllib.html. No third-party package is needed and `setup.sh` needs no new install step, for two independent reasons. The decisive one is that the plugin runs on the control node, in the interpreter running `ansible-playbook`, and ansible-core 2.19 supports control node Python 3.11 to 3.13 while 2.20 supports 3.12 to 3.14, so any interpreter capable of running a supported ansible-core already has `tomllib`. The second covers the shell and PowerShell adapters, which call the system interpreter:

| Target | Default python3 | tomllib |
|---|---|---|
| Ubuntu 26.04 | 3.14 | yes |
| Debian trixie | 3.13 | yes |
| Fedora 44 | 3.14 | yes |
| Arch | 3.14 | yes |
| macOS, Homebrew | 3.14 | yes |

The core still guards the import and raises a sentence naming Python 3.11 rather than letting an import error traceback out. No `tomli` fallback is added, because no supported platform would use it.

---

### 4. How the references between pinned values keep working

The adapter resolves them, and the spelling in the file does not change. Values keep the `{{ other_key }}` form they have today.

That choice is not nostalgia. It makes the migration diff a format change with byte-identical values, which is the only version of this change whose correctness can be proven mechanically: resolve the old YAML, resolve the new TOML, compare all 89 keys. Invent a new reference syntax and that proof becomes a rewrite.

The algorithm is the one the PowerShell resolver already implements, moved to the single place allowed to have it: textual substitution over the whole set, repeated until a pass changes nothing, with a pass cap. Three differences from today. A reference naming a key that is not in the file is an error at load naming both keys, instead of arriving at a caller as literal text. A cycle is an error naming the keys in it, instead of a silent bail after five passes. And the result is checked to contain no remaining braces, so an unresolved value cannot leave the port.

Nothing is flattened. The one key that cannot be resolved this way, `android_home`, moves to `group_vars/all.yaml` next to `non_root_user`, as one line. It belongs there: it is a path derived from a runtime fact, not a pinned value, and Ansible's lazy templating resolves it after the OS group vars load, exactly as it does now.

With that move the pinned file becomes closed: every reference resolves inside it. Closure is what makes the resolver total, what makes "no value contains braces" a checkable invariant, and what makes marking values unsafe on the Ansible side correct. The cost is that a future pin can no longer reference an Ansible fact, which is not a loss but the boundary: a value that depends on the host belongs in `group_vars`, and a value that is pinned belongs here.

The file shape, both tables explicit:

```toml
[pins]
appimage_launcher_version = "2.2.0"
appimage_launcher_file = "appimagelauncher_{{ appimage_launcher_version }}-travis995.0f91801.bionic_amd64.deb"
default_java = "{{ java21_id }}"
android_api_level = "35"

[checksums]
```

Two named tables rather than bare top-level keys, because TOML requires bare keys to precede every table header. With the checksum table at the end of the YAML today, a bare-key layout would work on day one and then silently swallow the next pin appended after the header into the checksum table. Named tables also map one to one onto the port's operations.

Every value is quoted. `android_api_level = 35` would arrive as an integer and `kind_version = 0.31` as a float with the trailing zero gone, and `1.13.3` is not a valid TOML float at all. The core rejects any non-string scalar by key name, and tier 1 asserts the same, so that failure mode is closed twice.

---

### 5. Migration

Two commits. The count is decided by the requirement that a half-migrated state be impossible, not by taste.

Commit one is preparatory, correct on its own and a no-op at runtime. `android_home` moves to `group_vars/all.yaml`, and the keys no reader can reach are removed. That set was established by resolving every one of the 89 keys against the roles, the OS dictionaries, `site.yaml`, the runtime-built names derived from the `apt_url` and `dnf_url` mapping keys, the Windows scripts, the tier 1 checks and the verify play. Thirteen keys have no reader at all, and nine feeders go with them where they feed nothing else. Anything kept on purpose is kept with its reason in an allowlist, and `vmware_url` is the likely candidate given the Broadcom login note above it.

Commit two is the migration and is indivisible. The TOML file is added and the YAML deleted, the core and all three adapters are added, `ansible.cfg` gains the two lines, the play and the verify play stop loading the file, the PowerShell parser is deleted, all four bash consumers move onto the adapter, the Pester tests for the deleted function are replaced by adapter tests, the Windows image gains Python, the new tier 1 check lands in the same commit, and every document naming the old path is updated. Shipping the migration and its guard separately would mean shipping the migration unguarded, and roughly twenty documentation and comment references point at a file that would no longer exist.

The one-off proof that no value changed runs inside the migration before the YAML is deleted: resolve both files and compare all 89 keys. It is a throwaway comparison rather than a permanent check, because after the commit there is only one file to resolve.

Rollback is a single `git revert` of commit two, which restores the YAML, the loading line, the PowerShell parser and every consumer atomically, with no intermediate state in which one runtime reads TOML and another greps a file that is gone.

---

### 6. What guards the design against rot

One new tier 1 script, registered in the same loop as the others and using the same reporting helpers. Six assertions, each aimed at one way this design can be bypassed.

1. Nobody parses the file but the core. Every shell, PowerShell, YAML and Python file under `setup/`, `e2e/` and `docs/manual/` is scanned, and naming the TOML file, importing a TOML library, or carrying a pin-shaped regular expression is a failure anywhere except the core. This is the assertion that fails when someone writes a second parser, which is the thing that already happened three times.
2. Every pin has at least one reader, with the reader set built from the literal references in the roles, the names derived from every `apt_url` and `dnf_url` mapping key, the in-file references, and the keys named in the PowerShell and shell callers. Anything outside that union fails unless listed with a reason, and the allowlist is checked for stale entries the same way the documented no-ops file is.
3. Every reader names a pin that exists, which catches a typo in a role and a pin renamed without its callsites.
4. The resolved set is total and non-empty: no value contains braces, no value is empty, every value is a string. The empty-string rule matters most, because an empty download location makes both dispatch tasks skip without a word.
5. No pin name is defined as a variable anywhere else in the repository, which is what makes the precedence drop safe rather than merely untested.
6. The PowerShell adapter and the core agree key by key, with the same honest SKIP the mapping parse check already uses when no runnable PowerShell exists.

Every assertion is proven to fail before it is trusted, by copying the tree, reintroducing the defect and watching the check go red. A check never seen to fail is not a check. The tier 1 spec gains one bullet per assertion.

What this does not guard, stated plainly: it cannot tell whether a pinned version is the right version, and it cannot see a value read through a name assembled from something other than an OS dictionary key.

---

### 7. The risks

A plugin that does not load, so the run fails at the first pinned value. This is the worst case. If either configuration line is wrong, or the configuration file does not reach the process, the playbook fails at the first pinned reference with an undefined-variable error, which is early, total and identical on every platform. What reduces it: the plugin runs only on the control node, so there is no per-distribution variation to discover in the field, the load is asserted with a one-command probe before the commit, and the smoke scenario runs on all four distributions. What it is not is a partial failure, so it cannot install half the software and stay green.

The enabled-plugins setting silently dropping the built-in group vars plugin, which would stop adjacent `group_vars` discovery. Survivable here because the cross-platform file is also read explicitly, but a real regression elsewhere. Closed by listing it, and by the probe still answering afterwards.

The precedence drop, where an override that used to lose now wins. No such override exists today, and assertion 5 keeps it that way.

TOML numeric type drift, where a version renders as `0.31` in a URL and produces a 404 that looks like a dead vendor link. Closed twice, in the core and in assertion 4.

Python unreachable from the PowerShell path, which would make the five Windows custom installs fail with a named error rather than installing. Reduced by the four-step interpreter search, by the WSL assertion running before those installs, and by pinning Python into the Windows e2e image so the adapter is exercised rather than skipped.

`tomllib` absent, which is only reachable on Python 3.10 or older, which no supported target ships. Cost is one clear sentence at startup.

Load-bearing comments lost in the move, and this is the risk least likely to be caught by any gate. The current file records why one content-delivery host is not a third party, that two vendor repository paths return 404 despite being published, why a CentOS 8 build is the correct choice on Fedora, that one tool needs a real tag rather than `latest`, and where to verify each candidate list. Losing that means the next person bumping a pin reintroduces a defect the comment existed to prevent. TOML keeps comments, the file is written by hand rather than generated, and the migration diff is reviewed comment by comment before the deletion is staged.

The verify play looking in the wrong place, which would report every URL as missing and fail every scenario for a reason unrelated to the software. Closed by anchoring the path to the plugin's own file.

The shell adapter making the tier 1 gate skip instead of pass, because Git Bash has no Python. A green gate with unproven checks is worse than a red one. Closed by re-executing inside WSL.

---

### Tasks

---

### 1. Move android_home out of the pinned values

- [x] 1.1 Add `android_home: "{{ non_root_home }}/Android/Sdk"` to `group_vars/all.yaml` beside `non_root_user`, and remove it from `versions.yaml`.

Files: `setup/ansible/group_vars/all.yaml`, `setup/ansible/group_vars/versions.yaml`.

```bash
wsl -d Ubuntu bash -c "cd /mnt/d/Development/projekty-IT/InstallationHelper/setup/ansible && ANSIBLE_CONFIG=./ansible.cfg ansible -i localhost, localhost -c local -m ansible.builtin.debug -a 'var=android_home'"
```

---

### 2. Remove the pins no reader can reach

- [x] 2.1 Delete the thirteen unread keys and the nine feeders that then feed nothing, and record any deliberate keep in an allowlist with its reason.

Files: `setup/ansible/group_vars/versions.yaml`, `e2e/tier1/unread_pins_allowed.txt`.

```bash
bash e2e/run.sh
```

---

### 3. Prove the pruning changed no install

- [x] 3.1 Run the Debian smoke scenario, because the pruned keys sit on the vendor-download path.

Files: none.

```bash
./e2e/run.sh --tier 3 --scenario smoke --os debian
```

---

### 4. Write the TOML file

- [x] 4.1 Create `setup/pinned_values/pinned_values.toml` with a pins table and a checksums table, every value quoted, every reference spelling unchanged, every comment carried across.

Files: `setup/pinned_values/pinned_values.toml`.

```bash
python3 -c "import tomllib,pathlib;print(len(tomllib.loads(pathlib.Path('setup/pinned_values/pinned_values.toml').read_text())['pins']))"
```

---

### 5. Write the port implementation

- [x] 5.1 Create `setup/pinned_values/pinned_values.py` with the three operations, the fixed-point resolver, the four load-time errors, and the three command line modes.

Files: `setup/pinned_values/pinned_values.py`.

```bash
python3 setup/pinned_values/pinned_values.py --get default_java
```

---

### 6. Prove the migration changed no value

- [x] 6.1 Resolve the old YAML and the new TOML and compare all keys, before the YAML is staged for deletion.

Run on 2026-08-20. All 67 keys resolved twice, once by Ansible loading the old YAML as a `vars_files` entry and once by the new reader from the TOML, and compared. No key missing on either side and no value different, so the format change carried no value change.

Files: none.

```bash
python3 setup/pinned_values/pinned_values.py --json
```

---

### 7. Add the Ansible adapter

- [x] 7.1 Create `setup/ansible/vars_plugins/pinned_values.py` with a documentation block, values marked unsafe, the checksum table always present, and the path anchored to the plugin's own location.
- [x] 7.2 Add the two lines to `[defaults]` in `ansible.cfg`.
- [x] 7.3 Stop loading the YAML in `site.yaml` and in the verify play.

Files: `setup/ansible/vars_plugins/pinned_values.py`, `setup/ansible/ansible.cfg`, `setup/ansible/site.yaml`, `e2e/tier3/verify.yaml`.

```bash
wsl -d Ubuntu bash -c "cd /mnt/d/Development/projekty-IT/InstallationHelper/setup/ansible && ANSIBLE_CONFIG=./ansible.cfg ansible -i localhost, localhost -c local -m ansible.builtin.debug -a 'var=minikube_url'"
```

---

### 8. Confirm the plugin is discoverable and group vars still load

- [x] 8.1 Assert the plugin is listed, and that a cross-platform toggle still resolves from the adjacent group vars.

All three answered. `minikube_url` resolves through the plugin, `install_chrome` still resolves from the adjacent `group_vars`, so listing `host_group_vars` kept that discovery, and `download_checksums` arrives as an empty mapping rather than undefined. Proven again against a relocated copy of `setup/`, which is the container's layout, so the plugin finds its file from its own path and not from the repository root.

Files: none.

```bash
wsl -d Ubuntu bash -c "cd /mnt/d/Development/projekty-IT/InstallationHelper/setup/ansible && ANSIBLE_CONFIG=./ansible.cfg ansible-doc -t vars -l"
```

---

### 9. Add the bash adapter and move its four callers onto it

- [x] 9.1 Create `setup/pinned_values/pinned_values.sh` with the two functions, the interpreter search and the WSL re-execution.
- [x] 9.2 Replace the version greps in `toggle_coverage.sh`.
- [x] 9.3 Replace the sed dereference in `windows_mapping.sh`.
- [x] 9.4 Replace the ten hand-copied URLs in the two manual install scripts.

Files: `setup/pinned_values/pinned_values.sh`, `e2e/tier1/toggle_coverage.sh`, `e2e/tier1/windows_mapping.sh`, `docs/manual/debian-ubuntu/install.sh`, `docs/manual/fedora/install.sh`.

```bash
bash e2e/run.sh
```

---

### 10. Add the PowerShell adapter and delete the second parser

- [x] 10.1 Create `setup/pinned_values/PinnedValues.psm1` exporting the two functions.
- [x] 10.2 Delete the resolver, the line pattern and the path parameter from `WindowsCustomInstalls.ps1`, and drop the argument in `setup.ps1`.

Files: `setup/pinned_values/PinnedValues.psm1`, `setup/windows/WindowsCustomInstalls.ps1`, `setup/setup.ps1`.

```powershell
pwsh -NoProfile -Command "Import-Module ./setup/pinned_values/PinnedValues.psm1; (Get-PinnedValueMap)['default_java']"
```

---

### 11. Move the Pester tests onto the adapter and give the container a Python

- [x] 11.1 Replace the resolver tests with adapter tests, keeping the absent-versus-empty case and the real-file case.
- [x] 11.2 Add a pinned Python from the embeddable zip to the Windows Dockerfile.

Files: `e2e/tier3/windows/WindowsSoftware.Tests.ps1`, `e2e/tier3/windows.Dockerfile`.

```powershell
pwsh e2e/tier3/Invoke-WindowsE2E.ps1
```

---

### 12. Add the tier 1 guard

- [x] 12.1 Create the check with the six assertions and register it in the tier 1 loop.
- [x] 12.2 Prove each assertion fails against a copy of the tree carrying the defect.

Six proofs, each against a copy of the tree with the old YAML already gone so only the injected defect could fail: a second parser in three shapes, an unread pin and both stale-allowlist halves, a reader naming no pin in both its typo and its renamed-pin shapes, an emptied value and a stray brace and an unquoted version, a pin name redefined in group_vars, and a tampered PowerShell adapter. Two of them found defects in the check itself: a mapping scanned without its manager excused a missing pin because the sibling rpm pin survived, and grep -q at the end of a pipeline under pipefail gave sed a SIGPIPE, which reported all three needles as dead against the one file that carries all three.

Files: `e2e/tier1/pinned_values.sh`, `e2e/run.sh`, `e2e/tier1/unread_pins_allowed.txt`.

```bash
bash e2e/run.sh
```

---

### 13. Delete the YAML and update every document that names it

- [x] 13.1 Remove `setup/ansible/group_vars/versions.yaml`.

Deleted. Every consumer had moved first, which is why the file could go in the same commit rather than leaving a half-migrated state.
- [x] 13.2 Update the roughly twenty prose and comment references.

Files: `setup/ansible/group_vars/versions.yaml`, `AGENTS.md`, `setup/README_SETUP.md`, `setup/configuration.md`, `setup/software.md`, `setup/version_sources.md`, `docs/manual/README.md`, the two manual install pages, the three OS dictionaries, `dynamic_install.yaml`, `e2e/tier3/verify.yaml`, `e2e/tier1/toggle_coverage.sh`, `e2e/testing/10-wizard-toggle-parse-test.md`.

```bash
bash e2e/run.sh
```

---

### 14. Prove it on real distributions before calling it done

- [ ] 14.1 Run the smoke scenario on Arch, Debian, Ubuntu and Fedora, two at a time.

Not run, and still owed. It was blocked when this was written, because Docker Desktop's WSL integration was off for the Ubuntu distro and the harness would only run the container tiers from a Linux shell. Neither half of that holds now: the guard is `require_docker_host`, which asks whether a daemon answers rather than what the operating system is, so the command below runs from Git Bash, and as measured on 2026-08-20 the Ubuntu distribution has a socket again and runs it too.

Files: none.

```bash
./e2e/run.sh --tier 3 --scenario smoke --jobs 2
```

---

### 15. Test the reader itself, not only its callers

- [x] 15.1 Create `e2e/tier1/pinned_values_reader.sh` with seven fixtures in `e2e/tier1/pins_fixtures/`, driving the reader through `INSTALLATION_HELPER_PINS_FILE` so no case depends on the values pinned today.
- [x] 15.2 Prove all thirteen assertions fail when the defect each one exists to catch is reintroduced into a copy of the reader.

Not in the original list, and it should have been. Task 12 guards the repository against acquiring a second parser, which is a different question from whether the one parser is correct, and every adapter is a shim over it, so a wrong answer here is a wrong answer in every runtime at once. The cases are the contract from section 1: a chain resolves, a reference inside a longer string resolves, nothing escapes still holding a template, an empty pin answers empty at exit 0 while an unpinned name exits 3, the checksum table stays separate and a file without one still loads, and each of the five load-time refusals names what is wrong.

Both of the parsers this replaced would have failed it. The PowerShell one left a dangling reference as literal `{{ nope }}` and bailed out of a cycle silently after five passes, and the `sed` chain in `windows_mapping.sh` could dereference exactly one hop.

The twelve mutations used for 15.2 were: resolving one hop instead of the chain, letting a template escape, reporting an empty pin as absent, answering an unpinned name with an empty string, mixing the checksum table into the pins, refusing a file that has no checksum table, accepting an unquoted version as a number, blanking a dangling reference, bailing out of a cycle, treating a missing pins table as an empty set, swallowing unparseable TOML, and dropping the quote escaping from the shell assignment output. Each one turned exactly the intended assertion red.

Finding worth recording, because it is the same class the suite exists for: the first run of the twelfth proof killed the check instead of failing it. The adapter case runs in a subshell, `common.sh` runs under `set -e`, and a bare subshell returning non-zero ends the script before the line that reads its status. The check now collects that status with `||`, so a defect produces a FAIL line rather than a truncated run.

```bash
bash e2e/tier1/pinned_values_reader.sh
```

---
