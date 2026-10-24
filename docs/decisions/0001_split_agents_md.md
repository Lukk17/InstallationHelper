# 0001: Split the root AGENTS.md into nested files and hold it to a size limit

Date: 2026-10-23
Status: accepted
Deciders: the owner

---

### Context

Every agent this repository supports loads the root [AGENTS.md](../../AGENTS.md) at the start of every session. By 2026-10-23 it had grown to 671 lines and 66,904 bytes, about 13,000 tokens by the estimate of words times 1.3. Most of it applied to one folder only: the e2e tiers, the Ansible architecture, the local dev stack, the OpenSpec rules. A session that only edited a homelab page still paid for all of it.

Codex reads `AGENTS.md` files from the root down to the working directory and stops adding them once the total reaches `project_doc_max_bytes`, 32 KiB by default. The root file alone was twice that, so Codex was reading a truncated copy, and nothing told anyone where it stopped.

Every supported agent loads a folder's own `AGENTS.md` natively when work reaches that folder. Claude Code reads the root file at the start and a nested one when it reads a file in that folder, Codex joins the chain from the root to the working directory, and OpenCode, Kilo Code and GitHub Copilot load per directory. That loading works only while the repository holds no `CLAUDE.md`, `CLAUDE.local.md` or `.claude/CLAUDE.md`.

The limits and the reasoning behind them come from the "Writing AGENTS.md files" section of `AGENTS.md.example` and the "Instruction files" section of `docs/AGENT_TOOLING.md` in [agent-standards](https://github.com/Lukk17/agent-standards).

---

### Decision

The root `AGENTS.md` keeps the pointers to skills, subagents and hooks, the three mandatory rules as short blocking rules, the conventions that apply everywhere, and a table that says what to read before working in each folder. Everything else moves to a nested `AGENTS.md` beside the code it governs, or into the docs that already explained it, and the nested file links there:

1. [e2e/AGENTS.md](../../e2e/AGENTS.md): the gate, the tiers, what to run when you change something, watching long runs, with the detail in [e2e/README_E2E.md](../../e2e/README_E2E.md).
2. [setup/ansible/AGENTS.md](../../setup/ansible/AGENTS.md): the Ansible rules no check catches and the ansible-core deserialization workaround, with the detail in [setup/ansible/ansible_architecture.md](../../setup/ansible/ansible_architecture.md).
3. [setup/windows/AGENTS.md](../../setup/windows/AGENTS.md): the Windows rules.
4. [local-dev/AGENTS.md](../../local-dev/AGENTS.md), [homelab/AGENTS.md](../../homelab/AGENTS.md) and [openspec/AGENTS.md](../../openspec/AGENTS.md).
5. The defect classes go to the top of [docs/regression_ledger.md](../regression_ledger.md).

The root file stays under 200 lines and 32,768 bytes, every nested `AGENTS.md` under 60 lines, and no `CLAUDE.md` or `CLAUDE.local.md` exists anywhere. The tier 1 check [e2e/tier1/agents_md_size.sh](../../e2e/tier1/agents_md_size.sh) fails the gate when any of that breaks.

---

### Alternatives considered

#### Keep one file and trim it

1. Pros: one place to read, nothing to cross-reference.
2. Cons: the e2e and Ansible rules alone fill more than 32 KiB, so trimming to the limit would have meant deleting rules rather than moving them.
3. Why not: a rule that is gone cannot stop the mistake it was written for.

#### Raise Codex's limit with project_doc_max_bytes

1. Pros: no restructuring.
2. Cons: every agent still loads every rule in every session, and the setting has to be made on every machine and in every agent's own way.
3. Why not: it fixes the truncation for one agent and leaves the context cost for all of them.

#### Import the folder files from the root with an @ line

1. Pros: one entry point.
2. Cons: Claude Code loads an imported file at launch, so every session pays for every file again, and only Claude Code understands the import.
3. Why not: it brings back exactly the cost the split removes.

---

### Consequences

#### Positive

1. A session at the root loads about 2,600 tokens of project instructions instead of about 13,000, measured on 2026-10-23 as 111 lines and 13,959 bytes against 671 lines and 66,904 bytes. Work in `e2e/`, the largest folder file, adds about 600.
2. Codex reads the whole chain again, because the root and the largest nested file together stay under 32 KiB.
3. A rule sits beside the code it governs, so an agent working in that folder sees it when it matters.

#### Negative

1. A rule is now in one of seven files, and an agent that never reads a file in a folder never sees that folder's rules. The table in the root file is the mitigation, and it has to stay accurate.
2. Source comments and docs that said "defect class N in AGENTS.md" had to be pointed at the ledger, and a new one written the old way would be wrong.

#### Risks

1. The files grow back. The tier 1 check stops that at the limits, but not below them.
2. A rule is lost in a move. The list of every moved rule and where it now lives is in the change that made this split, and the root table names every nested file.
