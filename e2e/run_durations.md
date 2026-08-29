# Measured run durations

How long each cell of the e2e sweep actually takes on GitHub-hosted runners, so nobody has to guess before dispatching one.

---

### Where these numbers come from

Every figure below is one measurement from run [32839893770](https://github.com/Lukk17/InstallationHelper/actions/runs/32839893770), the full sweep of 2026-08-25 on commit `2db3e69`. Dispatched at 10:58 UTC, finished at 15:11 UTC.

Read it as an order of magnitude, not a guarantee. One sample per cell, and hosted runners vary: two identical apt installs measured on the same day, on the same image, came out 250 and 199 seconds apart, a twenty per cent swing on the same work. Treat anything within twenty per cent of these figures as normal.

To take the measurement again for a different run, replace the identifier and run this.

Bash:

```bash
gh api "repos/Lukk17/InstallationHelper/actions/runs/<RUN_ID>/jobs?per_page=100" --jq '.jobs[] | "\(.name)\t\(.started_at)\t\(.completed_at)"'
```

PowerShell:

```powershell
gh api "repos/Lukk17/InstallationHelper/actions/runs/<RUN_ID>/jobs?per_page=100" --jq '.jobs[] | "$($_.name)`t$($_.started_at)`t$($_.completed_at)"'
```

---

### The two numbers that matter before you dispatch

Wall clock for the whole sweep was 241 minutes. Total job time across all 62 jobs was 2182 minutes.

The gap between those two is concurrency. The GitHub Free plan allows 20 concurrent jobs account-wide, so twenty container cells run at once while the other twenty-eight queue. The tail is what sets the wall clock: the two long Windows cells run near the end and one of them alone takes two hours.

So a full sweep is a four hour commitment, and roughly half of that is waiting for Windows.

---

### Linux container cells

Six distributions across eight scenarios, each a real Ansible run inside a systemd container ending in the playbook's own verification.

| Cell | Minutes |
|---|---|
| Arch idempotency | 74 |
| Ubuntu all software | 58 |
| Arch defaults | 57 |
| CachyOS GNOME full | 55 |
| CachyOS KDE full | 55 |
| CachyOS defaults | 53 |
| Arch all software | 52 |
| CachyOS KDE configure | 51 |
| Pop!_OS defaults | 51 |
| CachyOS all software | 48 |
| Debian idempotency | 46 |
| Debian KDE configure | 45 |
| CachyOS idempotency | 45 |
| Arch KDE full | 44 |
| Arch GNOME full | 44 |
| Ubuntu KDE configure | 43 |
| Ubuntu defaults | 43 |
| Pop!_OS GNOME full | 42 |
| Ubuntu idempotency | 42 |
| Fedora idempotency | 41 |
| Debian all software | 41 |
| Debian GNOME full | 40 |
| Pop!_OS all software | 40 |
| Fedora KDE configure | 40 |
| Pop!_OS idempotency | 40 |
| Arch KDE configure | 40 |
| Ubuntu KDE full | 40 |
| Ubuntu GNOME full | 39 |
| Pop!_OS KDE full | 38 |
| CachyOS forced failure | 38 |
| Fedora GNOME full | 38 |
| Arch forced failure | 38 |
| Pop!_OS KDE configure | 37 |
| Debian KDE full | 35 |
| Debian defaults | 35 |
| Fedora all software | 34 |
| Fedora KDE full | 34 |
| Fedora defaults | 30 |
| Ubuntu forced failure | 29 |
| Debian forced failure | 29 |
| Pop!_OS forced failure | 28 |
| Fedora forced failure | 25 |
| Arch live profile | 22 |
| CachyOS live profile | 16 |
| Debian live profile | 13 |
| Ubuntu live profile | 12 |
| Pop!_OS live profile | 12 |
| Fedora live profile | 10 |

Most cells land between 30 and 58 minutes. Three things move a cell away from that.

Arch and CachyOS are consistently the slowest of the six, 40 to 57 minutes against Fedora's 25 to 40. That is the Arch User Repository: those packages compile from source instead of fetching a binary.

Idempotency costs roughly double its distribution's defaults figure, because it applies the whole configuration twice. Arch idempotency at 74 minutes is the most expensive Linux cell there is.

Live profile is the cheapest scenario at 10 to 22 minutes, because that profile installs far less. Forced failure is next at 25 to 38, because it is the only scenario that never installs the software set.

---

### macOS cells

| Cell | Minutes |
|---|---|
| macOS default apps | 39 |
| macOS all apps | 39 |
| macOS four apps only | 8 |

A full macOS install is 39 minutes whether the toggles are at their defaults or every one is enabled, which says the time goes into the same shared work rather than into the extra applications. Cheap compared to Windows for the same job.

---

### Windows cells

| Cell | Minutes |
|---|---|
| Windows all apps | 122 |
| Windows default apps | 87 |
| Windows four apps only | 13 |
| Windows settings only | 11 |

Windows is by far the most expensive platform, and it sets the wall clock of the entire sweep. Around eighty packages install one at a time through winget and Chocolatey, and no batching anywhere means eighty process starts and eighty separate downloads. Both long cells carry a 150 minute ceiling, so `Windows all apps` at 122 minutes has less headroom than it looks.

If a Windows cell reports `cancelled` at close to a round number of minutes, suspect the ceiling rather than a cancellation. That happened on 2026-08-25 with a 60 minute ceiling on this same work, and a cancelled run carries no error and no failing step to read.

---

### Static and gate jobs

| Job | Minutes |
|---|---|
| Tier 1 checks | 2 |
| Windows unit tests | under 1 |
| Windows wizard plan | under 1 |
| macOS wizard plan | under 1 |
| Linux wizard plan | under 1 |
| Gate: checks passed | under 1 |
| Verdict: Linux installs | under 1 |

This is the argument for running tier 1 locally before pushing anything. It answers in minutes what a sweep answers in hours, measured at 6 minutes 28 seconds from Git Bash on Windows on 2026-08-29.

---

### Choosing what to dispatch

The dispatch inputs let you buy a fraction of the sweep. Times below assume nothing else is queued.

| What you want | Inputs | Cost |
|---|---|---|
| Only the static gate | run [run.sh](run.sh) locally | seconds |
| One distribution, one scenario | `scenario: defaults, distro: fedora` | about 30 minutes |
| One scenario everywhere | `scenario: idempotency, distro: all` | about 75 minutes, six cells at once |
| Only macOS and Windows | `start_from_stage: stage-3` | about 2 hours, Windows sets the pace |
| Everything | defaults | about 4 hours |

One trap worth knowing. Dispatching a sweep while another run of the same workflow is open does not queue behind free runners, it queues behind the whole run, because [e2e-matrix.yml](../.github/workflows/e2e-matrix.yml) declares a concurrency group with `cancel-in-progress: false`. The new run sits at `pending` with no jobs, which looks exactly like a slow start. Check for an open run first.

---

### Docs map

| Doc | What's in it |
|---|---|
| [README_E2E.md](README_E2E.md) | The harness itself, the three tiers, and what to run when you change something |
| [manual_test_matrix.md](manual_test_matrix.md) | What no pipeline here can prove, and where to prove it by hand |
| [testing/README.md](testing/README.md) | The per-scenario specifications the harness checks itself against |
| [../docs/regression_ledger.md](../docs/regression_ledger.md) | Every regression this project has suffered, and the prevention checklist |
| [../AGENTS.md](../AGENTS.md) | The mandatory gate, the defect classes, and the rest of the agent contract |
