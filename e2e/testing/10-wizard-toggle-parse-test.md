# wizard-toggle-parse: e2e test

Tier 1 of the harness, the pre-commit gate. Seconds, no container, nothing installed.

Section headings sit at level two because the `e2e-runbooks` test-spec template fixes the seven section names at that level, which overrides this repository's level-three heading rule.

The capability is named after the wizard parse check because that is the defect the tier was built around, but the gate command runs every tier 1 check and cannot run one alone. All of them are covered below.

---

## What this verifies

- Both wizards read the same toggles out of the same YAML. For each of `group_vars/all.yaml`, `linux.yaml`, `macos.yaml` and `windows.yaml`, the key and state set that `read_boolean_toggles` in [../../setup/setup.sh](../../setup/setup.sh) emits equals an independent parse of the file, and the key set that [../../setup/setup.ps1](../../setup/setup.ps1) matches equals the key set bash emits. This exists for the "Wizard toggle parse desync" entry in [../../docs/regression_ledger.md](../../docs/regression_ledger.md): an end-anchored state substitution let any toggle carrying a trailing comment reach the caller unconverted, so 11 toggles on Linux and 4 on macOS rendered unchecked with a stray colon in the label and could not be controlled in either direction, while the PowerShell wizard was never affected.
- No toggle is dropped or malformed on the way from the YAML to the wizard. Every emitted line has the shape `<key> ON|OFF`, no emitted key carries a colon, and the emitted count matches the independent count. The desync entry above produced the variable name `install_tailscale:=false`, which Ansible accepts silently and which leaves the real toggle untouched.
- Every enabled toggle resolves to something that installs it, per OS family. For Debian, RedHat, Archlinux, Darwin and Windows, each toggle whose effective value is true either has a `software_mapping` entry in `vars/<family>.yaml`, or is referenced as `install_<key>` by a role task file or by `site.yaml` with comments stripped, or is listed for that family in [../tier1/documented_no_ops.txt](../tier1/documented_no_ops.txt). This exists for the "Toggles enabled with no mapping and no task" entry in the ledger, where `install_putty` had no mapping on Arch or Fedora and `install_gradle` had none on Debian or Fedora behind a comment claiming SDKMAN handled it, and for the "Toggles that had already been dead for a while" entry, where four toggles appeared ticked in the wizard with no working install path on any operating system.
- The documented no-op list stays honest. No line in it forgives a toggle that has since gained a real mapping, because a stale entry makes a later break in that mapping look intentional.
- The four Windows system settings resolve too, which `install_` coverage cannot see. Every key [../../setup/windows/WindowsSettings.ps1](../../setup/windows/WindowsSettings.ps1) claims is a real boolean toggle in the `group_vars` pair the Windows wizard reads, every system-setting toggle that wizard shows is claimed by that file, every claimed key is applied by its dispatch, and the nine optional features it enables are the ones [../../setup/ansible/roles/windows_core/tasks/windows_features.yaml](../../setup/ansible/roles/windows_core/tasks/windows_features.yaml) loops over, in the same order. Those two lists are the same two-lists shape as the wizard desync above, and the coverage half is the non-install remainder of the "Toggles enabled with no mapping and no task" entry: a system setting has no `vars/Windows.yaml` mapping it could ever resolve to, so its only possible consumer is that file.
- The verification only looks, and something actually runs it. [../../setup/ansible/verify_install.yaml](../../setup/ansible/verify_install.yaml) uses no module that can change the machine and marks every `command` and `shell` read `changed_when: false`, [../tier3/verify.yaml](../tier3/verify.yaml) imports that play instead of holding a second copy of its assertions, and [../../setup/setup.sh](../../setup/setup.sh) ends both of its run paths in the verification, hands it the same selection it handed the playbook, and runs it under a stdout callback that cannot truncate the run's own logs. This is the "toggle nothing consumes" shape from the ledger applied to a whole step: a verification the wizard forgets to run, or one that resolves the selection a second time and demands the applications the user unticked, reports on a machine nobody asked about.
- The playbook parses, and parses quietly. `site.yaml` and [../tier3/verify.yaml](../tier3/verify.yaml) both pass a syntax check, the syntax check emits at most two warnings, and no repository file is reported as an inventory source. This exists for the ledger entry on `ansible.cfg` setting `inventory = localhost,`, where the empty entry after the comma resolved to the config directory, Ansible walked all of `setup/ansible/` as an inventory source, and 212 warnings printed on every invocation without an explicit `-i`. A real warning cannot be seen in that.

