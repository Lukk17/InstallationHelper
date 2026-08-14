# e2e fixtures

Input files a capability test reads. This directory exists because the `e2e-runbooks` scaffold defines it, and it is currently empty of fixtures.

Section headings in this file sit at level two because the `e2e-runbooks` scaffold template fixes them there, which overrides this repository's level-three heading rule.

---

## Why there are no fixtures yet

The scaffold template for this directory describes canary files for a retrieval-style suite: short documents holding invented place names and unique identifiers, so a passing test proves the answer came from the attached file rather than from a model's memory. Nothing in this project's suite works that way.

The capability under test is an Ansible playbook. Its inputs are the toggle files under [../../setup/ansible/group_vars/](../../setup/ansible/group_vars/), the per-distribution dictionaries under [../../setup/ansible/vars/](../../setup/ansible/vars/), and the scenario files under [../tier3/scenarios/](../tier3/scenarios/). All three are part of the working tree the test is asserting against, so copying them here would create a second source of truth that drifts, which is the failure this suite exists to catch. The scenario files stay where the harness reads them.

---

## When a fixture does belong here

Put a file here when a capability test needs an input that is not part of the thing under test. Two cases that would qualify.

1. A broken working tree used to prove a check fails. [../README_E2E.md](../README_E2E.md) requires every new check to be proven against a copy of the tree carrying the old defect, and `E2E_REPO_ROOT` in [../lib/common.sh](../lib/common.sh) exists so a check can be pointed at such a copy. A minimal fixture tree, rather than a full copy, would live here.
2. A recorded upstream response used to test the tier 2 resolver without hitting the network.

---

## Per-fixture documentation

Each fixture's purpose goes in this table when the first one lands.

| File | Used by | What makes it distinctive |
|---|---|---|
| none yet | | |
