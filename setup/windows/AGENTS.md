# AGENTS.md for setup/windows/

Rules for the native Windows installer, [../setup.ps1](../setup.ps1) and the modules in this folder. Ansible never runs on Windows. These read the same toggles and the mappings in [../ansible/vars/Windows.yaml](../ansible/vars/Windows.yaml).

### Before you work here

1. Before choosing between winget, Chocolatey and a vendor installer, read "Package manager order per OS" in [../ansible/ansible_architecture.md](../ansible/ansible_architecture.md). A Chocolatey mapping carries the reason beside it in `vars/Windows.yaml`.
2. Before deciding which run the change owes, read [../../e2e/AGENTS.md](../../e2e/AGENTS.md). Tier 1 runs the Pester suite. A real install is a Windows Sandbox run or the `windows` target of the single platform workflow, and what neither can prove is in [../../e2e/manual_test_matrix.md](../../e2e/manual_test_matrix.md).
3. Before writing PowerShell here, read defect classes 2, 3, 4, 5 and 20 in [../../docs/regression_ledger.md](../../docs/regression_ledger.md). Each was written in this folder once already.

### Rules no check catches

1. Wrap a function's list result at the call site, `@(Get-Thing)`. A one-element array returned from a function unrolls to a bare value, and `.Count` on it is a terminating error under `Set-StrictMode -Version Latest`.
2. Split a program's output on `'\r?\n'`, through `Get-CommandOutputTail` in [WindowsSoftware.ps1](WindowsSoftware.ps1). The Linux PowerShell in the gate never sees the carriage return, so the gate cannot catch a split on line feeds alone.
3. A path in `vars/Windows.yaml` uses a separator that needs no escape. Ansible and a PowerShell regex read that file with different escaping rules.
4. When the winget path, the Chocolatey path and the verification must agree on whether a package applies, they call one function. Three separate decisions disagreed in one run, and the run passed.
5. A vendor's support matrix is not the installer's behaviour. Measure what the installer does, inside Windows Sandbox or on a hosted runner, never on the owner's computer.