---

## Prerequisites

Confirm the shell is Linux. On Windows this means running from inside WSL, which is also the only place Ansible runs at all.

```bash
uname -s
```

Expect `Linux`. Anything else and the harness refuses tiers 2 and 3 outright, and the tier 1 scripts depend on GNU tool behaviour that Git Bash does not reliably provide.

Confirm `ansible-playbook` is on PATH.

```bash
command -v ansible-playbook
```

Expect a path. Without it the static check exits 2 before running any assertion.

Confirm GNU grep, because the cross-wizard comparison uses a Perl-mode pattern to pull the toggle regex out of the PowerShell wizard.

```bash
grep -V
```

Expect the first line to name GNU grep. With a grep that lacks `-P`, the cross-wizard comparison is skipped with a warning rather than failed, so the run would pass while covering less than it claims.

Confirm the working tree holds exactly the change you intend to test.

```bash
git status --short setup e2e
```

Expect only your own edits. Tier 1 asserts against the working tree, not against a commit, so an unrelated half-finished edit under [../../setup/](../../setup/) becomes part of the input.

Note whether yamllint is installed, because it changes the assertion set.

```bash
command -v yamllint
```

Either answer is acceptable. When it is present, a yamllint finding under `setup/ansible/` is a failure. When it is absent, that assertion is skipped with a warning and the run covers less.

---

## Reset state

None. This test writes no persisted state. It reads the working tree, extracts two functions out of `setup.sh` and evaluates them inside its own shell rather than launching the interactive wizard, and starts no container.

One side effect worth knowing: `ansible-playbook --syntax-check` writes into `~/.ansible/tmp` and the fact cache under `~/.ansible/`, because [../../setup/ansible/ansible.cfg](../../setup/ansible/ansible.cfg) moves those paths out of `/tmp`. Nothing in the repository is touched.

---

## Run

Run the gate from the repository root. With no arguments it is tier 1 only.

```bash
./e2e/run.sh
```

From a PowerShell prompt on Windows, the same run inside WSL.

```powershell
wsl -d Ubuntu bash -c "cd /mnt/d/Development/projekty-IT/InstallationHelper && ./e2e/run.sh"
```

Wait for the process to exit. It runs the checks in order and does not stop at the first failure, so the whole output is meaningful even when something fails early.

---

## Expected

The process exits 0. A non-zero exit means at least one check failed, and the harness prints the failing check names under a per-script tally line. Each script reports its own tally with the shape `<label>: N checks, all passed`, so a script that fails still tells you how many assertions ran.

Eleven check scripts run, in this order, and the list below is the whole of tier 1. Each is named by its script so [../tier1/verify_spec_parity.sh](../tier1/verify_spec_parity.sh) can read `run_tier1`'s own loop and prove this section is complete. Per-script assertion counts are deliberately not stated, because they grow as checks are added and a stale number here would be worse than none.

