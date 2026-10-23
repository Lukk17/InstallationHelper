# AGENTS.md for setup/ansible/

Rules for the playbook. How it is put together, and why, is in [ansible_architecture.md](ansible_architecture.md).

### Before you work here

1. Before adding an application, read "Adding a new application" in [ansible_architecture.md](ansible_architecture.md).
2. Before touching a `raw` install task, `apt_raw_env`, `apt_raw_flags` or the temporary paths in [ansible.cfg](ansible.cfg), read "The ansible-core deserialization bug, and the workaround" in [ansible_architecture.md](ansible_architecture.md) and run its recurring upstream check. They look like something to clean up and are not.
3. Before deciding which run the change owes, read [../../e2e/AGENTS.md](../../e2e/AGENTS.md). Any change here owes at least the tier 1 gate, and a package name owes tier 2.
4. Before choosing a package manager for a mapping, read "Package manager order per OS" in [ansible_architecture.md](ansible_architecture.md).

### Rules no check catches

1. A per-distribution fact belongs in `vars/<OS>.yaml` and is read through `os_dict`. Never write a group name, a package name, a path or a service name into a task. The OpenRazer group was written to Debian's answer and failed every Arch run.
2. Prove a package or group exists on every OS family you claim to support, not only the one you tried. Debian's answer does not carry over.
3. Never use `failed_when` or a `rescue` to turn a real failure into a pass. A two-condition `failed_when` is joined with AND, which is how one bad package name silently dropped every Arch package while the run stayed green.
4. A toggle is not implemented until something consumes it. A comment saying another role handles it is not an implementation.
5. An install that cannot work is a bug even when the playbook exits 0. OpenRazer installed on Arch with no kernel headers, so the driver never built.
6. A `changed_when` must read the stream the tool really writes to. Run the tool twice and look at which stream each line comes out on, defect class 8 in [../../docs/regression_ledger.md](../../docs/regression_ledger.md).
7. A verification query must work in the state the run leaves the machine in, after the playbook's own cache cleanup, not in a fresh container's state.
8. Never run `ansible-playbook`, `--syntax-check` or [../setup.sh](../setup.sh) yourself, not in PowerShell, Git Bash or WSL. WSL is the owner's computer too. The gate runs the syntax check.
