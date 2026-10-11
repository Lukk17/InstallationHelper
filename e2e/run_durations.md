# Measured run durations

How long each cell of the e2e sweep actually takes on GitHub-hosted runners, so nobody has to guess before dispatching one.

---

### Where these numbers come from

Every figure below comes from GitHub's own start and end time for each job, across three full sweeps of [e2e-matrix.yml](../.github/workflows/e2e-matrix.yml). Measured on 2026-10-11.

| Run | Date | Commit | Result |
|---|---|---|---|
| [32839893770](https://github.com/Lukk17/InstallationHelper/actions/runs/32839893770) | 2026-08-25 | `2db3e69` | finished, both long Windows cells failed on one package each |
| [38107292439](https://github.com/Lukk17/InstallationHelper/actions/runs/38107292439) | 2026-10-11 | `bf1c930` | finished, sixteen Linux cells and one Windows cell failed |
| [38130934506](https://github.com/Lukk17/InstallationHelper/actions/runs/38130934506) | 2026-10-11 | `1ddb58d` | finished, Fedora GNOME full and both long Windows cells failed |

Each cell below shows how many runs it counts, then the average, the fastest and the slowest, all in whole minutes. Read the average as an order of magnitude, not a guarantee. Hosted runners vary: Ubuntu all software took 58 minutes in one run and 34 in another, on the same image and the same scenario. Treat anything within twenty per cent of the average as normal, and look at the slowest figure before choosing a ceiling.

To take the measurement again for another run, replace the identifier and run this.

Bash:

```bash
gh api "repos/Lukk17/InstallationHelper/actions/runs/<RUN_ID>/jobs?per_page=100" --jq '.jobs[] | "\(.name)\t\(.started_at)\t\(.completed_at)"'
```

PowerShell:

```powershell
gh api "repos/Lukk17/InstallationHelper/actions/runs/<RUN_ID>/jobs?per_page=100" --jq '.jobs[] | "$($_.name)`t$($_.started_at)`t$($_.completed_at)"'
```

---

### Which cells count, and which do not

A cell that failed is counted when it still did all of its work: the playbook ran to its recap, the verification ran, and a failure only changed the verdict. That covers every failed cell in these three runs except two.

Kept out of the averages, because they stopped before doing the work the cell normally does:

| Run | Cell | Minutes | Why it ended early |
|---|---|---|---|
| 38107292439 | Fedora idempotency | 32 | the first pass failed because the Tailscale repository could not be added, so the second pass never ran |
| 38130934506 | Fedora GNOME full | 29 | the SDKMAN install failed, so the four Java versions and the Android SDK were never installed |

Counted, although the cell failed:

1. In 38107292439, five other Fedora cells, defaults, all software, KDE full, KDE configure and GNOME full, hit the same Tailscale repository failure. The playbook skipped only Tailscale, ran everything else and then verified, and each took within four minutes of its own figure in the other two runs.
2. In 38107292439, the idempotency cells on Arch, CachyOS, Debian, Pop!_OS and Ubuntu ran both passes in full and failed because one task reported a change on the second pass.
3. In 38107292439, forced failure on Arch, CachyOS and Fedora, and GNOME full on CachyOS, ran to the recap and the verification and failed an assertion there.
4. Every failed Windows cell, in all three runs, ran all of its phases and its verification and failed on one to three packages.

---

### The whole sweep, stage by stage

| Run | Dispatch to last job | Stage 1 | Linux stage | macOS and Windows stage | Job minutes added up |
|---|---|---|---|---|---|
| 32839893770 | 254 | 15 | 116 | 123 | 2182 |
| 38107292439 | 191 | 4 | 109 | 78 | 1961 |
| 38130934506 | 214 | 3 | 117 | 95 | 1963 |

Stage 1 runs from dispatch until the gate job passes, the Linux stage from there until the last Linux cell ends, and the last stage from the Linux verdict until the last macOS or Windows cell ends. The stages run one after another, so they add up to the wall time. Stage 1 in 32839893770 waited 13 minutes for its first job to start, which is why it is 15 rather than 3 or 4. This page used to give 241 minutes for that run, counted from the first job starting rather than from the dispatch.

The Linux stage is the part that surprises people. A Linux cell averages about 36 minutes, yet the stage takes nearly two hours. GitHub Free runs at most 20 jobs at once across the whole account, and the stage has 48 cells. In all three runs exactly 20 Linux cells were running at the peak, never more, so the 48 cells go through in roughly three waves of about 40 minutes each.

The last stage is set by Windows alone. Its two long cells start together with everything else in the stage and finish well after the macOS cells.

So a full sweep is a three to four hour commitment.

---

### Linux container cells

Six distributions across eight scenarios, each a real Ansible run inside a systemd container ending in the playbook's own verification.

| Cell | Runs | Average | Fastest | Slowest |
|---|---|---|---|---|
| Arch idempotency | 3 | 59 | 51 | 74 |
| CachyOS idempotency | 3 | 48 | 45 | 53 |
| Arch defaults | 3 | 48 | 42 | 57 |
| CachyOS defaults | 3 | 47 | 44 | 53 |
| CachyOS KDE full | 3 | 47 | 41 | 55 |
| Arch KDE full | 3 | 47 | 44 | 48 |
| CachyOS GNOME full | 3 | 46 | 40 | 55 |
| CachyOS all software | 3 | 45 | 41 | 48 |
| CachyOS KDE configure | 3 | 45 | 40 | 51 |
| Arch all software | 3 | 45 | 37 | 52 |
| Debian idempotency | 3 | 44 | 43 | 46 |
| Arch GNOME full | 3 | 44 | 42 | 45 |
| Pop!_OS idempotency | 3 | 44 | 40 | 47 |
| Ubuntu idempotency | 3 | 43 | 42 | 44 |
| Ubuntu all software | 3 | 42 | 34 | 58 |
| Ubuntu GNOME full | 3 | 42 | 39 | 46 |
| Ubuntu KDE full | 3 | 41 | 40 | 43 |
| Pop!_OS KDE full | 3 | 41 | 38 | 44 |
| Fedora idempotency | 2 | 41 | 41 | 41 |
| Pop!_OS GNOME full | 3 | 41 | 35 | 45 |
| Ubuntu KDE configure | 3 | 40 | 39 | 43 |
| Pop!_OS defaults | 3 | 40 | 34 | 51 |
| Pop!_OS all software | 3 | 39 | 37 | 41 |
| Arch KDE configure | 3 | 39 | 37 | 41 |
| Debian KDE configure | 3 | 39 | 35 | 45 |
| Ubuntu defaults | 3 | 39 | 34 | 43 |
| Debian GNOME full | 3 | 38 | 37 | 40 |
| Debian KDE full | 3 | 38 | 35 | 40 |
| Pop!_OS KDE configure | 3 | 38 | 37 | 40 |
| Fedora GNOME full | 2 | 37 | 37 | 38 |
| Debian all software | 3 | 37 | 34 | 41 |
| Fedora KDE configure | 3 | 36 | 33 | 40 |
| Fedora KDE full | 3 | 35 | 34 | 35 |
| Debian defaults | 3 | 33 | 31 | 35 |
| Fedora all software | 3 | 33 | 31 | 35 |
| Fedora defaults | 3 | 31 | 30 | 34 |
| Arch forced failure | 3 | 27 | 21 | 38 |
| Ubuntu forced failure | 3 | 27 | 25 | 29 |
| Debian forced failure | 3 | 27 | 25 | 29 |
| Pop!_OS forced failure | 3 | 27 | 26 | 28 |
| CachyOS forced failure | 3 | 27 | 21 | 38 |
| Fedora forced failure | 3 | 23 | 22 | 25 |
| Arch live profile | 3 | 19 | 16 | 22 |
| CachyOS live profile | 3 | 17 | 16 | 18 |
| Ubuntu live profile | 3 | 14 | 12 | 18 |
| Debian live profile | 3 | 14 | 13 | 15 |
| Pop!_OS live profile | 3 | 14 | 12 | 15 |
| Fedora live profile | 3 | 12 | 10 | 14 |

Most cells average between 31 and 48 minutes. Three things move a cell away from that.

Arch and CachyOS are consistently the slowest of the six: their defaults cells average 48 and 47 minutes against Fedora's 31. That is the Arch User Repository: those packages compile from source instead of fetching a binary.

Idempotency applies the whole configuration twice, but the second pass has nothing left to download, so on average it costs between 1 and 11 minutes more than its distribution's defaults rather than double. Arch idempotency, averaging 59 and once taking 74, is the most expensive Linux cell there is.

Live profile is the cheapest scenario at 12 to 19 minutes on average, because that profile installs far less. Forced failure is next at 23 to 27, because it is the only scenario that never installs the software set.

---

### macOS cells

| Cell | Runs | Average | Fastest | Slowest |
|---|---|---|---|---|
| macOS default apps | 3 | 42 | 39 | 45 |
| macOS all apps | 3 | 41 | 39 | 45 |
| macOS four apps only | 3 | 8 | 8 | 8 |

A full macOS install takes about 41 minutes whether the toggles are at their defaults or every one is enabled, which says the time goes into the same shared work rather than into the extra applications. Cheap compared to Windows for the same job.

---

### Windows cells

| Cell | Runs | Average | Fastest | Slowest |
|---|---|---|---|---|
| Windows all apps | 3 | 98 | 78 | 122 |
| Windows default apps | 3 | 82 | 72 | 87 |
| Windows four apps only | 3 | 14 | 13 | 15 |
| Windows settings only | 3 | 9 | 8 | 11 |

Windows is by far the most expensive platform, and it sets the wall clock of the entire sweep. Around eighty packages install one at a time through winget and Chocolatey, and no batching anywhere means eighty process starts and eighty separate downloads. Both long cells carry a 150 minute ceiling, and the slowest `Windows all apps` so far took 122 minutes, so the headroom is smaller than the average suggests. The two long cells also vary more than any other cell, by up to 44 minutes between runs.

If a Windows cell reports `cancelled` at close to a round number of minutes, suspect the ceiling rather than a cancellation. That happened on 2026-08-25 with a 60 minute ceiling on this same work, and a cancelled run carries no error and no failing step to read.

---

### Static and gate jobs

| Job | Runs | Average | Fastest | Slowest |
|---|---|---|---|---|
| Tier 1 checks | 3 | 3 | 2 | 4 |
| Windows unit tests | 3 | under 1 | under 1 | under 1 |
| Windows wizard plan | 3 | under 1 | under 1 | under 1 |
| macOS wizard plan | 3 | under 1 | under 1 | under 1 |
| Linux wizard plan | 3 | under 1 | under 1 | under 1 |
| Gate: checks passed | 3 | under 1 | under 1 | under 1 |
| Verdict: Linux installs | 3 | under 1 | under 1 | under 1 |

This is the argument for running tier 1 locally before pushing anything. It answers in minutes what a sweep answers in hours, measured at 6 minutes 28 seconds from Git Bash on Windows on 2026-08-29.

---

### Choosing what to dispatch

The dispatch inputs let you buy a fraction of the sweep. Times below assume nothing else is queued.

| What you want | Inputs | Cost |
|---|---|---|
| Only the static gate | run [run.sh](run.sh) locally | about six and a half minutes |
| One distribution, one scenario | `scenario: defaults, distro: fedora` | about 30 minutes |
| One scenario everywhere | `scenario: idempotency, distro: all` | about 60 minutes, six cells at once, Arch sets the pace |
| Only macOS and Windows | `start_from_stage: stage-3` | about 1.5 to 2 hours, Windows sets the pace |
| Everything | defaults | about 3 to 4 hours |

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