1. `wizard_parse` reports five passes for each of `all.yaml`, `linux.yaml`, `macos.yaml` and `windows.yaml`: the bash parse matches the YAML with a toggle count, every emitted line has the shape `<key> ON|OFF`, no key carries a stray colon, no toggle is dropped between the YAML and the wizard, and the two wizards see the same toggle keys. A mismatch prints a truncated diff of the two key sets rather than a log excerpt. Two further passes cover the whole set rather than one file: every visible system setting has a descriptive label, and both wizards hide the same toggles.
2. `toggle_coverage` reports one pass per OS family, `Debian`, `RedHat`, `Archlinux`, `Darwin` and `Windows`, each stating how many enabled toggles resolved. A failure names the unresolved toggles. One further pass states that the documented no-op list has no stale entries, and a failure names each family and toggle pair that is forgiven while a real mapping now exists. Windows is judged differently from the other four: a Windows-gated Ansible task cannot run, so only the three native installers count as coverage there. Four more passes cover the `apt_url` and `dnf_url` mappings, two per family: that every one has a download location, meaning an inline `url:` field or a non-empty `<key>_url` in `group_vars/versions.yaml`, and `<key>_rpm_url` as well on Fedora, and that every one names the package the way dpkg or rpm will report it rather than holding a filename or a URL. Both dispatch tasks skip silently when the location renders empty, and the verify play looks the installed package up by that name, so a filename there means the check can never pass.
3. `windows_mapping` reports that every mapping-shaped line in `vars/Windows.yaml` parses in bash, that the PowerShell installer parses the same number of mappings, that the two agree on every mapping including manager and source, that every mapping has a toggle to select it, and that the Windows Python mapping still matches `default_python`. The PowerShell half needs a runnable `pwsh`, which on this machine means running the gate from Git Bash rather than WSL, and it reports SKIP rather than passing quietly when it cannot. Locating that `pwsh` and converting a path for it live in [../tier1/pwsh_probe.sh](../tier1/pwsh_probe.sh), shared with the next-but-one check, because the probe has to reject the Microsoft Store alias stub and a second hand-written copy of that would be the one that rots.
4. `windows_npm_parity` reports that the native npm tool list and the `ai_tools` role it replaces name the same packages, and that every one has an install toggle.
5. `windows_settings` reports that [../../setup/windows/WindowsSettings.ps1](../../setup/windows/WindowsSettings.ps1) still exports both of the lists this check asks it for, that those nine optional feature names equal `windows_core/tasks/windows_features.yaml`'s loop in the same order, that all four setting keys are boolean toggles in the `group_vars` pair the Windows wizard reads, that the visible non-`install_` toggle set in that pair is exactly those four keys, and that each one is applied by `Invoke-WindowsSystemSetting`. The two lists are asked of the file through `Get-WindowsOptionalFeatureName` and `Get-WindowsSettingKey`, so the check sees what the applier sees rather than a parse of the dispatch, and it reports SKIP without a runnable `pwsh` the way `windows_mapping` does. The accessor assertion is the one deliberately written in bash, so a SKIP cannot hide their deletion. It also carries the non-`install_` half of Windows toggle coverage, which `toggle_coverage` cannot reach: a system setting has no `vars/Windows.yaml` mapping and no runnable task, so this file is its only possible consumer, and the set comparison closes the gap in both directions instead of teaching `toggle_coverage` a second Windows special case. The `group_vars` pair is `all.yaml` overlaid by `windows.yaml`, because `set_custom_wallpaper` is cross-platform and lives in `all.yaml` while the other three are Windows-only.
6. `verify_spec_parity` reports that every assertion in the verification play, [../../setup/ansible/verify_install.yaml](../../setup/ansible/verify_install.yaml), is named in each of the six container capability specs, and that this spec names every tier 1 check script. It reads the play rather than [../tier3/verify.yaml](../tier3/verify.yaml) because the play is where the assertions live: the tier 3 file is a wrapper that imports it, so a container run and a real machine assert the same eleven things. It is the check that keeps this document honest, and it fails when a spec understates what its run proves.
7. `verify_wiring` reports that the verification play uses no state-changing module, that every one of its `command` and `shell` reads is marked `changed_when: false`, that [../tier3/verify.yaml](../tier3/verify.yaml) imports the play instead of carrying assertions of its own, that both of the wizard's run paths end in `finish_run` and therefore verify, that the verification is handed the same selection as the playbook by slicing it off `PLAYBOOK_ARGS` rather than resolving it a second time, and that it runs under the stock stdout callback. Each guards a defect with a known shape. A play that installs something is no longer a diagnostic, and a person is told to run this one on a working laptop. A verification wired into only one entrypoint leaves the scripted install, the one nobody watches, reporting success without ever asking the machine. A second resolution of the selection drifts from the first, and the drift demands every application the user unticked and reports it missing. And `dual_logger` opens the four `installation_*.log` files with mode `w`, so verifying a run under it would erase that run's own log.
8. `failed_key_reads` reports that nothing in the playbook, the task files it imports, the profile overlays, its roles or the verify play decides anything from a result's `failed` key. It exists for one defect that cost a day: a collector selecting on `failed == true` could never match, because the task that registered the result carried `failed_when: false` and Ansible applies `failed_when` by rewriting that very key. Three AUR builds that exited rc 1 were counted as successes. `rc` and `finished` survive `failed_when` untouched and are what to read instead. Five shapes are matched: `selectattr` or `rejectattr` on the key, `attribute="failed"`, dotted access on a word boundary, bracket access, and the Jinja tests `is failed` and `is not failed` with their `failure` alias. The word boundary is what catches `when: r.failed` and `failed_when: r.failed == true`, the two shortest ways to write the forbidden thing, both of which an earlier version of the pattern passed because it required a pipe or a closing brace straight after the key. `until: <result> is succeeded` is deliberately not matched, because forty tasks use it as their retry condition and a forty-line allowlist forgives by default rather than by decision. Exceptions live in [../tier1/failed_key_reads_allowed.txt](../tier1/failed_key_reads_allowed.txt), currently empty.
9. `tolerated_failures_read` reports how many tasks tolerate failure and how many of those register a result, that every registered result is read somewhere other than its own register line, and that the allowlist has no stale entries. It exists for the second half of the same defect the check above guards: a task tolerates failure, registers a result, and nothing downstream reads it, so the tolerance is real and the reporting is imaginary. A registered variable nobody uses is legal Ansible, so nothing warns. The scan also refuses to report on fewer than ten tolerated tasks, because a block-splitting pattern that stops matching would otherwise pass every assertion. Exceptions live in [../tier1/tolerated_failures_allowed.txt](../tier1/tolerated_failures_allowed.txt), currently empty, because the one candidate was a diagnostic whose register was simply dead and was removed instead.
10. `os_family_derivation` reports that the playbook branches on the derived family rather than on Ansible's own answer, and that the derivation resolves every distribution this repository claims to support. It exists because Ansible maps a distribution to a family through one fixed table in `ansible/module_utils/facts/system/distribution.py` and falls back to the distribution's own name for anything absent from it, so on a derivative such as Nobara every `os_family == '...'` condition here was false, no `vars/<family>.yaml` matched, and the run stopped having installed nothing. Eight passes: that [../../setup/ansible/tasks/derive_os_facts.yaml](../../setup/ansible/tasks/derive_os_facts.yaml) still reads `/etc/os-release` and still sets both `ih_family` and `ih_base`, which is what stops the exemption below from becoming vacuous; that `site.yaml` imports it before the OS dictionary named after it is loaded, with both line numbers in the message; that no task file under `setup/ansible` reads `ansible_facts['os_family']` or the raw distribution name; that no entry in [../tier1/os_family_reads_allowed.txt](../tier1/os_family_reads_allowed.txt) has gone stale, each entry forgiving one exact line rather than a whole file; that every os-release fixture is named by a case and every case has a fixture; and three from a real Ansible run of the shipped derivation against those fixtures, that it asserted one case per fixture, that every fixture derives the expected pair with openSUSE rejected rather than silently treated as RedHat, and that the machine running the gate resolves to a supported family. The play carries one case with no fixture, because the absence of the file is its input: a path that does not exist, standing in for macOS and Windows, where both facts must still come out defined or every later task that reads them fails. Like `ansible_static`, it re-executes itself inside WSL when `ansible-playbook` is not on the local PATH, through the helper both of them share, [../tier1/wsl_delegate.sh](../tier1/wsl_delegate.sh).
11. `ansible_static` reports that `site.yaml` parses, that the syntax check emitted at most two warnings with the actual count in the message, that no repository file is mistaken for an inventory source, and that `verify.yaml` parses. The two expected warnings are correct: no inventory was passed, so only the implicit localhost exists and it does not match `all`. When `ansible-playbook` is not on the local PATH, which is the case in Git Bash on Windows, this script re-executes itself inside WSL rather than aborting the gate.

