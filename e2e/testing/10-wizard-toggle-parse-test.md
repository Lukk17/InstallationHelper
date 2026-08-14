# wizard-toggle-parse: e2e test

Tier 1 of the harness, the pre-commit gate. Seconds, no container, nothing installed.

Section headings sit at level two because the `e2e-runbooks` test-spec template fixes the seven section names at that level, which overrides this repository's level-three heading rule.

The capability is named after the wizard parse check because that is the defect the tier was built around, but the gate command runs all three tier 1 checks and cannot run one alone. All three are covered below.

---

## What this verifies

- Both wizards read the same toggles out of the same YAML. For each of `group_vars/all.yaml`, `linux.yaml`, `macos.yaml` and `windows.yaml`, the key and state set that `read_boolean_toggles` in [../../setup/setup.sh](../../setup/setup.sh) emits equals an independent parse of the file, and the key set that [../../setup/setup.ps1](../../setup/setup.ps1) matches equals the key set bash emits. This exists for the "Wizard toggle parse desync" entry in [../../docs/regression_ledger.md](../../docs/regression_ledger.md): an end-anchored state substitution let any toggle carrying a trailing comment reach the caller unconverted, so 11 toggles on Linux and 4 on macOS rendered unchecked with a stray colon in the label and could not be controlled in either direction, while the PowerShell wizard was never affected.
- No toggle is dropped or malformed on the way from the YAML to the wizard. Every emitted line has the shape `<key> ON|OFF`, no emitted key carries a colon, and the emitted count matches the independent count. The desync entry above produced the variable name `install_tailscale:=false`, which Ansible accepts silently and which leaves the real toggle untouched.
- Every enabled toggle resolves to something that installs it, per OS family. For Debian, RedHat, Archlinux, Darwin and Windows, each toggle whose effective value is true either has a `software_mapping` entry in `vars/<family>.yaml`, or is referenced as `install_<key>` by a role task file or by `site.yaml` with comments stripped, or is listed for that family in [../tier1/documented_no_ops.txt](../tier1/documented_no_ops.txt). This exists for the "Toggles enabled with no mapping and no task" entry in the ledger, where `install_putty` had no mapping on Arch or Fedora and `install_gradle` had none on Debian or Fedora behind a comment claiming SDKMAN handled it, and for the "Toggles that had already been dead for a while" entry, where four toggles appeared ticked in the wizard with no working install path on any operating system.
- The documented no-op list stays honest. No line in it forgives a toggle that has since gained a real mapping, because a stale entry makes a later break in that mapping look intentional.
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

Wait for the process to exit. It runs the three checks in order and does not stop at the first failure, so the whole output is meaningful even when something fails early.

---

## Expected

The process exits 0. A non-zero exit means at least one check failed, and the harness prints the failing check names under a per-script tally line. Each script reports its own tally with the shape `<label>: N checks, all passed`, so a script that fails still tells you how many assertions ran.

For each of `all.yaml`, `linux.yaml`, `macos.yaml` and `windows.yaml`, the wizard parse check reports five passes: the bash parse matches the YAML with a toggle count, every emitted line has the shape `<key> ON|OFF`, no key carries a stray colon, no toggle is dropped between the YAML and the wizard, and the two wizards see the same toggle keys. A mismatch prints a truncated diff of the two key sets rather than a log excerpt.

The toggle coverage check reports one pass per OS family, `Debian`, `RedHat`, `Archlinux`, `Darwin` and `Windows`, each stating how many enabled toggles resolved. A failure names the unresolved toggles. One further pass states that the documented no-op list has no stale entries, and a failure names each family and toggle pair that is forgiven while a real mapping now exists.

The static check reports that `site.yaml` parses, that the syntax check emitted at most two warnings with the actual count in the message, that no repository file is mistaken for an inventory source, and that `verify.yaml` parses. The two expected warnings are correct: no inventory was passed, so only the implicit localhost exists and it does not match `all`.

Optional linters behave asymmetrically on purpose. A yamllint finding fails the gate when yamllint is installed. An ansible-lint finding is printed and never fails. When either tool is missing, the run says so and skips it.

Container limitations do not apply to this capability. No container starts, so nothing in [../tier3/container_limits.yaml](../tier3/container_limits.yaml) is suppressed and neither documented container consequence, the kernel modules that cannot build and the missing login session, is in play here. Those belong to capabilities 30 through 80.

Two coverage gaps that a pass does not close. Tier 1 compares the two wizards against the YAML, but it never runs either wizard's interactive flow, so a defect in the checklist rendering that does not change the parsed key set would not show up. And it asserts that an enabled toggle resolves to a mapping or a task, not that the mapping is correct: a mapping pointing at a package name that does not exist passes here and is caught by capability 20 instead.

---

## Fixtures

None. The inputs are the working tree itself: [../../setup/setup.sh](../../setup/setup.sh), [../../setup/setup.ps1](../../setup/setup.ps1), the four files under [../../setup/ansible/group_vars/](../../setup/ansible/group_vars/), the five dictionaries under [../../setup/ansible/vars/](../../setup/ansible/vars/), every task file under [../../setup/ansible/roles/](../../setup/ansible/roles/), [../../setup/ansible/site.yaml](../../setup/ansible/site.yaml), [../tier1/documented_no_ops.txt](../tier1/documented_no_ops.txt) and [../tier3/verify.yaml](../tier3/verify.yaml).

---

## Concurrency

- Mutates: none in the repository. Read-only against every input listed under Fixtures. Over-declared because the syntax check touches them: `~/.ansible/tmp` and the fact cache directory named in `ansible.cfg`, both under the invoking user's home.
- Conflicts with: any process editing files under [../../setup/](../../setup/) or [../tier1/documented_no_ops.txt](../tier1/documented_no_ops.txt) while it runs, because the working tree is the input and an edit mid-run produces a result that describes neither the before nor the after state. It conflicts with no other capability test, and it can run alongside any container scenario.
- Serial: false.
