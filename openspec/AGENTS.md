# AGENTS.md for openspec/

Rules for spec-driven changes under [changes/](changes/). The lifecycle, propose, apply, verify and archive, and the command spelling each agent shows, are in "OpenSpec workflow" in [../docs/AGENT_TOOLING.md](../docs/AGENT_TOOLING.md).

### Before you work here

1. Before implementing a change, read its `proposal.md`, `design.md`, every `spec.md` and `tasks.md`.
2. Before touching [changes/add-playbook-e2e-capability-tests/](changes/add-playbook-e2e-capability-tests/), read [../e2e/testing/README.md](../e2e/testing/README.md), which it describes.

### Rules no check catches

1. Never start coding on your own. If planning leaves a question or a consideration open, ask it first, and ask again whenever something is unclear.
2. A `proposal.md` holds everything the implementer needs: every command, file path, link and implementation step. Do the research while planning, so the implementer never has to guess or research again.
3. Keep `proposal.md`, `design.md`, every `spec.md` and `tasks.md` current. Mark a task `[x]` in `tasks.md` the moment it is done, and leave `[ ]` on what is not.
4. Follow the proposal when applying a task. To deviate, update the documents first.
5. Never archive [changes/add-playbook-e2e-capability-tests/](changes/add-playbook-e2e-capability-tests/), not with `/opsx:archive` and not by moving it by hand. It is the living description of the e2e capability tests.
6. When a capability is added, removed or renumbered, or changes its invocation or cost, update `proposal.md`, `test-spec.md` and `tasks-template.md` in that change in the same piece of work. [../e2e/tier1/capability_index_parity.sh](../e2e/tier1/capability_index_parity.sh) checks the numbers and names, not the rest.