Optional linters behave asymmetrically on purpose. A yamllint finding fails the gate when yamllint is installed. An ansible-lint finding is printed and never fails. When either tool is missing, the run says so and skips it.

Container limitations do not apply to this capability. No container starts, so nothing in [../tier3/container_limits.yaml](../tier3/container_limits.yaml) is suppressed and neither documented container consequence, the kernel modules that cannot build and the missing login session, is in play here. Those belong to capabilities 30 through 80.

Two coverage gaps that a pass does not close. Tier 1 compares the two wizards against the YAML, but it never runs either wizard's interactive flow, so a defect in the checklist rendering that does not change the parsed key set would not show up. And it asserts that an enabled toggle resolves to a mapping or a task, not that the mapping is correct: a mapping pointing at a package name that does not exist passes here and is caught by capability 20 instead.

---

## Fixtures

Almost none. The inputs are mostly the working tree itself: [../../setup/setup.sh](../../setup/setup.sh), [../../setup/setup.ps1](../../setup/setup.ps1), the four files under [../../setup/ansible/group_vars/](../../setup/ansible/group_vars/), the five dictionaries under [../../setup/ansible/vars/](../../setup/ansible/vars/), every task file under [../../setup/ansible/roles/](../../setup/ansible/roles/), [../../setup/ansible/site.yaml](../../setup/ansible/site.yaml), [../../setup/ansible/tasks/](../../setup/ansible/tasks/), [../../setup/ansible/profiles/](../../setup/ansible/profiles/), the four native installers under [../../setup/windows/](../../setup/windows/), [../tier1/documented_no_ops.txt](../tier1/documented_no_ops.txt), [../../setup/ansible/verify_install.yaml](../../setup/ansible/verify_install.yaml) and [../tier3/verify.yaml](../tier3/verify.yaml).

The one exception is `os_family_derivation`, which needs an input that is not part of the thing under test: one real `/etc/os-release` per distribution, in [../tier1/os_release_fixtures/](../tier1/os_release_fixtures/). They live beside the check rather than in [../fixtures/](../fixtures/) because they belong to a single tier 1 check rather than to a container capability. Each file carries, in a comment at the top, the archive, packaging repository or forum paste it was taken from, so a reader can re-derive it rather than trust it. Nothing here is written by hand from memory, which matters because a fixture that invents `ID_LIKE` would prove the derivation agrees with the invention.

---

## Concurrency

- Mutates: none in the repository. Read-only against every input listed under Fixtures. Over-declared because the syntax check touches them: `~/.ansible/tmp` and the fact cache directory named in `ansible.cfg`, both under the invoking user's home.
- Conflicts with: any process editing files under [../../setup/](../../setup/) or [../tier1/documented_no_ops.txt](../tier1/documented_no_ops.txt) while it runs, because the working tree is the input and an edit mid-run produces a result that describes neither the before nor the after state. It conflicts with no other capability test, and it can run alongside any container scenario.
- Serial: false.
