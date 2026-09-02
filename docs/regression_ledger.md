# Regression ledger

Current as of 2026-08-28. Every entry below is written against the tree at that date, and the one still-open finding says so in its own status line.

This is the list of defects the Ansible playbook and its wizard scripts have actually suffered, mined from the project's git history and from a container audit run the same day this page was written. Every entry states the cause, what it broke, and where the fix lives, or says plainly that it is still open. The point is prevention. Read the checklist below before touching anything under [setup/](../setup/), then use the grouped entries as a reference for the failure mode you are about to repeat.

The older, pre-Ansible bash-script era of this repository (2022 to early 2024, the plain `ubuntu/*.sh` and `windows/installer.ps1` scripts) is excluded. Those commits carry no message body explaining cause and effect, and the files they touched no longer exist, so nothing in that history can be verified against current code.

---

### Checklist before calling playbook work done

1. If you touched anything that names a Linux group, a package name, or a service name, check whether that name is the same string on Debian, Fedora and Arch. If it is not, the mapping belongs in the per-distribution `vars/{OS}.yaml` dictionary, never hardcoded in a shared task file. This is the exact mistake in the Arch OpenRazer device group entry below.
2. Do not assume a package exists in a distribution's official repository just because it exists in Debian's. Check the actual repository for every OS family the toggle claims to support. This is the mistake behind the Arch OpenRazer kernel module entry, the Arch Arduino removal, and the toggle plumbing entries for `install_putty` and `install_gradle`.
3. Never let `failed_when` or a block's `rescue` turn a real failure into a passing play. If you write a `failed_when` with more than one condition, work out by hand whether Ansible ANDs or ORs them, then write a test that proves it. If a `rescue` block exists, make it name the task that failed, not just print a generic warning. See the pacman batch entry and the install-block rescue entry.
3a. A `failed_when` on `rc` is only as good as the `rc` it reads, and with `raw`, `shell` or `command` that is the shell's status, not your program's. A pipeline reports its last command, so `apt-get ... | tee log` reports tee and tee always succeeds. A command list reports the last one, so anything ending `&& echo A || echo B` reports an echo and can never be non-zero. Both were live in this repository and both had a `failed_when: rc != 0` sitting uselessly beside them. Prepend `set -o pipefail` to any pipeline whose status you intend to check, never end such a command with an echo, and prove it by making the inner command exit non-zero and watching the task fail. See the raw pipeline entry. One exception, and it is the reason this sentence has been amended: pipefail also reports a producer the kernel killed, so a pipeline whose left side never terminates on its own must not use it. `yes | anything` under pipefail always reports 141, because `yes` is still writing when the reader exits and SIGPIPE kills it. Feed the answers from a temporary file instead. Following this item literally is how that defect was written twice, in `Accept Android SDK licenses` and then in the CachyOS graphics alignment task, and `e2e/tier1/sigpipe_pipelines.sh` now fails on it.
4. A toggle in `group_vars/all.yaml` or `group_vars/linux.yaml` is not implemented until you can point at the line in a `vars/{OS}.yaml` file, or a task file, that consumes it on every OS the toggle claims to support. A code comment that says another role handles it is not verification, run it and watch the software actually appear. See the toggle plumbing entries and the dead-toggle cleanup entry.
5. If the same parsing or matching logic exists in more than one place, for example a bash wizard and a PowerShell wizard reading the same YAML, test both independently with the same fixture line. They will drift the moment one gets fixed and the other does not. This is exactly what happened in the wizard toggle parse desync entry.
6. An install that completes with exit code zero but leaves the feature non-functional is still a bug. A daemon that starts and immediately dies because its kernel module never built is not a success just because Ansible reported `ok`. See the Arch OpenRazer kernel module entry.
7. Any shell-out that could hit an interactive prompt needs its stdin closed and a real timeout, not a guessed one. See the FVM interactive-picker entry, which stalled 8 hours before anyone noticed.
8. Do not wrap a resolution or install step in a spinner or a generic heartbeat without also checking that the wrapped command's own error output still reaches the terminal. A spinner that swallows the one line saying "version not found" costs hours. See the SDKMAN and Ansible Galaxy entries under package drift and silent failure.
9. Anything that writes to shared on-disk state (a shared config file, a shared candidate registry, a shared cache) from a loop needs serialization, not just `async` for throughput. See the SDKMAN concurrency entry.
10. When a task builds against, configures, or shells out to a platform that has major versions, check which major version the distributions actually ship now, not which one the task was written for. Every current release of all four supported Linux families ships KDE Plasma 6 with Frameworks 6, and the KDE role was Plasma 5 throughout: a dead source repository, Qt 5 development packages, a `kwriteconfig5` that no longer exists, and probe paths nothing writes. The tell is a version digit in a name, so grep the role for one. Note that the old names do not all stop resolving, which is why this needs looking for rather than waiting for a failure. See the four Plasma rows below.
11. A check that reads a file must fail when it reads nothing. An assertion over an empty set passes and is indistinguishable from an assertion that found no problem, and so is a loop over an empty candidate list. Every collector needs a companion condition proving it examined something, a package count, a candidate count or a mapping count, and the tier 1 reader of the URL mappings had that guard while the tier 3 assertion mirroring it did not. See the 2026-08-17 entries.
12. Verify what the package database will call the software, not what the download is called. A mapping whose `package` field held a filename could never match an installed-package query, and the filename had rotted out of step with the real artifact anyway. Measure the name from the artifact itself with `dpkg-deb -f <file> Package` or `rpm -qp --qf '%{NAME}'`, and record in the file which tool produced it.
13. When you tolerate a failure so the run can continue, work out what else you are tolerating. A fatal task near the top of a block takes every later task in that block with it, which here meant one dead vendor URL costing roughly twenty flatpak applications, snap, and every custom install. Tolerating the item and reporting it are two separate pieces of work and both are needed.
14. A predictable path under `/tmp` is not a staging directory. Every local account can write there, so a fixed file name later installed as root, especially with a digest check disabled, lets any local user have their payload installed with root maintainer scripts. Stage in a root-owned directory with mode 0700, and remember that `get_url` does not overwrite an existing destination unless told to, which turns any permanent staging path into a cache that a version bump cannot invalidate.
15. Adding a task to a role means asking which tag selections must reach it. Tags inherited from the import are not enough for a fact every later task depends on: two `set_fact` tasks carrying no tag made every documented per-manager tag selection a silent no-op, because the fact they build was undefined and the block's own `when` then evaluated false.
16. A `shell` or `command` task has to be able to tell whether its work is already done, and the test has to be measured rather than assumed. Five tasks reported a change on every rerun and no two of them had the same cause: a probe that looked in the directory an installer used to install into, a probe keyed to a path an installer has never written, a `changed_when` reading stdout for a message the tool writes to stderr, a `changed_when` looking for a phrase the tool prints only when the flag it is given suppresses all output, and a `changed_when` keyed to a phrase the tool prints both when it did the work and when there was none to do. Run the tool twice in a container, look at what it leaves on disk and at which stream it says so on, and prefer `creates` when the artefact is one fixed path. Where it is not, ask with a separate read-only task and gate on the answer. Never reach for `changed_when: false` on a task that really does change things, because that trades a false change report for a false clean one, which is worse. See the idempotency section below.

Note added 2026-08-20: the coverage sentences below count seven scenarios, and the seventh, smoke, was removed on that date. Every toggle it enabled is already enabled in the defaults scenario, so it was the same test with 88 of 96 toggles taken out, and defaults is the cheapest container scenario now. The counts are left as they were written, because they record runs that really happened.

A harness under [e2e/](../e2e/) mechanises part of this checklist. Items 4 and 5 are fully covered by its tier 1 checks, which run in minutes and are proven to fail against the code from before each fix. Item 2 is covered by tier 2, in two halves that cover different things. The `vars/{OS}.yaml` dictionary names are resolved over HTTP for Arch, the Arch User Repository, Flathub, Homebrew, Chocolatey and winget, and deliberately not for apt or dnf, because most of those names come from repositories the playbook adds while it runs and resolving them beforehand would report healthy packages as missing. The names written directly into role task files are resolved for all four Linux families, apt and dnf included, inside the same pinned base images the tier 3 scenarios use, with the handful that genuinely need a run-time repository listed in [runtime_repo_packages.txt](../e2e/tier2/runtime_repo_packages.txt) rather than silently forgiven. So for apt and dnf, a stale name in a role is caught in seconds and a stale name in a dictionary is caught only by tier 3. Items 1 and 6 are covered by tier 3, which runs the real playbook in a container. Coverage there is uneven and worth stating exactly, because a green tier 3 is easy to read as more than it is. Arch has run all seven scenarios. Debian and Fedora have since also run the defaults scenario, on 2026-08-17: Fedora passed clean, Debian did not, failing on a balena-etcher dependency the container image cannot satisfy (`Dependency is not satisfiable: polkit-1-auth-agent|policykit-1-gnome|polkit-kde-1`, run `2026-08-17T10-13-03Z_debian_defaults`), an open finding not yet triaged. Ubuntu has run smoke and nothing else. So five of the seven scenarios remain something a person has to do by hand on Debian and Fedora, six on Ubuntu, and the desktop environment scenarios in particular have never run outside Arch. macOS has no container at all and Windows has never been run in one, its gate being a separate PowerShell entry point that needs a Docker daemon already serving Windows containers, which this project's machine is not and will not be. Items 3, 7, 8, 9 and 10 are not mechanised at all and remain review discipline.

[AGENTS.md](../AGENTS.md) carries the mandatory recurring check for the upstream ansible-core deserialization bug referenced at the bottom of this ledger, and that file is the authoritative copy, this ledger only summarises it.

---

### Found by the container harness on 2026-08-14 and 2026-08-15

Twenty defects, one per row of the table below, found by running the playbook in containers or by resolving its package names against real repositories, rather than by reading code. Listed together because they share an origin and because the list is the argument for the harness existing. All are fixed. The harness's own three defects are separate, under "Defects in the harness itself" below.

Seven of the twenty share one shape: something did not happen and the run still reported success. Three more share another: a task assumed a live desktop session that does not exist before a first login, over SSH, on a headless machine or in a container. Four more share a third: a subsystem was still written against the previous major version of the platform underneath it. Two share a fourth: a task used something the playbook was supposed to install and had not, or never did. None of the four patterns is visible in a diff.

Three of the six silent-success rows are AUR installs, all found on Arch, all with a different cause: a build that failed, a build that ran out of time, and a build that exited zero without installing. That is worth noticing on its own. An asynchronous install has three ways to not happen and each one needs its own detection, because the job result answers a different question from the machine's state.

| Defect | What it did | Where the fix is |
|---|---|---|
| flatpak was never installed on Arch | The Flathub remote-add runs on every Linux, but flatpak was installed only for Debian and RedHat, so on Arch it shelled out to a missing binary. With no rescue on that role the whole run died fifteen minutes in with nothing installed. | [base_utils.yaml](../setup/ansible/roles/system_core/tasks/base_utils.yaml) |
| The OpenRazer device group was Debian's answer everywhere | Arch has no plugdev group and patches OpenRazer to use one called openrazer, so every Arch run failed with "Group plugdev does not exist". | [custom_installs.yaml](../setup/ansible/roles/software_installer/tasks/custom_installs.yaml), group name now in os_dict |
| No kernel headers on Arch for the DKMS build | Fedora installed kernel-devel and kernel-headers, Arch installed nothing, so the OpenRazer driver never built and the daemon exited while everything reported success. | [arch_prereqs.yaml](../setup/ansible/roles/software_installer/tasks/arch_prereqs.yaml) |
| Nerd Fonts downloaded into a directory that did not exist | get_url does not create parents, and /usr/share/fonts is absent on a Linux install with no font package or desktop, which is a minimal Arch install. setup_zsh defaults true and was hidden from the wizard, so the user could not even opt out. | [fonts_theme.yaml](../setup/ansible/roles/shell_zsh/tasks/fonts_theme.yaml) |
| plasma-framework5 does not exist any more | It was the Plasma 5 name. The Konsave build-dependency task failed on it and took the whole KDE configuration down. Plasma 6 ships the same library as libplasma. | [configure_kde.yaml](../setup/ansible/roles/kde_plasma_setup/tasks/configure_kde.yaml) |
| An AUR build that ran out of time was reported as a success | async_status marks a real failure with finished 1 and failed true, but a job still building when the retries expire returns finished 0 with no failed key. The collector required `failed` to be defined, so timeouts fell through and the play exited zero with the package absent. Observed with google-chrome. | [dynamic_install.yaml](../setup/ansible/roles/software_installer/tasks/dynamic_install.yaml) |
| Setting the KDE wallpaper assumed Plasma was already running | It talks to plasmashell over the session bus, which needs a live Plasma and a session. None of that exists before a first login, over SSH, on a headless box or in a container, and the task had no tolerance for it. | [configure_kde.yaml](../setup/ansible/roles/kde_plasma_setup/tasks/configure_kde.yaml) |
| Chocolatey always tried to elevate | Start-Process -Verb RunAs fails outright with no interactive desktop to prompt on, and is pointless when already administrator, which is the normal case in a container and in CI. | [WindowsSoftware.ps1](../setup/windows/WindowsSoftware.ps1) |
| iptables-nft no longer exists on Arch | Arch consolidated: core/iptables IS the nftables build now and the old behaviour moved to iptables-legacy. The Docker install task named a package that cannot resolve, which failed the task and took the Docker install with it. That line was itself an earlier Arch fix, so the fix had rotted. | [virtualization_config/tasks/main.yaml](../setup/ansible/roles/virtualization_config/tasks/main.yaml) |
| GNOME Terminal configuration assumed a session bus | gsettings writes through dconf, which needs D-Bus. The Konsole equivalent immediately below already had failed_when false, so the KDE path survived a missing session and the GNOME path failed the whole run over a terminal preference. | [terminal_config.yaml](../setup/ansible/roles/shell_zsh/tasks/terminal_config.yaml) |
| Enabling GDM failed when SDDM already owned the machine | A machine has one display manager and systemd models that with a single display-manager.service symlink, so enabling a second fails. Happens whenever KDE and GNOME are both on, which the wizard cannot produce but group_vars can, and the all-software scenario does. | [gnome_setup/tasks/install_gnome.yaml](../setup/ansible/roles/gnome_setup/tasks/install_gnome.yaml) |
| A missing AUR package was reported as a successful run | Two causes stacked. The wait budget was a fixed 20 minutes, and aur_allow_failures defaults true so the task that would have failed the run never fired and nothing else recorded the miss. Tolerating a failure and pretending it did not happen are different things, and this did both. | [dynamic_install.yaml](../setup/ansible/roles/software_installer/tasks/dynamic_install.yaml), [defaults/main.yaml](../setup/ansible/roles/software_installer/defaults/main.yaml) |
| Four package names gone from their own distributions | libkdecorations2-dev absent from Debian and Ubuntu alike, libncursesw5-dev replaced by libncurses-dev on both, zlib-devel replaced by zlib-ng-compat-devel on Fedora 44, and Fedora has no package called systemd-boot at all, it ships as systemd-boot-unsigned. Each verified absent and each replacement verified present inside the pinned images. | [configure_kde.yaml](../setup/ansible/roles/kde_plasma_setup/tasks/configure_kde.yaml), [pyenv_unix.yaml](../setup/ansible/roles/sdk_manager/tasks/pyenv_unix.yaml), [systemd_boot/tasks/fedora.yaml](../setup/ansible/roles/systemd_boot/tasks/fedora.yaml) |
| The KDE panel widget was still a Plasma 5 project | Three failures stacked in one task. The clone was chermnyx/applet-window-buttons at branch dumb_5.27_support, a Frameworks 5 project whose upstream is archived, so find_package could not resolve on a machine with Frameworks 6 only. CMake 4 has removed compatibility with cmake_minimum_required below 3.5 and that source asked for 3.0, so configure died before reaching any dependency at all. The Plasma 6 port that replaced it pins itself to C++14 while the KDecoration3 6.7 headers need C++20, and neither -DCMAKE_CXX_STANDARD nor -std in CMAKE_CXX_FLAGS can override a plain set() plus CMake's own trailing -std flag, so the standard has to be raised at the source. | [configure_kde.yaml](../setup/ansible/roles/kde_plasma_setup/tasks/configure_kde.yaml), pin in [pinned_values.toml](../setup/pinned_values/pinned_values.toml) |
| Qt 5 and Frameworks 5 build dependencies for a Frameworks 6 build | Fourteen development packages installed so the widget could compile, all of them the previous generation's names. This is worse than a name that no longer resolves: kf5-plasma-devel and qt5-base still exist, so the task went green and installed a set of packages that could not satisfy the build it existed for. | [configure_kde.yaml](../setup/ansible/roles/kde_plasma_setup/tasks/configure_kde.yaml) |
| kwriteconfig5 was dropped with Frameworks 5 | Arch's kconfig package ships kwriteconfig6 and kreadconfig6 and nothing else, so the Spectacle shortcut task died with command not found. The task carried changed_when false, which says nothing about failure, so nothing about the way it was written softened the blow. | [configure_kde.yaml](../setup/ansible/roles/kde_plasma_setup/tasks/configure_kde.yaml) |
| An AUR build reported success while the package was absent | A third shape of AUR failure, and the only one the job's own result cannot reveal: paru exits 0, async_status returns finished 1 with no failed key, and pacman does not have the package. Both existing collectors read the job result, so neither could see it, and the playbook's own summary listed antigravity as installed while verification found it missing. Detection now asks `pacman -Qq` for every requested AUR name after the wait and treats the set difference as a failure. Proven by running the two new expressions against real pacman in a finished container: `query_rc=1`, `present=['antigravity', 'gputest']`, `ABSENT=['definitely-not-a-real-package']`. The original miss was intermittent, the rerun installed antigravity 2.8.1-1 cleanly, which is exactly why it needed detection rather than a corrected name. | [dynamic_install.yaml](../setup/ansible/roles/software_installer/tasks/dynamic_install.yaml) |
| Every apt and flatpak batch failure on the Debian family was invisible | All three `raw` callsites pipe into `tee`. A shell reports the last command's status in a pipeline, `tee` succeeds whatever preceded it, and all three tasks carry `failed_when: rc != 0`, so the guard could never fire. The full-upgrade task was worse still: it ended with `grep ... && echo CHANGED || echo UNCHANGED`, so its status was an echo's and `pipefail` alone would not have helped, its `2>&1 | tee` bound to the autoremove only because `&&` binds looser than a pipe, and it grepped a log opened with `tee -a` while its own comment claimed `>` truncated it, so from the second run onward it reported changed forever. Proven in both target images: `sh -c "exit 7" \| tee log` gives rc 0, and with `set -o pipefail` gives 7. | [base_utils.yaml](../setup/ansible/roles/system_core/tasks/base_utils.yaml), [dynamic_install.yaml](../setup/ansible/roles/software_installer/tasks/dynamic_install.yaml) |
| locale generation ran before the package that makes it possible, and never on Ubuntu | `locale_gen` needs /etc/locale.gen and /var/lib/locales/supported.d, both from the `locales` package. On Debian that package was installed further down the same file, after the task that needs it. On Ubuntu it was never installed at all, because the line carrying it was gated to distribution != Ubuntu and the Ubuntu branch installs language packs instead. A desktop install has `locales` already, so this was invisible until a minimal one ran it, and it failed inside system_core, early enough that the recap read "installed: (none)" for the whole run. Same shape as the flatpak row above: a task using something the playbook was supposed to install and had not. | [system_config.yaml](../setup/ansible/roles/system_core/tasks/system_config.yaml) |
| The widget install probe stat'd three Plasma 5 paths | One literal QML plugin path per family, all of them Plasma 5 locations that nothing writes any more, so the probe always answered "not installed" and every single run cloned and recompiled a widget that was already there. Green, idempotent-looking, and wrong. The plasmoid directory is identical on every distribution, so probing that instead removes all three hardcodings and the branch between them. | [configure_kde.yaml](../setup/ansible/roles/kde_plasma_setup/tasks/configure_kde.yaml) |

The silent-success rows are the reason item 3 of the checklist exists, and the Plasma rows are the reason item 10 does.

---

### Defects in the harness itself

Three, all found on 2026-08-15 while running the non-Arch distributions, all fixed. They are recorded separately from the table above because they are not playbook defects, and together because they share one lesson that the table cannot carry: the thing that checks can be the thing that lies, and a check that answers wrongly is worse than one that errors, because the run around it carries on and reports the wrong answer with confidence.

#### The installed-package query returned one concatenated string

Status: fixed, [e2e/tier3/verify.yaml](../e2e/tier3/verify.yaml), plus an assertion on the query's own output.

Cause: the Debian and RedHat queries were `dpkg-query -W -f=${Package}\n` and `rpm -qa --qf %{NAME}\n`. Both tools interpret `\n` in a format string themselves, so the two characters backslash and n have to reach them. Written as `\n` in a double-quoted YAML scalar it becomes a real newline, and `ansible.builtin.command` splits its argument string on whitespace, so the newline was discarded before either tool saw it.

Effect: dpkg-query printed all 201 installed package names with no separator, `adduseransibleansible-coreapt...`. Splitting that on newline yields one enormous pseudo-package, so the difference against the expected set reported every expected package as missing. On a Debian run whose playbook had genuinely succeeded, verification claimed syncthing, chkrootkit, tailscale and openrazer-meta were all absent while the apt log showed each one being configured and all four appear inside the blob in the verify log.

Cross-check: Arch is clean because `pacman -Qq` needs no format string. So the largest assertion in the suite could not pass on Debian, Ubuntu or Fedora and always passed on Arch, which is the worst available arrangement because it looked proven. Both corrected forms were checked in clean containers: 201 lines on debian:trixie, 194 on fedora:44. Both queries carry `failed_when: false`, so nothing else could have caught it, and there is now an assertion that the query returned more than fifty entries before the comparison is trusted at all.

#### An unchecked docker cp launched a playbook against an empty filesystem

Status: fixed, [e2e/tier3/container.sh](../e2e/tier3/container.sh).

Cause: `docker cp` of `setup/` into the container was not checked. Under the load of three parallel scenarios the drvfs bind mount serving the repository stumbled and the daemon failed mid-archive with `archive/tar: missed writing 3635782 bytes` followed by `unexpected EOF`, at the same time `wsl.exe` began answering `Wsl/Service/0x8007274c` to unrelated calls.

Effect: the script carried on and launched the playbook with its output redirected into a `/work` that did not exist. Confirmed after the fact: no `/work`, no `playbook.log`, no `playbook.rc`. The container sat idle and the queue would have waited out the scenario's entire 45 minute timeout for an exit code that was never coming, which is precisely the stall this harness exists to catch, produced by the harness. The copy now retries three times, asserts that `site.yaml`, `group_vars/all.yaml` and at least a hundred files arrived, and on failure removes the container and writes a `result.txt` saying the run proves nothing.

#### The unattended queue exited 0 with three scenarios failed

Status: fixed in [AGENTS.md](../AGENTS.md), which is where the command is documented.

Cause: the documented `docker run` ended its `-c` string with the run redirected to a log, and anything appended after that without capturing the status first becomes the container's exit status.

Effect: a sweep where kde-full, kde-configure-only and smoke all failed reported `Exited (0)`, three lines below run.sh printing "Scenarios that failed". A queue whose exit code cannot be trusted cannot be alarmed on or chained behind, which is the same class of problem as the shell-tied queue the container was built to replace. The image itself was never at fault: a probe exiting 7 reports 7, and the corrected form writes `QUEUE_EXIT=2` and exits 2.

---

### Found on 2026-08-17, closing the vendor-URL blind spot

Seven, all fixed, and they belong together because one of them is the reason the other six were invisible. Nine mappings across Debian, Ubuntu and Fedora install from a vendor URL rather than a repository, and no tier of the harness looked at them at all, so everything else in this section could sit in the code indefinitely with every run green.

Two of the seven were caught by review before they ever ran, and they are recorded here rather than quietly dropped, because a defect stopped at review is evidence the review is worth the time.

#### Nine URL-installed mappings that no tier checked

Status: fixed in [e2e/tier3/verify.yaml](../e2e/tier3/verify.yaml), [e2e/tier1/toggle_coverage.sh](../e2e/tier1/toggle_coverage.sh), [setup/ansible/vars/Debian.yaml](../setup/ansible/vars/Debian.yaml) and [setup/ansible/vars/RedHat.yaml](../setup/ansible/vars/RedHat.yaml).

Cause: three separate blind spots lining up. The verify play's expected set selected on `['pacman', 'aur', 'apt', 'dnf']`, so `apt_url` and `dnf_url` were excluded by construction. Tier 2 resolves names against repository indexes these packages are not in. And the `package` field for those nine mappings held a decorative filename such as `minikube_latest_amd64.deb`, which no package database ever reports, so even including them would have reported all nine as missing.

Effect: both dispatch tasks are guarded by `when: item_url | length > 0`, so a URL variable that renders empty skips the download and the install and prints nothing. Minikube, TeamViewer, VeraCrypt, AppImageLauncher and balenaEtcher, all enabled by default, could each have been silently absent on every Debian, Ubuntu and Fedora run.

Fix: `package` now holds the name the package database reports, measured against the real vendor artifacts rather than guessed, five with `dpkg-deb -f <file> Package` and four with `rpm -qp --qf '%{NAME}'`. TeamViewer's needed a second look because the rpm prints an OpenPGP `NOKEY` warning that hid the answer. The verify play now includes both managers in the comparison, records how many candidates it examined, and asserts separately that every enabled one resolved a download location. Tier 1 gained four checks that catch the same thing statically in a second, and both of their branches were proven to fail against a deliberately broken mapping and an emptied URL before being trusted.

#### A predictable /tmp path for packages installed as root

Status: fixed in [setup/ansible/roles/software_installer/tasks/dynamic_install.yaml](../setup/ansible/roles/software_installer/tasks/dynamic_install.yaml) and [custom_installs.yaml](../setup/ansible/roles/software_installer/tasks/custom_installs.yaml).

Cause: four vendor artifacts were downloaded to fixed paths under `/tmp`, `apt_url-<key>.deb`, `appimagelauncher.rpm`, `gridcoin.flatpak` and `gputest.zip`, then installed as root. `/tmp` is writable by every local account, and `get_url` does not overwrite a destination that already exists.

Effect: any unprivileged local user could pre-create one of those paths and have their own file installed as root. The AppImageLauncher path is the worst of the four, because the next task runs `rpm --install --nodigest`, which is to say with integrity checking switched off. All four now stage in a root-owned directory with mode 0700, and the fix was applied to all four rather than only the one being worked on, because two answers to the same question is how the next person picks the wrong one.

#### A staging directory that would have become a stale cache

Status: caught in review, never ran.

Cause: moving the staging path out of `/tmp` made it permanent, while `get_url` still defaulted to not overwriting an existing file and the destination was keyed on the toggle name rather than the artifact.

Effect, had it shipped: bumping a pinned version would have been ignored, the previously cached file installed instead, and tier 3 could not have caught it because it compares package names and never versions. The old `/tmp` path had bounded this to a single boot. Now the download forces a refetch, the staged files are removed after the install, and the checksum hook every other vendor download in this repository already uses is wired in here too.

#### One dead vendor URL took twenty applications with it

Status: fixed in [dynamic_install.yaml](../setup/ansible/roles/software_installer/tasks/dynamic_install.yaml).

Cause: making the download synchronous, which was itself a fix, also made it fatal, and it sits near the top of a block whose rescue skips everything after the failing task.

Effect: a single 404 on a pinned artifact, which is the failure mode this repository hits most often, would have cost the flatpak batch of roughly twenty applications, snap, and every custom install. The download is now tolerated per item, what happened is established from the file on disk rather than from the result's `failed` key, and every absent artifact is named and marks the run failed at the end.

#### A documented tag selection installed nothing

Status: fixed in [dynamic_install.yaml](../setup/ansible/roles/software_installer/tasks/dynamic_install.yaml).

Cause: the two `set_fact` tasks that build `software_installer_packages` carried no tag, so under any per-manager selection such as `--tags apt_batch`, both were skipped, the fact was undefined and the block's own `when` evaluated false.

Effect: [setup/ansible/tags.md](../setup/ansible/tags.md) documents `apt_batch` as a way to run the batched apt install and the vendor .deb installs, and running it did nothing at all while exiting zero. Both tasks now carry `always`.

#### The Windows gate could not fail

Status: fixed at the time in `e2e/tier3/Invoke-WindowsE2E.ps1`, a file since deleted with the rest of the Windows container tier on 2026-08-26.

Cause: two defects in the command generated for the container. `Invoke-Pester` was called without `PassThru`, so it returned nothing, and the script then ran `exit $r.FailedCount` on a null. Separately, the `-SkipSlow` branch interpolated the string `-ExcludeTagFilter @('Slow','Network')` onto a line of its own inside the generated script, where a leading hyphen is an operator PowerShell does not have.

Effect: with `-SkipSlow` the generated script was a parse error and the run failed before Pester started. Without it, the gate exited 0 no matter how many tests failed. Both were proven directly: `$r = $null; exit $r.FailedCount` exits 0, and feeding that exclude line to `[scriptblock]::Create` throws at the character where the array begins. The fixed form was proven the other way too, with throwaway suites: a green suite exits 0 and a suite with two failures exits 2, and the script now also refuses a run that discovered no tests rather than calling it a pass.

#### A test suite that only passed with an environment variable nobody sets

Status: fixed in [e2e/tier1/windows/WindowsSoftware.Tests.ps1](../e2e/tier1/windows/WindowsSoftware.Tests.ps1), which lived under `tier3/windows` when this happened.

Cause: the suite located the repository through `$env:E2E_REPO_ROOT` with a fallback to `C:\work`, the path inside the Windows container. The variable is set by the container entry point and by nothing else.

Effect: run the normal way from the repository, the suite reported 31 tests discovered and 0 passed, every one failing in `BeforeAll`. It had been reported as 28 passing, measured in a session that had exported the variable by hand. It now walks up from its own directory to find the repository, keeps the variable as an explicit override, and throws a clear error rather than guessing when neither works. Verified from the repository root and from an unrelated working directory, 28 passed and 0 failed in both.

---

### Findings that were open when this page was written, and what became of them

The title used to read "Open findings, not yet fixed", which stopped being true and then
misled every reader who trusted it. Each entry below carries its own status line, and those
are the authority. Nothing on this page is open as of 2026-08-25.

Five entries follow, and three of them are closed rather than open, kept anyway because each still carries something worth keeping. The AUR finding is kept in this section, with its status line saying plainly that it is fixed and confirmed, because the reasoning that got from "one package in eleven, at random" to three named causes is worth more than tidy filing and moving it would scatter it. The Windows toggles with no native install path are closed because reading the dead Ansible first shaped the native replacements that took over. `import_hibernate_task`'s missing scheduled-task file is closed because the native settings script that replaced the import is worth pointing readers at directly. The entire Windows path entry is addressed rather than closed, since the Ansible side of it is dead permanently rather than fixed, and it still records what remains true about that. The correction to an earlier entry is kept because a wrong cause left on the page is worse than no entry at all. What remains:

#### The entire Windows path is unreachable

Both wizards used to invoke the playbook as `ansible-playbook site.yaml -i localhost, -c local` from inside WSL. [setup/setup.ps1](../setup/setup.ps1) did it at an `Invoke-AnsiblePlaybook` function, since removed, that handed the command to `wsl bash -c`. So the target was the WSL distribution, and `ansible_os_family` reported Debian, which was verified by running the same command the wizard ran and printing the fact.

Consequence: every task gated on `os_family == 'Windows'` never executes, the `windows_core` role never runs, [setup/ansible/vars/Windows.yaml](../setup/ansible/vars/Windows.yaml) is never loaded as `os_dict` because the pre-task loads `vars/{{ os_family }}.yaml`, and all 77 winget plus 6 Chocolatey mappings are dead. What a Windows user actually gets is the Debian software set installed into their WSL instance.

This is architectural rather than a small bug. Making Ansible do it would need the playbook to target Windows as a host over WinRM or SSH, with an inventory that says so, and there is no `ansible_connection`, `ansible_host` or WinRM configuration anywhere in the repository.

Addressed, and not by making Ansible reach Windows. [setup.ps1](../setup/setup.ps1) no longer runs the playbook at all, on WSL or anywhere else. The software catalogue installs natively through [setup/windows/WindowsSoftware.ps1](../setup/windows/WindowsSoftware.ps1), [setup/windows/WindowsNpmTools.ps1](../setup/windows/WindowsNpmTools.ps1) and [setup/windows/WindowsCustomInstalls.ps1](../setup/windows/WindowsCustomInstalls.ps1), and the four settings that used to live in `windows_core` install natively through [setup/windows/WindowsSettings.ps1](../setup/windows/WindowsSettings.ps1). All four read the same `group_vars` and `vars/Windows.yaml` the playbook reads, so the toggles and mappings stay one source of truth and only the executor differs. Every winget and Chocolatey mapping is live again, including any added on the assumption that a reachable playbook would install it. The only thing `setup.ps1` still does with WSL is install Ansible inside the distribution, because the owner wants that tool available there, not because anything in this repository drives it from Windows.

What is still true: the playbook cannot reach Windows, and `vars/Windows.yaml` is still never loaded as `os_dict`. It is read directly by the PowerShell installers instead. Nothing Windows-shaped should be added to the playbook expecting it to run.

2026-08-20, the dead Ansible was deleted. Twenty task files could not execute on any path and are gone: the whole `windows_core` role (`main.yaml`, `windows_features.yaml`, `wsl_setup.yaml`, `wallpaper_windows.yaml`, `virtualization_windows.yaml`), the seven `ai_tools` Windows task files including the `npm_install_windows.yaml` helper, the five `sdk_manager` ones (`nvm_windows.yaml`, `sdkman_windows.yaml`, `pyenv_windows.yaml`, `fvm_windows.yaml`, `android_sdk_windows.yaml`), and the three `software_installer` ones (`windows_install.yaml`, `windows_chocolatey.yaml`, `windows_winget.yaml`). The `windows_core` import in `site.yaml` and the `windows_install.yaml` include in `dynamic_install.yaml` went with them, along with the `bootstrap_windows`, `choco` and `winget` rows in [setup/ansible/tags.md](../setup/ansible/tags.md) and the now-orphaned `chocolatey.chocolatey` collection in `requirements.yaml`.

The knowledge worth keeping is not the code, it is where each capability lives now. Optional features, WSL registration, the wallpaper and the hibernate task moved to [setup/windows/WindowsSettings.ps1](../setup/windows/WindowsSettings.ps1). The Chocolatey and winget batches moved to [setup/windows/WindowsSoftware.ps1](../setup/windows/WindowsSoftware.ps1), which also covers what `virtualization_windows.yaml` did, since `virtualbox` and `vmware` are ordinary `vars/Windows.yaml` mappings. Java, Node, Flutter, Gridcoin and Razer Cortex moved to [setup/windows/WindowsCustomInstalls.ps1](../setup/windows/WindowsCustomInstalls.ps1). The six npm command line tools moved to [setup/windows/WindowsNpmTools.ps1](../setup/windows/WindowsNpmTools.ps1). Python and the Android SDK need no code at all, because the mapping lines are the whole install.

One file was deliberately not deleted. `roles/env_variables/tasks/env_windows.yaml` creates `%USERPROFILE%\apps_config` and sets `GRADLE_USER_HOME`, `DOCKER_CONFIG`, `M2_HOME`, `ANDROID_SDK_HOME` and `KUBECONFIG` for the user plus `ANDROID_SDK_ROOT` and `ANDROID_HOME` for the machine, and nothing under `setup/windows/` does any of that. `WindowsCustomInstalls.ps1` sets `JAVA_HOME`, and that is the only user environment variable the native path writes. Deleting the file would have lost the only record of that intent, so it stays, unreachable, until somebody decides whether the native installer should carry it. It is the one Windows capability the repository has expressed and cannot currently deliver.

Two tier 1 checks read a deleted file as one side of a parity comparison and were repointed rather than weakened. `windows_npm_parity.sh` now compares [setup/windows/WindowsNpmTools.ps1](../setup/windows/WindowsNpmTools.ps1) against the `ai_tools` role's `*_unix.yaml` files, which is a stronger question than the old one: a Windows package that has drifted from the package Linux and macOS install is a real difference in what a user gets, where the old comparison held a live file against a dead one. `windows_settings.sh` used to compare the nine optional features against `windows_features.yaml`. It now asserts in bash that the declaration in `WindowsSettings.ps1` is single, led by the two features WSL 2 needs, and handed unchanged to `Enable-WindowsFeatureSet` at every call site, and asserts through PowerShell that `Get-WindowsOptionalFeatureName` returns that declaration in its order. The check went from five assertions to six.

#### Windows toggles with no native install path: closed

Closed. This entry recorded seventeen, then eleven as the CLI tools were covered, and now none. What closed the last eleven, and what reading the dead Ansible first was worth:

Six became mapping lines, because a single package is the whole install: `claude_desktop`, `lm_studio`, `jetbrains_toolbox`, `python`, `dart` and `android_sdk`. Two of those the dead Ansible had already chosen well and I would have chosen differently. `pyenv_windows.yaml` installs one interpreter rather than pyenv-win, which is right because installing pyenv-win leaves no Python behind, and `android_sdk_windows.yaml` installs Studio rather than the command line tools zip, which has no installer and no updater. A tier 1 check now ties the Python mapping to `default_python`.

Five needed [setup/windows/WindowsCustomInstalls.ps1](../setup/windows/WindowsCustomInstalls.ps1), because no single package expresses them: `java` is four JDKs plus a discovered `JAVA_HOME`, `nodejs` and `flutter` are a version manager followed by a version inside it, and `gridcoin` and `razer_cortex` are direct installer downloads. Here the dead Ansible was actively wrong and copying it would have shipped the bug: `sdkman_windows.yaml` named four Chocolatey packages, `temurin11`, `temurin17`, `temurin21` and `temurin`, none of which exist on the feed, then set `JAVA_HOME` machine-wide to a hardcoded `jdk-21.0.6+7-hotspot` when the real directory on this machine is `jdk-21.0.12.8-hotspot`.

The remainder is closed too, and it is the reason this entry still records the history rather than being deleted: [setup/windows/WindowsSettings.ps1](../setup/windows/WindowsSettings.ps1) now applies the optional features, the WSL registration, the wallpaper and the hibernate scheduled task natively, so the four `windows_core` task files that owned this OS configuration each have a working replacement. The toggle coverage check no longer counts an unreachable Windows Ansible task as coverage, so any new gap of this kind fails the gate instead of hiding, which is how the eleven were found in the first place.

#### A correction to an earlier entry in this file

An earlier version of this ledger recorded the Flathub failure as transient network contention, and it was wrong. That conclusion came from running the command three times in a clean container and seeing it succeed, but flatpak had been installed by hand first in that test, so it proved the wrong thing. The real cause was that flatpak was never installed on Arch at all, which is in the table above. Retries were added to thirteen network operations in the no-rescue bootstrap path anyway, and that change stands on its own merits, but retrying was never the fix for this.

The lesson is worth more than the fix: a reproduction that does not start from the same state as the failure proves nothing. Recorded because a wrong cause left in a ledger is worse than no entry.

#### One AUR package in eleven silently does not install, at random

Status: fixed and confirmed. All seven Arch scenarios passed both halves on the fixed code, 2026-08-16, with `QUEUE_EXIT=0` and the absent-package diagnostic never firing once across the whole sweep. Kept in full because the path from "one package in eleven, at random" to three named causes is the most useful thing on this page, and because two of my own hypotheses along the way were wrong.

The confirmation matters more than usual here, because the previous seven-green sweep was green for the wrong reason. It predated the `pacman -Qq` check, so three of those runs had a missing package and no way to notice. Green before meant the check did not exist. Green now means eleven of eleven AUR packages are present in every scenario that installs them.

| Scenario | Playbook | Verify | Wall |
|---|---|---|---|
| smoke | ok=84 failed=0 | ok=26 skipped=2 | 16m |
| live-profile | ok=95 failed=0 | ok=20 skipped=8 | 26m |
| kde-configure-only | ok=214 failed=0 | ok=26 skipped=2 | 53m |
| gnome-full | ok=204 failed=0 | ok=28 skipped=0 | 57m |
| defaults | ok=192 failed=0 | ok=26 skipped=2 | 58m |
| kde-full | ok=218 failed=0 | ok=28 skipped=0 | 61m |
| all-software | ok=208 failed=0 | ok=26 skipped=2 | 63m |

Serialising cost what it should and no more. The heavy scenarios grew by roughly seventeen minutes, `live-profile` and `smoke` got faster because their AUR sets are tiny and they no longer wait on an `async_status` poll cycle with nothing to wait for.

Cause: three separate defects, none of them the thing I first suspected.

1. `paru -S --noconfirm` still asks which provider to use when a package name has several. `--noconfirm` does not answer that question, so paru asks, gets nothing and exits 1. Four AUR packages provide `appimagelauncher` and three provide `google-chrome` besides the exactly-named ones, and both exact names are real AUR packages, checked against the AUR API. `--noprovides` makes paru target the literal name and pick exactly what the default would have picked, without the prompt. This is why it looked random and was not: it is whichever packages currently carry provider ambiguity, and the AUR gains and loses providers over time.
2. The pacman database lock. `jetbrains-toolbox` built cleanly and then died on `:: Pacman is currently in use, please wait...`. Eleven jobs fired with `poll: 0` all run at once, so `throttle: 2` was throttling the firing and nothing else. Checklist item 9 on this page already said anything writing to shared on-disk state from a loop needs serialisation rather than async for throughput, and the pacman database is shared on-disk state. The loop now runs in the foreground, one package at a time.
3. The collector meant to report a failed build could never fire. It selected on `failed == true`, and the wait task's own `failed_when: false` rewrites `failed` to false on every item. So the task whose entire job was reporting failed AUR builds had never reported one, and only the `pacman -Qq` check added the day before surfaced any of this.

Effect on the earlier evidence: the three jobs below were not silent successes at all. Each exited rc 1 and each result file on disk carried `"failed": true`. The playbook could not see it because of defect 3, and I could not see it because the three warnings are debug tasks that the `dual_logger` callback does not render on an ok task.

The occurrences, and a different package every time:

| Run | Absent |
|---|---|
| kde-configure-only, 2026-08-15T09-13 | antigravity |
| defaults, 2026-08-15T13-34 | visual-studio-code-bin |
| gnome-full, 2026-08-15T14-17 | appimagelauncher |

One of eleven at random rules out a broken package, and the packages were checked rather than assumed: `visual-studio-code-bin`'s AUR entry is healthy, maintained and not flagged out of date, and its 239 MB source from Microsoft matched the declared sha256 exactly when fetched by hand.

Effect: before the third AUR detection existed, these runs exited 0 with the package absent, which is why `defaults` and `gnome-full` were previously green and are now red. Nothing about the playbook got worse. The check that finds it got added.

What broke the deadlock: reading the failing job's own result file, which nothing had been reading. A run now prints paru's message for every absent package, through a `command` rather than a `debug`, because the `dual_logger` callback does not render a debug message on an `ok` task and that alone is why this took three runs to notice rather than one.

The detour through `kewlfft.aur.aur`'s source is kept because the mistake in it is instructive. Its `install_packages` does, per package:

```python
was_installed = package_installed(module, package)
if state == 'present' and was_installed:
    rc = 0
    continue
rc, out, err = module.run_command(command, check_rc=True)
changed_pkg = not (out == '' or 'up-to-date -- skipping' in out or 'nothing to do' in out.lower())
```

That reading produced a confident prediction and the prediction was wrong, which is worth keeping. I reasoned: `check_rc=True` means a non-zero paru fails the module outright, so the existing reported-failure collector would have caught that, therefore paru must have exited zero, therefore the fault must be the `changed_pkg` line reporting `installed: []` while the package was absent.

The first step is where it broke. `check_rc=True` does fail the module, and the module did fail, and the collector still did not catch it, because that collector was broken in a way I had not yet found. Reasoning from "the check would have caught it" to "so it did not happen" is only sound when the check works, and the whole subject of this page is checks that do not.

The evidence, once the async result files were read directly, said the opposite of the prediction: `rc: 1`, `"failed": true`, and paru's own stdout carrying the provider question. Two wrong hypotheses on the way, the module's pre-install check being fooled by the lock and then the `changed_pkg` line, both discarded by looking at the artefact instead of the code.

One process note worth keeping. While the cause was open, this entry carried an instruction not to reduce the concurrency yet, on the grounds that serialising the installs was the obvious candidate fix and would also stop the failure reproducing, leaving the cause unknown and the fix unproven. That held, and it was the right call: serialising early would have fixed the lock contention, hidden the provider prompts entirely, and left the dead collector undiscovered. Two of the three defects would still be in the tree.

#### import_hibernate_task referenced a file that does not exist: closed

`roles/windows_core/tasks/wsl_setup.yaml` ran `schtasks` against a `Hibernate@2AM.xml` under `{{ playbook_dir }}\..\tasks\`, and there is no `setup/tasks/` directory anywhere in this repository. The toggle defaulted to true, so it would have failed on every Windows run had the Windows path been reachable at all. That task never ran, per the entry above, and on 2026-08-20 the file was deleted along with the rest of the unreachable Windows Ansible.

[setup/windows/WindowsSettings.ps1](../setup/windows/WindowsSettings.ps1)'s `Register-HibernateTask` is the native replacement, and it builds the scheduled task from its action, trigger and settings directly instead of importing anything, so there is no artefact to commit before the toggle can be turned on. `import_hibernate_task` is still `false` in [group_vars/windows.yaml](../setup/ansible/group_vars/windows.yaml), which is now an owner decision rather than a hazard being avoided, and the comment beside it says so.

---

### Found on a real CachyOS machine on 2026-08-28

Four entries from one run, three of them defects this repository wrote and one a diagnosis it got
wrong. The run reached fourteen minutes, installed none of the software set, and the owner spent the
afternoon on it. Every one of the four was invisible to the gate for a different reason, which is why
three new tier 1 checks came out of it rather than one.

#### `yes |` under `set -o pipefail`, written a second time after being fixed the first time

Cause: the CachyOS graphics alignment task ran `yes | pacman -Syy --needed mesa-git lib32-mesa-git`
with `set -o pipefail` above it. `yes` never stops on its own, so the kernel kills it with SIGPIPE the
moment pacman exits, and a process killed by a signal reports 128 plus the signal number. Under
pipefail that 141 is the pipeline's answer whatever pacman did.

Effect: on a machine where both packages were already installed, pacman printed
`warning: mesa-git-26.3.0_devel.228049.0b1b8798d81-1 is up to date -- skipping` for each and then
` there is nothing to do`, with no `error:` line anywhere in it, and the task reported
`The command exited with a non-zero return code.` It retried three times over 1m 25s, failed all
three, and the play's `any_role_failed` handling then skipped every role after `arch_core`. Recap:
`ok=45 changed=14 failed=1 skipped=26 rescued=1`. Nothing the owner asked for was installed.

How it was proven rather than reasoned about: `set -o pipefail; yes | sleep 1` in a script file
answers `rc=141 pipestatus=141 0`, so the reader exited 0 and the pipeline still reported failure. An
earlier attempt at the same measurement, typed inline through `wsl bash -c`, answered 0 and was wrong:
`${PIPESTATUS[*]}` came back empty in that run, which is the tell that the shell never saw a pipeline
at all. Take the measurement from a file when the thing being measured is multi-line.

Worth stating plainly: this exact mechanism was found, fixed and written down in this repository
already, in `Accept Android SDK licenses`, and the note explaining it sits at the top of
[android_sdk_unix.yaml](../setup/ansible/roles/sdk_manager/tasks/android_sdk_unix.yaml). It was then
written again, in a different role, five days later. A note that lives next to one instance does not
protect the next one.

Checklist item 3a of this page is part of the cause and has been amended. It said to prepend
`set -o pipefail` to any pipeline whose status you intend to check, which is right for `| tee` and
produces exactly this defect on `yes |`.

Fix: the answers come from a temporary file redirected into pacman's stdin, matching the Android SDK
task, in [arch_core/tasks/main.yaml](../setup/ansible/roles/arch_core/tasks/main.yaml).

Check added: [e2e/tier1/sigpipe_pipelines.sh](../e2e/tier1/sigpipe_pipelines.sh), which reads every
Ansible shell body and every shell script under `setup/` and `e2e/`. Proven to fail against both
instances before being trusted: against `HEAD` for the CachyOS task, and against `ac770e9` for the
Android SDK one. Also proven to fail when it reads nothing.

#### A task the whole suite could never execute, and nothing said so

Cause: the alignment task is gated on `ih_os_release_id == 'cachyos'` and `install_steam`. The only
image that satisfies the first was the only image where `container_limits.cachyos.yaml` set
`install_steam: false`. Tier 1 executes nothing, tier 2 only resolves names, and tier 3 skipped the
task by construction, so that shell had never been run by the harness at all.

Effect: the defect above shipped, and the thing that found it was a person installing a real machine.

How it was proven: restoring `container_limits.cachyos.yaml` and running the new reachability check
names the task and the single image, and removing the file makes it pass.

Fix: the suppression file is deleted, so steam installs and is verified on CachyOS like everywhere
else.

Check added: [e2e/tier1/unreachable_tasks.sh](../e2e/tier1/unreachable_tasks.sh). Deliberate cases are
listed with what they cost in [uncovered_toggles_allowed.txt](../e2e/tier1/uncovered_toggles_allowed.txt),
and a line there that is no longer suppressed fails too, so the file cannot outlive its reasons.

#### The 404 was one incomplete mirror, not a repository disagreeing with itself

Cause of the wrong call: two package files the v3 index named answered 404 on `cdn77.cachyos.org`, and
that was written up as an index and a set of files that disagree, with the conclusion that steam
cannot be installed on CachyOS at all. Only one host was ever asked.

Effect: a whole package was suppressed in the harness on the strength of it, which is what hid the
SIGPIPE defect above. The suppression was the expensive part, not the misreading.

How it was proven wrong: `lib32-glibc-2.44+r24+g16be1518495f-1-x86_64_v3.pkg.tar.zst` and
`lib32-gcc-libs-16.2.1+r23+gd564253eb6c8-1-x86_64_v3.pkg.tar.zst`, the exact builds the index names,
answer 404 on `cdn77.cachyos.org` and 200 on `mirror.cachyos.org`. A ranged fetch of the first returns
`content-range: bytes 0-1023/4110126` and the zstd magic `28 b5 2f fd`, so it is the real package and
not a redirect to an error page. The index is right and one mirror is incomplete, which is what a
mirrorlist with more than one entry exists for.

The lesson is checklist item 8's, one level further in. Measuring the exact URL out of the failure was
right and it was still not enough, because a 404 from one host answers a question about that host. Ask
a second one before calling it upstream.

#### The konsave profile silently reverted the user's screen lock and session settings

Cause: `configure_kde.yaml` applies a konsave profile, and konsave copies each file in its manifest
over the live one. The shipped [lukk_desktop_profile.knsv](../setup/config/lukk_desktop_profile.knsv)
carried `save/configs/kscreenlockerrc` containing nothing but a version stanza, and
`save/configs/ksmserverrc` in the same state.

Effect: a machine deliberately configured with Lock screen automatically set to Never goes back to
Plasma's default, which is autolock on with a five minute timeout, and the Session Restore choice goes
with it. Nothing reports it. The run says success and the setting is gone.

How it was proven: reading the two members straight out of the archive, and the manifest at
`conf.yaml:53` and `conf.yaml:54` that lists them.

What this entry does not claim. It is not established that this is what locked the owner's screen on
2026-08-28. The role only runs when `configure_kde_plasma` is true, that toggle is false in
[group_vars/linux.yaml](../setup/ansible/group_vars/linux.yaml), and the run in question died in
`arch_core` long before any desktop role. Every task in that log was read and none of them touches the
display, the compositor or the locker. So this is a live hazard found while looking for that cause,
and the cause itself is still open pending the machine's own journal.

Fix: both files and both manifest lines are removed from the archive, which now holds 4617 entries
against 4619, and the rule is written down: this project does not change lock, idle or session
settings on any platform.

Check added: [e2e/tier1/desktop_settings.sh](../e2e/tier1/desktop_settings.sh), which reads inside the
`.knsv` as well as over the tree, because a grep would never have found this one. Proven to fail
against the archive as it was.

#### A sudo keepalive that could not survive Ansible's local connection

Cause: setup.sh was changed to call `sudo -v` once with a background keepalive and drop Ansible's `-K`
from both playbook invocations, so the run would rely on the warmed credential instead of prompting
itself. sudo keys its credential timestamp to the controlling terminal by default, which is
`timestamp_type=tty` in sudo 1.9, and Ansible's `-c local` connection runs sudo in a child process with
no controlling tty, so the ticket the keepalive refreshed on the parent shell was never visible to the
sudo the playbook actually invoked.

Effect: the change reached a real installation run and failed twenty seconds in, with `sudo -H -S -n`
finding no valid ticket.

```
FAILED: [localhost] => TASK: arch_core : Configure passwordless sudo for non-root user
Error: Task failed: Premature end of stream waiting for become success.
>>> Standard Error
sudo: a password is required
```

Recap: `ok=12 changed=0 failed=1 skipped=11 rescued=1`. Nothing was installed.

How it was proven rather than reasoned about: the failure text above is what the real run produced,
not a prediction read out of the diff. The revert was checked the same way, by confirming the
behaviour is back to what it was before the change, one `-K` prompt per ansible-playbook process, two
prompts in a normal run.

This defect was introduced by the agent working on this repository that same day, not found in code
anyone else wrote. It is recorded as such on purpose, because this page's own rule says a defect an
agent writes and ships itself is the one most likely to be repeated by the next agent that touches
this file.

Coverage hole: nothing in this repository's automated gate ever exercises the interactive sudo path
this change touched. Every continuous-integration call to setup.sh passes `--passwordless-sudo`, which
routes around the changed code entirely, and the tier 3 container scenarios call `ansible-playbook`
directly rather than going through setup.sh at all. The only local machine available to try the
interactive path was WSL, which needs a sudo password itself and has no terminal to type one into, so
the change was known to be unproven when it shipped rather than untested by accident.

Fix: reverted the same day in [setup/setup.sh](../setup/setup.sh), back to two separate `-K` prompts,
one per ansible-playbook invocation, and then replaced properly on 2026-08-28 by a
`prepare_become_password` function in the same file. It asks once before anything needs root,
validates the answer against `sudo -S -k` on the spot, writes it under `umask 077` into a file inside
a `mktemp -d` directory, and hands both playbooks `--become-password-file` through the single
`BECOME_ARGS` assignment that `build_playbook_args` bakes into `PLAYBOOK_ARGS` and slices `VERIFY_ARGS`
off. An EXIT trap removes the directory. That mechanism carries none of the assumption that killed the
first attempt: a file is read by whichever process opens it, so it does not care that Ansible's sudo
child has no controlling terminal and it never consults a credential timestamp at all. A machine whose
sudo needs no password is detected with `sudo -n true` first and never asked. `--print-command` still
prints `-K`, because a command copied out of the script and run by hand has no password file to read.
Check added: [e2e/tier1/become_password_file.sh](../e2e/tier1/become_password_file.sh), which asserts
the six properties that make the file safe and is proven to fail against a copy of the tree with the
`umask 077` removed. It is text analysis, so the coverage hole above is unchanged: nothing here proves
ansible-playbook authenticates from the file.

That last sentence stopped being true on 2026-08-28, when the link was measured instead of assumed.
Real sudo could not be used, because proving it that way needs a machine whose sudo demands a password
and the password itself, and WSL demands one that the agent does not have. So a stub named `sudo` was
put first on PATH in WSL Ubuntu against ansible-core 2.19.9. It parses its own argument list, writes
back the prompt string Ansible passed with `-p`, reads one line from standard input, records that line,
and then executes the remaining command with no privilege change at all. Both behaviours it relies on
were read out of the installed source first rather than taken on trust: `plugins/become/sudo.py` sets
the prompt to `[sudo via ansible, key=<id>] password:` and strips `-n` out of the default `-H -S -n`
flags whenever a become password exists, and `plugins/connection/local.py` waits for that exact prompt
in the child's output before writing the password followed by a newline. Run against `-i localhost, -c
local` with one task carrying `become: true`, the stub recorded exactly the sentinel string that the
password file held, and the play reached `ok=2 changed=0 failed=0` with the become task reported ok, so
Ansible was not left waiting on a prompt it never saw. A second file holding a different sentinel
delivered that different sentinel, and rewriting the first file in place with a third delivered the
third, which rules out anything cached by path or by process. The negative control, the same playbook
and stub with no `--become-password-file` and no `-K`, produced `-H -S -n` with no `-p` at all and
nothing whatsoever on standard input within three seconds, which is what the failure at the top of this
entry looked like from sudo's own side.

What that proves is that the contents of the file named by `--become-password-file` are read and
written to the standard input of whatever program named sudo is first on PATH, at the moment the become
plugin asks for it. What it does not prove is that real sudo then accepts the password and grants root,
because the stub never authenticates anything. That last step still needs a machine whose sudo requires
a password that somebody knows, so the honest status is that the plumbing is proven and the
authentication itself remains covered only by a real installation run.

Closed on 2026-08-29. A real CachyOS virtual machine ran the wizard end to end and the run passed:
1 hour 12 minutes, 68 packages newly installed, 7 already present, an empty errors log, and a
verification that completed all 41 assertions with `failed=0`. It got past `Configure passwordless
sudo for non-root user`, which is the exact task that died twenty seconds into the run this entry
is about, and then ran root tasks for over an hour, so real sudo does accept the password from the
file. The verification playbook also ran to completion rather than stopping on an unanswered second
prompt. The coverage hole above is unchanged and still open: this was proven by a person running
the installer, not by anything automated, and the container scenario that would prove it in the
gate is still unbuilt.

#### One character of IFS, and the checklist kept one application out of everything the user ticked

Cause: setup.sh sets `IFS=$'\n\t'` on its second executable line, and two pieces of code further
down were written as though it were still the default, one joining an array with `${_results[*]}`
and reading it back with a plain `read -ra`, the other splitting a profile name on its spaces with
an unquoted expansion.

Effect: an array expanded with `[*]` is joined with the first character of IFS, which here is a
newline rather than a space, and `read` without `-d` stops at the first newline, so exactly one key
survived the checklist however many the user marked. Every other key was then written into the extra
variables as `key=false`, and an extra variable outranks group_vars, so those applications were
actively turned off rather than merely left out and the run still reported success. Driven over a
four-key fixture with `install_alpha` and `install_gamma` marked, the wizard produced
`install_alpha=true`, `install_beta=false`, `install_gamma=false`, `install_delta=false`, so the
second key the user marked came back off. The second defect costs only a label: the loop that title
cases a profile name never split anything, so the one profile on disk was offered as `Linux live`
instead of `Linux Live`.

How it was proven: reduced to a one-liner outside the repository first, where
`IFS=$'\n\t'; a=(one two three); s="${a[*]}"; read -ra out <<<"$s"; echo "${#out[@]}"`
prints 1, and the same line with `mapfile -t out` prints 3. Then in the tree itself, both checks
failed against the shipped file and pass against the fixed one, `interactive_states.sh` at 19 checks
with 1 failed and `shell_units.sh` at 33 checks with 1 failed, both now all passed, and the
checklist assertion is made on the variables the state machine hands the playbook rather than on the
route it took.

Fix: [setup/setup.sh](../setup/setup.sh), where the checklist state now reads the keys with
`mapfile -t selected_keys` and `load_profiles` splits the name with `IFS=' ' read -ra words`, which
scopes the space to that one command instead of changing IFS for the file. The join in
`pick_software` was left alone on purpose, because joining on a newline is what keeps the value
unambiguous if a key ever contains a space, so moving the fix to the reading end trades nothing.

Found by a check written the same day,
[e2e/tier1/interactive_states.sh](../e2e/tier1/interactive_states.sh) and
[e2e/tier1/shell_units.sh](../e2e/tier1/shell_units.sh), and not by anybody reading the code. The
interactive path had never been executed by any automated test before those two files existed: the
wizard's six states, the seven back edges between them and `load_profiles` were all text that no
gate had ever run. That is the whole argument for writing them. The first time the state machine was
driven at all, both of these fell out of it, and one of them is the difference between a person
getting the software they asked for and getting one application with the rest switched off.

#### The wizard and the container harness each decide the software set, and they have never agreed

Cause: [setup/setup.sh](../setup/setup.sh) resolves which toggles a run enables in
`software_override_vars`, working from the keys `preload_toggles` collected out of `group_vars`,
while [e2e/tier3/container.sh](../e2e/tier3/container.sh) resolves the same thing again by sweeping
`^install_` out of `group_vars/all.yaml` and `group_vars/linux.yaml`. That is the same rule
implemented twice, which is defect class 2 in [AGENTS.md](../AGENTS.md), and this instance sits
inside the harness that is supposed to catch the class. The only thing the two ever shared was the
`EXCLUDED_VARS` line the harness greps out of the wizard, and nothing had compared the answers.

Effect: 100 keys are shared and agree on their value, and six are not shared at all, identically on
both the all and the defaults baseline. Four are offered only by the wizard, `set_custom_wallpaper`,
`setup_tmpfs`, `setup_zsh` and `toggle_wayland_nvidia`, because `--software all` enables every
selectable toggle and those four are system settings whose names do not begin with `install_`, so
the harness sweep cannot see them. The cost is that no container scenario in this repository has
ever executed those four roles, on any distribution, which means the automated coverage of them is
zero and always has been. That last sentence is wrong and is kept because it was believed on the day.
Three of the four are true in `group_vars` and nothing in the harness ever wrote them, so they have run
at their defaults in every container scenario ever executed here. What had never happened is their
appearing in a generated set. The Fix paragraph below has the correction and how it was established. Two are generated only by the harness, `install_gnome` and
`install_kde_plasma`, because the wizard keeps the desktop keys off the checklist and gives them a
screen where exactly one environment is chosen, while the harness has no such screen. The cost there
is that the all-software scenario installs KDE and GNOME onto the same machine, which is a
combination no wizard run can produce, so that scenario has been proving something about a machine
nobody can ask for.

How it was proven: [e2e/tier1/selection_parity.sh](../e2e/tier1/selection_parity.sh) evaluates the
two shipped implementations rather than restating either, the wizard's own functions on one side and
the sweep lifted verbatim out of `container.sh` on the other, and against the tree at
`HEAD` on 2026-08-29 it reported `only the wizard offers: set_custom_wallpaper setup_tmpfs setup_zsh
toggle_wayland_nvidia | only the container harness generates: install_gnome install_kde_plasma` for
both baselines. That the check can see a divergence at all rather than merely reprinting a fixed
list was proven by narrowing the harness sweep to `^install_[a-m]` in a copy of the tree, which
fails it and names every key the narrowed sweep stopped generating.

Fix: reconciled on 2026-08-29, in the direction the owner chose, which is that the harness follows
the wizard and `setup.sh` is not touched. `container.sh` no longer resolves a software set at all. It
calls `wizard_toggle_keys` in [e2e/lib/common.sh](../e2e/lib/common.sh), which evaluates the shipped
`EXCLUDED_VARS`, `DE_KEYS`, `LABEL_OVERRIDES`, `format_label`, `is_de_key`, `read_boolean_toggles` and
`preload_toggles` out of `setup.sh` under that file's own IFS and prints the checklist keys. There is
one rule and the harness reads it, which is the only fix that does not leave a third copy behind: a
sweep rewritten inside `container.sh` to match the wizard's answer would have been the same defect
again, one commit further on. The reader returns 3 and prints why rather than an empty list, because a
process substitution hands `mapfile` no exit status and an empty array would have generated a scenario
that installs nothing while reporting a pass over everything, which is defect class 10 in
[AGENTS.md](../AGENTS.md).

The check kept its two-route shape rather than being deleted as satisfied. `selection_parity.sh`
extracts `setup.sh`'s functions its own way on the wizard side and evaluates whatever `container.sh`
actually does on the other, so it does not reach the answer the way the harness reaches it and can
still fail. It also now asserts the coupling itself, in place of the `EXCLUDED_VARS` line it used to
assert: that the block at `mapfile -t all_toggles` calls `wizard_toggle_keys`, and that
`wizard_toggle_keys` still reads `setup/setup.sh`. Either can be undone by one paste, and each has its
own failure line. [e2e/tier1/selection_parity_allowed.txt](../e2e/tier1/selection_parity_allowed.txt)
now carries no entries and stays as the place a future divergence has to be admitted.

How the fix was proven: the check reports `all: both implementations resolve the same 104 toggles to
the same values` and the same for `defaults`, with an empty allow file, where before it reported 100
shared and 6 listed. That it can still fail was proven by pointing `E2E_REPO_ROOT` at a copy of the
tree at the previous commit, where the old `^install_` sweep is still in place: it fails four of four
checks and names every one of the six keys on both baselines. `container.sh`'s sweep was also extracted
and run on its own against the real `group_vars`, which prints 104 keys, with the four system settings
present and neither desktop key in the list.

What the reconciliation is not proven against, and this is the part to read before trusting it: no
container scenario was run, because this machine had no Docker daemon on the day. Every claim above is
static. The scenario to run first when a daemon exists is `--tier 3 --scenario all-software`, because
that is the only scenario `e2e_generate` touches and therefore the only one whose input this change
alters at all.

What changes in a real run, in both directions. `install_kde_plasma` and `install_gnome` fall out of
the generated set, so the all-software scenario installs no desktop environment and its
`e2e_expect_desktop: none` becomes true rather than merely unasserted. The desktop scenarios are
unaffected: `03-kde-full.yaml`, `04-gnome-full.yaml` and `06-kde-configure-only.yaml` each state all
four desktop keys themselves, and a key the scenario states explicitly has always won over a generated
one. The 300 minute ceiling on the all-software scenario is deliberately left alone, because dropping
two desktop environments should cut the run and nobody has measured the new number, and a ceiling
lowered on an expectation is how a slow cell starts being killed for being slow.

In the other direction the four system settings join the generated set. Three of them cost nothing,
and the claim above that none of the four had ever run in a container is wrong, which is worth more
here than the fix: `set_custom_wallpaper` is true in `all.yaml`, `setup_tmpfs` and `setup_zsh` are true
in `linux.yaml`, nothing in `container.sh`, in the scenario files or in the container limits ever wrote
any of the three, and `site.yaml` loads both `group_vars` files, so all three have run at their
defaults in every container scenario this repository has ever executed. What had never happened is
their appearing in a generated set, which is a statement about the sweep rather than about coverage.
The wrong sentence came from reading a key-set difference as a coverage claim without checking what the
playbook does when the harness writes nothing. `setup_tmpfs` only adds a line to `/etc/fstab` and
`setup_zsh` runs the `shell_zsh` role, neither of which a container prevents, so neither needs a line
in [e2e/tier3/container_limits.yaml](../e2e/tier3/container_limits.yaml). `set_custom_wallpaper` is
read only inside `configure_gnome`, `configure_kde` and `macos_core`, none of which the all-software
scenario reaches, so it stays a no-op there.

`toggle_wayland_nvidia` is the only one of the four whose value this change actually alters, from false
to true in the all-software scenario, and it is also a defect in its own right that this work found and
did not fix. Nothing consumes it. It appears in `group_vars/linux.yaml`, in `setup.sh`'s label map and
in `setup.ps1`'s label map, and in no task, no role and no template anywhere under `setup/ansible`. It
is therefore a toggle the wizard offers, the checklist labels "force Wayland on NVIDIA, can break the
session", and the playbook ignores, which is the shape of the `install_gradle` defect recorded further
down this page. `toggle_coverage.sh` cannot see it because that check collects consumers by grepping
for `install_[a-z0-9_]+` and this key has no such prefix. Turning it true in a container is safe
precisely because it does nothing, so it needs no container limit either, but it needs either an
implementation or a deletion, and it has neither.

#### A gate that was green on the machine that wrote it and red on every machine that could run it

Cause: `e2e/tier1/shell_syntax.sh` was added on 2026-08-28 and runs two things, `bash -n` over every
shell script in the tree and ShellCheck at severity warning over the same set. ShellCheck is optional
by design, reported as a SKIP when it is absent so the gate does not depend on a tool that may not be
installed. It is not installed on this development machine, so the check reported SKIP here and the
tree it was added to was never measured against it. It is preinstalled on GitHub's hosted Ubuntu
runners and on many developer machines, where the same check runs for real and fails.

Effect: the tree carried 32 ShellCheck findings at severity warning on the day the check was written,
across twelve files, so the new gate exited 0 here and 1 everywhere ShellCheck existed. Green on one
machine and red on the rest is worse than no check at all, because the machine that decides whether to
commit is the one that cannot see the failure. Two of the thirty-two were real defects rather than
noise, one silent and one that made the check around it assert less than it claimed. `cd
"${ANSIBLE_DIR}"` in [ansible_static.sh](../e2e/tier1/ansible_static.sh) had no `|| exit`, so a run
that could not reach `setup/ansible` would have gone on to syntax-check `site.yaml` in whatever
directory it happened to be in and reported a parse failure that had nothing to do with the playbook.
`ls -1 ... | xargs -r -n1 basename` in [container.sh](../e2e/tier3/container.sh) parsed `ls` output.

How it was proven rather than reasoned about: a portable ShellCheck 0.10.0 binary was fetched and run
against the tree. `shellcheck -S warning -f gcc $(git ls-files '*.sh')` reported 15 findings, and the
same command over the 56 files the check itself collects reported 32. The gap is worth recording on
its own: seven of the check scripts written that day were still untracked, so the obvious `git
ls-files` measurement under-reported the gate by seventeen findings, and only running the tool over
the set the gate builds gives the number the gate will act on. Both commands report nothing now and
exit 0.

Fix: all 32 cleared, in [common.sh](../e2e/lib/common.sh),
[ansible_static.sh](../e2e/tier1/ansible_static.sh), [pinned_values.sh](../e2e/tier1/pinned_values.sh),
[pwsh_probe.sh](../e2e/tier1/pwsh_probe.sh),
[tolerated_failures_read.sh](../e2e/tier1/tolerated_failures_read.sh),
[wizard_parse.sh](../e2e/tier1/wizard_parse.sh),
[interactive_states.sh](../e2e/tier1/interactive_states.sh),
[list_software.sh](../e2e/tier1/list_software.sh),
[print_command_resolution.sh](../e2e/tier1/print_command_resolution.sh),
[selection_parity.sh](../e2e/tier1/selection_parity.sh), [container.sh](../e2e/tier3/container.sh) and
[setup.sh](../setup/setup.sh). Three shapes, judged one at a time rather than suppressed as a batch.
The two real defects above were fixed. Three variables were genuinely dead and were deleted or renamed
to `_`: `ALLOWED_REASON` in `selection_parity.sh`, which was filled from the allow file and read
nowhere, and `de` and `attempt` in `setup.sh`, which were a local assigned and never read and a loop
counter nobody counted. The rest are variables a reader can see and the linter cannot, every one of
them set for a function that arrives through `eval` or `source`, and each carries its own
`# shellcheck disable=` on the line above with the reason. No file-level or repository-level
suppression was added anywhere, because a blanket disable hides the next real finding.

A hypothesis along the way was wrong and is kept here because the wrong turn is the useful part. The
three findings at `setup/setup.sh` lines 565, 570 and 572 were read as being about `required`, the
newline-separated collection list that `for coll in ${required}` splits on the non-default IFS of
newline and tab set at the top of that file. They are not. ShellCheck reports columns, and columns 30,
53 and 15 on those three lines all land on `missing`, an integer flag local to `install_collections`.
The linter had carried the array type over from `local missing=()` in `install_prerequisites`, a
different function five dozen lines earlier, and misread all three. `required` is correct and was never
what was flagged. The flag was renamed to `missing_any` rather than suppressed three times, because two
locals sharing a name and not a type in one file mislead a reader exactly as they misled the tool.

One more finding belongs here because it was introduced during this very fix rather than found by it.
The widened toggle check written in the entry below reads the Windows installer through
`find "${WINDOWS_DIR}" -name '*.ps1' | xargs -r sed ...`, which is SC2038, the same class as the `ls`
pipe fixed two paragraphs up, written by the same hand in the same sitting minutes after fixing it.
The gate caught it: running `shell_syntax.sh` with the portable binary on `PATH` failed with one line
naming `toggle_coverage.sh:205`. It is now `find ... -exec sed ... {} +`. The useful part is that
knowing a rule and having just applied it elsewhere did nothing to stop it, and only the mechanical
check did.

Check added: none, because the check already existed and this is the tree it was measuring. What the
episode is really about is that an optional half of a gate is a half nobody measures. ShellCheck stays
optional in [shell_syntax.sh](../e2e/tier1/shell_syntax.sh), and the lesson is to run it once by hand
against a downloaded binary before trusting a clean local run, which takes about a minute. Better
still, run the check itself with the binary on `PATH`, which is what caught the finding above.

#### A coverage check that had only ever looked at one prefix, and the dead toggles behind it

Cause: [toggle_coverage.sh](../e2e/tier1/toggle_coverage.sh) exists to catch a toggle that installs
nothing, which is the `install_gradle` shape recorded further down this page. It collected consumers
with `grep -ohE 'install_[a-z0-9_]+'` and selected toggles with `^install_[a-z0-9_]+: (true|false)$`.
`group_vars` declares booleans under eight prefixes, so `configure_`, `setup_`, `remove_`, `set_`,
`enable_`, `allow_` and `toggle_` were outside the check entirely. It also asked its question only of
toggles set to true, and a dead toggle set to false is invisible to that question while being just as
dead.

Effect: three declared toggles are consumed by nothing anywhere in the repository, and the check
reported full coverage on all five families throughout. `toggle_wayland_nvidia` is the one that reaches
a user: it is on both wizards' checklists, labelled "System: force Wayland on NVIDIA, can break the
session", and ticking it does nothing at all. `setup_grub` and `remove_distro_systemd_boot` are hidden
from both checklists by `EXCLUDED_VARS`, so only somebody editing `group_vars/linux.yaml` can reach
them, and they are the unwritten halves of a symmetric pair whose other halves, `setup_systemd_boot`
and `remove_distro_grub`, are implemented in
[systemd_boot](../setup/ansible/roles/systemd_boot/tasks/main.yaml).

How it was proven rather than reasoned about: each of the sixteen non-install toggles was searched for
by name across `setup/ansible`, `setup/windows` and both wizards. Thirteen have a real consumer. Two of
the three had appeared to have one and did not: `setup_grub` and `remove_distro_systemd_boot` are named
in `dual_logger.py`'s `ROLE_TOGGLE_MAPPING`, which decides how a skipped role is described in the
summary, and in `setup.ps1`'s `$ExcludedVars`, which decides that the checklist must not offer them.
Both are display. Counting either as an implementation is the same mistake as the `gradle` comment that
claimed SDKMAN handled it, which is why this check strips comments in the first place. The widened
check was then run against a copy of the tree under `E2E_REPO_ROOT` with one line,
`setup_nonexistent_thing: true`, appended to `group_vars/linux.yaml`: it fails on Debian, RedHat and
Archlinux naming that toggle, and lists it among the unconsumed. The check as it stood at `HEAD` passes
that same copy with `15 checks, all passed`.

Fix: the prefix is no longer in the check. Consumers are collected as every identifier the
implementation files mention and the declared set decides which of them are toggle names, so a prefix
nobody has used yet is covered on the day it is first written. The enabled direction now covers every
prefix, which took Debian from 95 toggles to 99 and Windows from 99 to 102, and Windows gained the
settings list in `WindowsSettings.ps1` as a consumer source, because `enable_hyperv`, `setup_wsl` and
`set_custom_wallpaper` are applied there and carry no `install_` prefix. A second direction was added
that asks of every declared non-install toggle, whatever its value, whether anything at all acts on it.
That direction is asked once over the union of the `group_vars` files rather than once per family,
because these toggles have one route each and the thing at the end of it differs by platform, an
Ansible task for Linux and macOS and `WindowsSettings.ps1` for Windows. Neither wizard counts as a
consumer and neither does the callback's role table, for the reason above.

The three toggles themselves are not fixed. Implementing one and deleting one are both the owner's
call, so the new direction reports them as a SKIP that names all three on every run rather than as a
failure, and the gate stays green while they are open. That is deliberate and temporary: it is recorded
in the check next to the line, and turning the `skip` into a `fail` is the whole of the change once
they are resolved. None of the three was added to
[documented_no_ops.txt](../e2e/tier1/documented_no_ops.txt), because that file is for a toggle that is
deliberately inert on some operating system and these are inert on all of them.

The owner decided on 2026-08-29 to leave all three as they are rather than implement or delete them,
and the plan for each was written down the same day so it is not lost. It lives in
[openspec/changes/implement-unconsumed-linux-toggles](../openspec/changes/implement-unconsumed-linux-toggles),
as three separately selectable tasks with the research already done, and the SKIP message now names
that directory so the gate's own output leads to it.

Check added: none, for the same reason as the entry above. The check existed, and what was wrong with
it was the width of one regular expression. Its own vacuous-pass guard was widened to match: it now
fails if the reader comes back with fewer than a hundred toggles or with only one prefix, so a future
narrowing back to `install_` is a failure rather than a quiet return to full marks.

---

### Cross-distro assumptions

#### Arch OpenRazer device group does not exist

Status: fixed. The group name now comes from `os_dict.openrazer_device_group`, which is `openrazer` in [vars/Archlinux.yaml](../setup/ansible/vars/Archlinux.yaml) and `plugdev` in the Debian and RedHat dictionaries, and a getent probe fails with an actionable message when the group is absent. Covered by the smoke and defaults scenarios on Arch.

Cause: [setup/ansible/roles/software_installer/tasks/custom_installs.yaml](../setup/ansible/roles/software_installer/tasks/custom_installs.yaml) line 315 hardcodes `groups: plugdev` on the task that adds the non-root user to the OpenRazer device group. Arch Linux has no `plugdev` group at all, before or after installing OpenRazer. Arch carries a downstream patch, `0001-Use-openrazer-group.patch`, that switches upstream OpenRazer from `plugdev` to a group named `openrazer`, created by the package's own `sysusers.conf` at gid 969.

Effect: hard task failure on Arch, reproduced with real Ansible in an `archlinux:latest` container: `fatal: [localhost]: FAILED! => {"changed": false, "msg": "Group plugdev does not exist"}`. `usermod -a -G plugdev` exits 6. Because the task sits inside a block with a rescue, this surfaced only as a generic warning and silently skipped the remaining tasks in the block, the same mechanism documented in the install-block rescue entry below.

Cross-check: Debian trixie has `plugdev` at gid 46 and Fedora 43's openSUSE Build Service package creates `plugdev` at gid 996, both verified in containers, so only Arch is wrong. Introduced in commit `dabad985651e44f4063989fa47475bd3d3776089` (2026-08-09, "feat(software): add Razer Synapse and OpenRazer, restore Razer Cortex"). The group name is a per-distribution fact and belongs in the OS dictionary, not hardcoded in a task.

#### Arch OpenRazer kernel module never builds

Status: fixed for the headers, and the underlying limitation is now documented per distribution. [arch_prereqs.yaml](../setup/ansible/roles/software_installer/tasks/arch_prereqs.yaml) installs the headers for every installed kernel, derived from each `/usr/lib/modules/*/pkgbase`. A container still cannot build the module, because the running kernel is the host's, and what that costs differs by distribution: see the Fedora entry below, where the same failure is fatal rather than cosmetic.

Cause: [setup/ansible/roles/software_installer/tasks/fedora_repos.yaml](../setup/ansible/roles/software_installer/tasks/fedora_repos.yaml) lines 129 to 131 install `kernel-devel` and `kernel-headers` before the OpenRazer DKMS build. Arch installs nothing equivalent, and Arch's own `dkms` package lists `linux-headers` only as an optional dependency, never pulled automatically.

Effect: `openrazer-daemon` installs, the kernel module never builds, and the daemon exits on startup. Container evidence: `(5/5) Install DKMS modules` followed by `error: command failed to execute correctly`. This is not a playbook failure, which is why it went unnoticed, the play recap still reports success. Arch's `dkms` alpm hook ends in `return 0`, so a missing-headers build failure is reported as text on the console and never as a process exit code the playbook could catch. An install that cannot function is still a bug even when the playbook exits zero.

#### Arch libvirt and Docker fight over the iptables backend

Status: fixed, commit `890de1487721ac7643baae4a4277d64da1d86ab8` (2026-05-20), with a same-day follow-up fix.

Cause: on stock Arch, `libvirtd` starts with the legacy `iptables` firewall backend and writes its NAT rules through it. Installing Docker afterward pulls in `iptables-nft`, so the system's iptables provider becomes the nftables shim while the kernel namespace still holds libvirt's legacy rules. Docker's own NAT chain creation then hits a kernel state that is neither purely legacy nor purely nftables.

Effect: `iptables v1.8.13 (nf_tables): Could not fetch rule set generation id: Invalid argument`, and Docker fails to register its bridge driver. Fix: write `firewall_backend = "nftables"` to `/etc/libvirt/network.conf` and restart `libvirtd` before starting Docker, in [setup/ansible/roles/virtualization_config/tasks/main.yaml](../setup/ansible/roles/virtualization_config/tasks/main.yaml), so both daemons share one backend.

The same commit also added an explicit `community.general.modprobe` step for `nf_tables`, `nft_compat` and `br_netfilter` as a belt-and-braces measure. That addition broke the very next Arch run in commit `8aa5e2187e3f379d48369252ca6a20f1cb9f6b30` (2026-05-20), because [setup/setup.sh](../setup/setup.sh) runs `pacman -Syu` before Ansible starts, which can bump the kernel package mid-playbook. Pacman deletes the old kernel's `/lib/modules/<ver>/` once the new one lands, but the running kernel is still the old one until reboot, so `modprobe` could not even read `modules.builtin` and every module-load attempt errored out, and the rescue swallowed that error and skipped the Docker start task entirely, actively preventing the fix it was meant to protect. The modprobe step was also unnecessary, since `nf_tables`, `nft_compat` and `br_netfilter` are built into stock Arch kernels, not loadable modules, and Docker's own daemon-load already tolerates the module being absent. It was removed. Two lessons stack here, a fix that changes kernel state mid-run needs to account for a kernel upgrade that already happened in the same run, and a defensive-sounding extra step is still a regression if a rescue block can turn its failure into a silent skip of the real fix.

#### systemd-boot pointed at a kernel `apt autoremove` had already deleted

Status: fixed, commit `28b933e40e67e11d1cc4928ad3ca15fdd76d8e3a` (2026-05-20).

Cause: [setup/ansible/roles/systemd_boot/tasks/debian.yaml](../setup/ansible/roles/systemd_boot/tasks/debian.yaml) and the matching Fedora task captured the running kernel with `uname -r`, then referenced `/boot/vmlinuz-<kernel>` or `/lib/modules/<kernel>/vmlinuz` later as the kernel-install input. [setup/setup.sh](../setup/setup.sh) runs a full system upgrade before Ansible starts, which can install a new kernel package, and `apt autoremove` then strips the old kernel image from `/boot` once a newer one is present, while the running kernel stays the old version until reboot.

Effect: on Debian the referenced `/boot/vmlinuz-<old>` file could already be gone, failing kernel-install outright, and on Fedora the equivalent path could be missing if `installonly_limit = 1` is set. Even when the file was still present, pointing the boot loader at the outgoing kernel was the wrong target regardless, since the next boot loads whatever the package manager made current. Fix: probe the newest kernel actually on disk with `ls ... | sort -V | tail -1` instead of trusting the running kernel, at line 36 of the Debian task, with a `failed_when` on empty output so a genuinely empty `/boot` hard-fails instead of writing a broken loader entry. Arch's own task in [setup/ansible/roles/systemd_boot/tasks/arch.yaml](../setup/ansible/roles/systemd_boot/tasks/arch.yaml) was never affected, it uses static symlinks the kernel package updates atomically. This toggle defaults to false, so the bug was dormant rather than triggered, caught by audit rather than by a failed run.

#### The same DKMS failure is cosmetic on pacman and fatal on RPM

Status: not a defect, a real limitation, now suppressed for Fedora alone in [e2e/tier3/container_limits.fedora.yaml](../e2e/tier3/container_limits.fedora.yaml).

Cause: `openrazer-meta` pulls `openrazer-kernel-modules-dkms`, whose RPM `%posttrans` scriptlet runs DKMS against the running kernel. In a container that is the host's kernel, so no matching headers exist and the scriptlet exits 21. RPM treats a failed `%posttrans` as a failed transaction.

Effect: dnf batches the install, so a single unbuildable kernel module reported `syncthing`, `tailscale` and `chkrootkit` as not installed too, even though all three had unpacked successfully. The module's own message is only "Failed to install some of the specified packages", and verification's missing list therefore reads exactly like four bad package names. It is not: `openrazer-meta` is in the OBS repo's noarch directory and the Fedora 44 build exists, both checked, and installing it by hand in a plain Fedora container reproduces the scriptlet failure and nothing else.

Cross-check: identical DKMS failure on Arch, entirely harmless. Arch's `dkms` alpm hook ends in `return 0`, so pacman prints the error and succeeds, the package installs, and the run carries on. That difference is the point. A limitation that is invisible on one distribution can be fatal on another, and suppressing OpenRazer everywhere to satisfy Fedora would have discarded the Arch coverage that exists for the device group entry above. Container limits are therefore per distribution, with the shared file reserved for what no container can do at all.

#### Verification could not render the Debian dictionary at all

Status: fixed at the time. [e2e/tier3/verify.yaml](../e2e/tier3/verify.yaml) loaded `group_vars/versions.yaml` alongside the toggle files, matching what `site.yaml` did with it as a `vars_file`. Both playbooks now get the same pins from the pinned values vars plugin instead, so neither loads a versions file directly, but the requirement this fix established still holds: verification has to see the same pins the OS dictionaries template against.

Cause: the verify play loaded `all.yaml`, `linux.yaml` and the OS dictionary, and not the pinned versions the dictionaries template against. Debian maps appimagelauncher to `{ manager: apt_url, package: "{{ appimage_launcher_url }}" }`, so merely rendering `software_mapping` through `dict2items` raised `'appimage_launcher_url' is undefined`.

Effect: the first assertion in the play failed, so nothing about the Debian or Ubuntu runs was verified at all, on top of the playbook failure those runs already had.

Cross-check: Arch maps the same application to the AUR by name, with no URL to dereference, and so does Fedora, where it is commented out entirely and installed from `custom_installs.yaml`. Seven green Arch scenarios and one Fedora run therefore proved nothing about this. The general lesson is narrower than "test every distribution": a value that is a template in one dictionary and a literal in another will only fail where it is a template, and the OS dictionaries are exactly where that asymmetry lives.

#### Package and repository facts that only held for one distribution

Status: fixed, commits `aac857986b52a77f1dc19491c804592afb31d9ae` (2026-05-21) and `6e8913a7580940a918530c61ed4f9f5b3d5bb782` (2026-05-19).

A single cross-distro test pass on Debian, Ubuntu, Fedora and Arch (`aac857986b52a77f1dc19491c804592afb31d9ae`) turned up five distinct per-distro assumptions in one sitting: `ansible.builtin.command: command -v zsh` in [setup/ansible/roles/shell_zsh/tasks/install_zsh.yaml](../setup/ansible/roles/shell_zsh/tasks/install_zsh.yaml) failed on every distro because `command` is a shell builtin, not a binary Ansible's `command` module can execve, and needed to go back to `ansible.builtin.shell`. Ubuntu minimal images have no `git`, which pyenv's own bootstrap script hard-requires, so [setup/ansible/roles/system_core/tasks/base_utils.yaml](../setup/ansible/roles/system_core/tasks/base_utils.yaml) now installs it explicitly on all three Linux families even though Arch and Fedora usually pull it transitively. Arch's `snap install core` was running before `snapd.socket` was enabled in [setup/ansible/roles/arch_core/tasks/main.yaml](../setup/ansible/roles/arch_core/tasks/main.yaml), failing with "cannot communicate with server", fixed by reordering the tasks and adding a settle pause.

A separate version and URL audit (`6e8913a7580940a918530c61ed4f9f5b3d5bb782`) found that Arch's official pacman repository had dropped the `arduino` package entirely, requiring a switch to the Flathub `cc.arduino.IDE2` entry that Debian already used, and that the FreeCAD Flathub application ID had been renamed upstream and needed correcting in the Debian, Fedora and Arch dictionaries independently. Neither of these package facts generalised from one distribution to the others, and both were only caught by checking the live upstream source rather than trusting what had worked before.

#### Tailscale's apt repository URL assumed the distribution name was already the codename it needed

Status: fixed, commit `e6eff3e0cac5d96a56cab4e0d58c4ff777cd2551` (2026-08-13).

Cause: the Tailscale apt repository task built its URL from the raw `ansible_facts['distribution']` string, unlike the Docker CE task in the same file, [setup/ansible/roles/software_installer/tasks/debian_repos.yaml](../setup/ansible/roles/software_installer/tasks/debian_repos.yaml), which already normalised any Debian derivative down to `ubuntu` or `debian` before building its URL, since upstream only publishes those two paths.

Effect: a Debian derivative such as Linux Mint or Pop!_OS produced a 404 instead of degrading, because Tailscale's package host has no `linuxmint` or `pop` path. Fixed by applying the same normalisation the Docker task already used, now visible at lines 339 and 350 of the same file. The same commit also caught that the live USB profile never disabled Tailscale, so an ephemeral run added a repository and enabled a daemon on a session that could never join a tailnet, and that the manual install docs under [docs/manual/](manual/) had no Tailscale entry at all on any of the five operating systems despite declaring itself grouped exactly like the main software catalogue.

---

### Silent failure and error swallowing

#### Pacman batch failure marked as success

Status: fixed. The two-condition `failed_when` is gone from the pacman batch, so a could-not-find error fails the task as it should.

Cause: [setup/ansible/roles/software_installer/tasks/dynamic_install.yaml](../setup/ansible/roles/software_installer/tasks/dynamic_install.yaml) lines 207 to 210 give `failed_when` a two-item list, which Ansible combines with AND, not OR: `pacman_result.failed` and `'could not find' not in msg`. Any could-not-find error therefore marks the task `ok`.

Effect: one wrong package name anywhere in [setup/ansible/vars/Archlinux.yaml](../setup/ansible/vars/Archlinux.yaml) silently drops every single pacman package from the run while the playbook reports success end to end. This is latent rather than triggered, caught by reading the condition by hand rather than by a failing run, which is exactly why item 3 on the checklist above exists.

#### Install block rescue hides which task failed

Status: fixed. The rescue now names the failing task and what it cost, and sets `any_role_failed` so the run cannot exit zero over it. Both are visible in the Fedora smoke log, where "Install DNF packages (batched)" failed and the next two tasks read "Name the install step that failed and what it cost" and "Propagate the installer failure to the play summary".

Cause: [setup/ansible/roles/software_installer/tasks/dynamic_install.yaml](../setup/ansible/roles/software_installer/tasks/dynamic_install.yaml) lines 459 to 462 wrap the entire install block, apt, dnf, pacman, snap, Windows and custom installs together, in a single `rescue` that emits one anonymous line.

Effect: any failure inside the block prints `[WARNING] Some packages failed to install`, skips every remaining task in the block regardless of which package manager or OS it belonged to, and the play recap stays green. Nothing in the output says which task, which package, or which OS branch actually failed.

#### `playbook_succeeded` reported true regardless of what the rescue actually caught

Status: fixed, commit `dd07664d28c4ba1dcf6c6763b3ce4dc44637a6b9` (2026-05-19).

Cause: the fact that gates the post-run cleanup tasks was set with an unconditional `set_fact`, so it read true even when a role's rescue block had just caught a real failure. Effect: cleanup tasks such as removing the temporary sudoers grant ran the same way whether the run had actually succeeded or been silently rescued. Fixed by tracking `any_role_failed` from the rescue blocks themselves in [setup/ansible/site.yaml](../setup/ansible/site.yaml), so cleanup correctly distinguishes a rescued failure from a clean run.

#### A round of `ignore_errors` and always-true `changed_when` across a dozen roles

Status: fixed, commits `bf23f193898628070f337d7eccf9edd7e67bdb77` (2026-05-21) and an earlier pass in `20c6f615a354f252f2ca8be82da5eba92be076e1` (2026-04-14).

An audit found `ignore_errors: yes` scattered across [setup/ansible/roles/virtualization_config/tasks/main.yaml](../setup/ansible/roles/virtualization_config/tasks/main.yaml), the GRUB removal task, and a Flathub remote-add step, each one hiding whatever real failure the task might hit behind a guaranteed pass. The worst instance was in [setup/ansible/roles/shell_zsh/tasks/install_zsh.yaml](../setup/ansible/roles/shell_zsh/tasks/install_zsh.yaml): the `command -v zsh` probe had no guard against empty stdout, so a silent install failure could set a user's login shell to an empty string, an account lockout vector, not just a cosmetic bug. Three Debian apt tasks and the apt and flatpak batch installs also carried an always-true `changed_when`, meaning the play recap reported `changed` on every single run whether anything actually changed or not, masking the signal an operator would use to notice an install that silently did nothing. All replaced with real `failed_when` and `changed_when` conditions that parse the actual command output.

#### A spinner hid an Ansible Galaxy collection resolution failure for hours

Status: fixed, commit `6e8913a7580940a918530c61ed4f9f5b3d5bb782` (2026-05-19), with a companion fix in [setup/setup.sh](../setup/setup.sh).

Cause: [setup/ansible/requirements.yaml](../setup/ansible/requirements.yaml) pinned exact collection versions that had been invented rather than checked against Ansible Galaxy, for example `community.general:10.5.0` and `chocolatey.chocolatey:1.5.3`, neither of which exists as a real release. `ansible-galaxy collection install` failed to resolve them, but the install script wrapped that command in a `gum spin` loading animation that swallowed the command's own stderr.

Effect: the operator saw a spinner running for however long they waited, with no indication that the underlying command had already failed. Fixed two ways, the collection pins went back to bounded ranges that Galaxy can actually resolve, and `install_collections()` in [setup/setup.sh](../setup/setup.sh) stopped wrapping the call in `gum spin` so resolution errors stream to the console immediately.

#### MCP configuration silently loaded zero servers when one variable was unset

Status: fixed, commit `147759b72d37981c927e92e3da70275ab8884136` (2026-05-21).

Cause: [.mcp.json](../.mcp.json) referenced `CONTEXT7_API_KEY`, a Grafana token, and a SonarQube token with no default value. Claude Code fails to parse the entire file, not just the one server block, when any referenced environment variable is unset, so a project that had not set all three lost every configured MCP server with no error surfaced anywhere. Fixed by adding an empty-string fallback, `${CONTEXT7_API_KEY:-}`, still visible at line 8 of the current file. [opencode.json](../opencode.json) had the equivalent problem for a different reason, its `{env:VAR}` syntax has no default-value fallback at all, so unset variables produced empty URLs instead of a parse failure, fixed by hardcoding localhost defaults instead. [docs/MCP_SETUP.md](MCP_SETUP.md) documents the asymmetry between the two tools' handling of a missing variable.

---

### Wizard and toggle plumbing

#### Wizard toggle parse desync

Status: fixed in this change, in `setup/setup.sh`, function `read_boolean_toggles`.

Cause: `read_boolean_toggles` in [setup/setup.sh](../setup/setup.sh), lines 344 to 348, matches toggle lines with `grep -E '^[a-z_]+: (true|false)'`, which happily matches a line that carries a trailing `# comment`, then converts state with `sed 's/: true$/ ON/;s/: false$/ OFF/'`, which is anchored to the end of the line and therefore never fires on a commented line. `preload_toggles` then splits the result with `key="${entry%% *}"` and `val="${entry##* }"`, so the key kept its trailing colon and the state became the last word of the comment instead of `ON` or `OFF`.

Effect: 11 toggles on Linux and 4 more on macOS rendered as unchecked in the customise checklist with a stray colon in the label, and could not be controlled in either direction. The wizard emitted a line like `install_tailscale:=false`, a variable name that does not match the real toggle, which Ansible accepts silently and leaves the real value untouched. The profile picker's package count was also 11 too low. Affected toggles: `install_chatgpt`, `install_synapse`, `install_tailscale`, `install_stable_diffusion`, `install_hardinfo`, `install_lm_sensors`, `install_greenenvy`, `install_baobab`, `install_openrazer`, `install_polychromatic`, `install_gputest`, plus `install_stats`, `install_grandperspective`, `install_lulu`, and `install_balena_etcher` on macOS.

[setup/setup.ps1](../setup/setup.ps1) was never affected, its equivalent regex at line 582 is `^([a-z_]+): (true|false)` with no end anchor, so it matches the value regardless of a trailing comment. That asymmetry is itself the lesson behind item 5 on the checklist above, two implementations of the same parse drifted apart, and only one of them was ever tested against a commented toggle line.

#### Toggles enabled with no mapping and no task

Status: fixed, and mechanised. `putty` and `gradle` are mapped on every family that claims them, and [e2e/tier1/toggle_coverage.sh](../e2e/tier1/toggle_coverage.sh) now fails the gate for any enabled toggle that resolves to neither a mapping nor a consumer, per OS family, with intended no-ops listed in [documented_no_ops.txt](../e2e/tier1/documented_no_ops.txt) and stale entries flagged too.

`install_putty: true` in [setup/ansible/group_vars/linux.yaml](../setup/ansible/group_vars/linux.yaml) line 37 has no mapping in [setup/ansible/vars/Archlinux.yaml](../setup/ansible/vars/Archlinux.yaml) or [setup/ansible/vars/RedHat.yaml](../setup/ansible/vars/RedHat.yaml), even though `putty` is present in Arch's `extra` repository and in Fedora's repositories, both verified directly.

`install_gradle: true` in [setup/ansible/group_vars/all.yaml](../setup/ansible/group_vars/all.yaml) line 17 has no mapping on Debian or Fedora. Both [setup/ansible/vars/Debian.yaml](../setup/ansible/vars/Debian.yaml) and [setup/ansible/vars/RedHat.yaml](../setup/ansible/vars/RedHat.yaml) carry a one-line comment claiming SDKMAN handles it, but [setup/ansible/roles/sdk_manager/tasks/sdkman_unix.yaml](../setup/ansible/roles/sdk_manager/tasks/sdkman_unix.yaml) only ever installs Java. Gradle was never installed on either OS and the comment was false. Arch, by contrast, does map it correctly to `pacman` at line 11 of its dictionary.

Effect: the user enables the toggle, the run reports success, the software is absent, on the two operating systems where the comment lied. The lesson behind item 4 on the checklist above is that a comment claiming another role handles something is not implementation, only a task file that actually runs is.

#### A selective-update script force-added agent paths a project never had

Status: fixed, commit `f056d3a76778aca06e411ec84865e4467fe76dfc` (2026-06-25).

Cause: the update commands documented for consumer projects looped over every known agent integration path, `.github/agents`, `.opencode/plugin`, `.kilocode/rules`, assuming all of them existed. A project that had imported this repository's agent tooling before one of those tools existed had none of that path on disk. Effect: the skills loop, subagent loop, and adapter refresh either errored outright or force-added paths that path never asked for. Fixed by skipping any agent path not present locally, in both the bash and PowerShell variants of the update command, the same two-implementation risk called out in item 5 of the checklist above.

#### Toggles that had already been dead for a while

Status: fixed, part of commit `8b32a1e9d42a36385e2b8528f48a0ed08b3b29fa` (2026-05-21).

A cross-check of every toggle in `group_vars/all.yaml` and `group_vars/linux.yaml` against the per-OS install paths in `vars/{OS}.yaml` found four toggles with zero working install path on any operating system, `install_trello`, `install_exodus`, `install_intellij`, and `install_teams`, while still appearing ticked in the wizard checklist. `install_trello` defaulted to true but every OS dictionary had it commented out as unavailable, so the wizard ticked a box that could never do anything. This is the mirror image of the toggle-with-no-mapping entry above, here the toggle, its profile overrides, its version variables, and its documentation references were all purged together so the operator's checklist only shows software the playbook will actually install.

---

### Package naming and availability drift

#### Windows winget product IDs that stopped resolving

Status: fixed, commit `e8eef3894430cb72d2eaf1beb7336b5d07d12b63` (2026-06-01).

Google's Antigravity IDE rebrand moved the product from `Google.Antigravity` to `Google.AntigravityIDE`, leaving the old ID pointing at a different product entirely. `Ookla.Speedtest` did not exist in winget-pkgs at all, only `Ookla.Speedtest.CLI` did, so the install failed with "No package found". NVIDIA discontinued GeForce Experience in favour of the NVIDIA App, which has no winget or Chocolatey manifest, so the toggle was flipped to false rather than left pointing at a dead package. All of this lives in [setup/ansible/vars/Windows.yaml](../setup/ansible/vars/Windows.yaml).

#### Microsoft Store product IDs need an explicit source or they abort the whole batch

Status: fixed, commit `ae24205998893843b3e02d652964c69a2b3e7125` (2026-08-09).

Cause: five Store product IDs in [setup/ansible/vars/Windows.yaml](../setup/ansible/vars/Windows.yaml) carried no `source` field, so the winget task fell back to the default winget source, where a bare Store ID returns exit 20, "no package found". Because the winget loop runs inside the same install block described in the rescue entry above, the first failure dropped the whole block into the rescue handler and silently skipped every remaining package, including one added in the same round of commits. All six enabled toggles hit this. Verified directly on Windows 11: `winget show --exact --id <id> --source winget` fails for all six IDs while `--source msstore` succeeds for five of them. The sixth, Razer Cortex's `9PK9W5QV2PKX`, resolves on neither source and no Store search matches the name, so that mapping was removed entirely rather than left to abort the batch.

#### Two Ansible module names that never resolved at all

Status: fixed, commit `ddfe050d8bfb053d58e4e752a82da632ec2acdeb` (2026-06-02).

`community.windows.win_winget` does not exist in any installed collection, `community.windows` only ships `win_scoop`, and there is no such module in `ansible.windows` either. Confirmed with `ansible -m <fqcn>` returning "Cannot resolve to an action or module". `roles/software_installer/tasks/windows_winget.yaml` was rewritten to drive the winget CLI directly through `ansible.windows.win_shell`, resolving the real `winget.exe` path out of the DesktopAppInstaller package because the App Execution Alias is not on PATH in a non-interactive WinRM session. That file has since been deleted with the rest of the unreachable Windows Ansible, and the same `winget.exe` resolution now lives in `Get-WingetPath` in [setup/windows/WindowsSoftware.ps1](../setup/windows/WindowsSoftware.ps1), for the same reason. `community.windows.win_chocolatey` had the same problem, the module actually lives in `chocolatey.chocolatey`, already a declared dependency, with no redirect in `community.windows` 2.x. The same commit also caught that the Windows FVM task had been installing a non-existent `Google.Flutter` winget package, rewritten to install FVM through Chocolatey instead, which is the route `Install-FlutterViaFvm` in [setup/windows/WindowsCustomInstalls.ps1](../setup/windows/WindowsCustomInstalls.ps1) still takes.

---

### Concurrency and shared state

#### Parallel SDKMAN Java installs race on shared registry state

Status: fixed, commit `744bf443e41f02c2b6a63e7177bd19683aa2e760` (2026-05-19).

Cause: SDKMAN's `sdk install` writes to shared state without any locking, `~/.sdkman/etc/config`, the candidate metadata cache under `~/.sdkman/var/`, the active-version pointer, and its own installed-candidates registry. Running four `sdk install java <version>-tem` invocations concurrently, one per Temurin version this playbook installs, let those writes interleave.

Effect: a follow-up run failed at "Set default Java via SDKMAN" with "java 21.0.11-tem is not installed on your system", even though the parallel install task had just reported all four JDKs as installed. The on-disk extract under each candidate's own directory usually succeeded, but SDKMAN's own view of what was installed lost entries. Fixed by reverting to a serial `loop:` in [setup/ansible/roles/sdk_manager/tasks/sdkman_unix.yaml](../setup/ansible/roles/sdk_manager/tasks/sdkman_unix.yaml), the rationale is documented directly in the comment above the task at lines 17 to 22 of the current file. Pyenv stayed parallel deliberately, each pyenv install writes to its own isolated `~/.pyenv/versions/X.Y.Z/` directory with no shared state file, so the same race does not apply there. The wall-clock cost is roughly 10 minutes on a fresh box versus 5 minutes parallel, accepted as the price of a registry that stays coherent.

---

### Timeouts and interactive stalls

#### FVM's interactive picker stalled a run for 8 hours with no signal

Status: fixed, commits `cd733f381244eb2a19a214eee457007fa21e8439` and `2e11e3e050b4d71b27d815524a2cf04b37b82f74` (both 2026-05-20).

Cause: FVM 3.2 and later, `fvm global` with no arguments enters an interactive terminal picker when no global Flutter version is set yet. The read-probe task in `fvm_unix.yaml` ran that command with stdin left open, inheriting the Ansible controller's non-TTY pseudo-terminal, so the picker blocked waiting for a keystroke that could never arrive.

Effect: a real Ubuntu run hung for 8 hours on "Read current FVM global channel", with the heartbeat logger emitting "still working, log unchanged" every 5 minutes for 490 minutes before anyone noticed. Fixed first by closing stdin with `</dev/null` and adding a hard timeout, then cleaned up the same day once the numbers turned out sloppy, the actual work is a sub-second config-file write with no network involved, so a follow-up commit deleted the read-probe entirely, ran the set task unconditionally since FVM is idempotent on its own, and capped the whole thing at 10 seconds as a safety net rather than a real wait budget, visible at line 160 of [setup/ansible/roles/sdk_manager/tasks/fvm_unix.yaml](../setup/ansible/roles/sdk_manager/tasks/fvm_unix.yaml) today. Every other read-only shell-out in the SDK manager role, npm, pyenv, SDKMAN's own `sdk default`, was audited in the same commit and confirmed non-interactive, so this fix stayed scoped to FVM alone.

#### A synchronous long task blocked the controller with no signal it was even alive

Status: fixed, part of commit `8b32a1e9d42a36385e2b8528f48a0ed08b3b29fa` (2026-05-21).

A Flatpak batch install once hung silently for roughly an hour, the synchronous task blocked the whole controller and the progress logger had no way to emit anything because it only reacted to task-lifecycle events, not to activity inside a still-running task. Applied across every long-running task in the playbook after that, pyenv compiles, SDKMAN downloads, JetBrains IDE downloads, AUR builds, the `oh-my-zsh` bootstrap, and the FVM install itself, all now redirect stdin from `/dev/null`, run under `async` with `poll`, and carry `retries` for transient network blips, the pattern documented in [setup/ansible/callback_plugins/dual_logger.py](../setup/ansible/callback_plugins/dual_logger.py). The heartbeat now tails the relevant log file and emits a line whenever it actually changes, plus an idle ping after 5 minutes of silence, so a stuck task and a slow one no longer look identical on screen.

---

#### The AUR metadata endpoint refused one package and took the whole run with it

Status: fixed, 2026-08-24, in [setup/ansible/roles/software_installer/tasks/dynamic_install.yaml](../setup/ansible/roles/software_installer/tasks/dynamic_install.yaml).

Cause: the AUR install loop asked paru for google-chrome and got `error sending request for url (https://aur.archlinux.org/rpc): channel closed`, which is the metadata query paru makes before it builds anything, so nothing was ever compiled. aur.archlinux.org rate-limits that endpoint per source address, and a hosted CI runner shares its address with every other tenant on that cloud range, so the window in which it refuses can outlast a short retry budget. The task did retry, three attempts thirty seconds apart, and ran out.

Effect: the `kde-full` cell on Arch went red in sweep 32703419920 while the other forty-seven cells passed, including `defaults` on the same distribution in the same sweep. The nine other AUR packages in the same loop, brave, lens, vscode, sublime, antigravity, teamviewer, appimagelauncher, chkrootkit and gputest, all built within the next six minutes.

What was not wrong: the reporting. The play refused to exit zero, the missing package was named in the terminal summary and in the error log, and `verify_install.yaml` caught it independently with `FAIL native packages missing: google-chrome`. Nothing was swallowed, which is why this entry exists at all rather than a silent green run.

Fix: the retry budget rose from three attempts across one minute to five across four. The delay is only ever paid by a package that has already failed, so a clean run costs nothing extra. Nothing about `failed_when` changed, because a package that genuinely will not build still has to fail the run.

Measured rather than assumed, because the log timestamps could not distinguish a retry that fired from one that never did: a task with the same shape, a loop plus `async` plus `failed_when: false` plus `until` on rc, run against `/bin/false`, emits `FAILED - RETRYING` the full count for every item. So `until` reading rc does survive `failed_when: false`, which is what the comment beside the task claims.

---

#### A deletion at the end of a function took the function's return with it

Status: fixed, 2026-08-24, in [setup/windows/WindowsCustomInstalls.ps1](../setup/windows/WindowsCustomInstalls.ps1), guarded by [e2e/tier1/windows_phase_contract.sh](../e2e/tier1/windows_phase_contract.sh).

Cause: commit `fef5e56` removed the Razer Cortex block from the end of `Invoke-WindowsCustomInstall`, and the function's own `return [PSCustomObject]@{ Results = ...; Installed = ...; Present = ...; Failed = ... }` sat immediately after it. Both went. The function then fell off its own end and handed the caller nothing.

Effect: `setup.ps1` reads `$r.Results.Count` off that return, and every PowerShell file here sets `Set-StrictMode -Version Latest`, where reading a property an object does not carry is a terminating error rather than an empty value. So the wizard died with "The property 'Results' cannot be found on this object", after the software phase had installed everything correctly and before the settings phase ran at all. Every Windows cell of sweep 32703419920 failed that way, and the message points at the reporting code rather than at the deletion two files away.

Why nothing caught it: the file still parses, PSScriptAnalyzer has no rule for a function that returns nothing, the Pester suite never calls that function because it shells out to real installers, `powershell_variables` asks about variables rather than return values, and the tier 1 gate passed 146 assertions over the broken tree twice.

Fix: the return is back, and a tier 1 check now asserts for every Windows phase function that it ends on an explicit return with nothing but blanks and comments after it, and that the union of properties across its return paths covers every property `setup.ps1` reads off the variable it is assigned to. The required list is read out of the caller rather than written into the check, so it cannot fall behind. Proven against the defect before being trusted: it fails on the tree without the return and passes with it.

The general lesson, which is item 17 of the checklist above in spirit: when you delete a block at the end of a function, look at what was underneath it. An editor selection that ends at a closing brace is one line away from ending at the wrong closing brace.

---

#### Verification failed packages the installer had correctly refused to install

Status: fixed, 2026-08-24, in [setup/windows/WindowsSoftware.ps1](../setup/windows/WindowsSoftware.ps1) and [setup/windows/WindowsVerify.ps1](../setup/windows/WindowsVerify.ps1).

Cause: three mapping keys say a package cannot install on some machines. `client_only` for a vendor who ships client editions of Windows only, `user_context` for an installer that refuses an administrator context, and now `requires_nvidia_gpu` for graphics software with no adapter to drive. The install phase honoured the first two and skipped with the reason. The verification knew about none of them, asked the package manager whether the package was installed, was told no, and reported it MISSING.

Effect: the wizard would have exited non-zero on a machine where it had behaved correctly, and blamed itself for an absence it had just explained. It went unseen because no Windows cell had reached the verification phase since those two keys were added: the sweep before this one failed in the software phase, and this one crashed between phases on the missing return above.

The third key came from `nvidia_app`, which failed the `all apps` and `default apps` cells with `choco exited -436207616`. The NVIDIA App is the driver and GPU control centre, and a hosted Windows runner is an Azure virtual machine with no NVIDIA adapter. The skip is conditioned on the measured answer rather than on the runner being CI: `Win32_VideoController` is asked for adapters whose name matches NVIDIA, and only an empty answer skips. On the development machine that query returns `NVIDIA GeForce RTX 2080`, so nothing is skipped there and the package installs as before.

Fix: one verdict, `not applicable`, decided from the same three machine facts in both phases, excluded from the requested count and named on its own line in the report so a reader sees which packages were refused and why. The three facts are asked once per run through helpers in `WindowsSoftware.ps1`, which `setup.ps1` dot-sources before the others precisely so they can share it.

A defect found while measuring rather than by reasoning, and worth its own line: `return @($list)` does not survive assignment. PowerShell unrolls a one-element array on output, so `$a = Get-NvidiaGraphicsAdapter` binds a bare string on a machine with exactly one adapter, and `.Count` on a string is a terminating error under `Set-StrictMode -Version Latest`. The first run of the new probe on a real machine failed exactly that way. Every call site now wraps the call in `@( )` rather than trusting the function's own.

---

#### One flatpak fetch timing out cost twenty container cells everything

Status: fixed, 2026-08-24, in [setup/ansible/roles/software_installer/tasks/dynamic_install.yaml](../setup/ansible/roles/software_installer/tasks/dynamic_install.yaml).

Cause: the flatpak installs were two batched tasks, one for Debian through `raw` and one for Arch and Fedora through `community.general.flatpak`. A batch is a single call, so a single failure anywhere in it fails all of it.

Effect: on sweep 32723213808, twenty of the forty-eight container cells failed, and every one of them failed on the same line:

```text
error: While fetching https://dl.flathub.org/repo/summaries/34abf2ee91b7a0b429589ec611bf1bd6fe9836088b12fb7717ce149b143494bd.gz: [28] Timeout was reached
```

curl error 28 is a timeout. One fetch of one 1.6 MB file. It cost twenty-two applications per cell, abandoned every task after it in the software installer, and made the verification refuse the run. The same URL, measured by hand while the sweep was still running, answered 200 with 1,644,604 bytes in 0.29 seconds, so Flathub was up and what failed was one fetch from one runner.

Worth recording that the first diagnosis was wrong and how. `https://dl.flathub.org/repo/summary` answered 503 from the development machine, which looked like confirmation that Flathub was down. It was not: that path is not what the client fetches any more, Flathub having moved to `summary.idx` plus `summaries/<digest>.gz`, and a 503 on a path nobody serves says nothing at all. Reading the URL out of the failing log and fetching that exact URL is what settled it. Measure the thing the failure names, not something adjacent to it.

Fix: one application at a time, with per-application retries, per-application reporting, and no failure that abandons the set. The batch had no justification in the first place. apt, dnf and pacman have to be batched because their solvers work on the whole set, and a per-package loop asks them to solve the same graph N times. A flatpak application is an independent download of an independent bundle, so batching bought only the seconds flatpak spends starting up.

The identical argument had already been written into this same file two days earlier, for Homebrew casks: "a cask is an independent download and install, and looping costs only the seconds brew spends starting up". It was not carried across to flatpak, which is the whole reason this entry exists. When you find that a batch was the wrong shape for one manager, check every other manager in the same file before closing the change.

Two collectors came with it, mirroring what the AUR path already does: the rc of every item is read, and flatpak is then asked with `flatpak list --system --app --columns=application` which applications are actually present. An install that exits zero and leaves nothing behind has happened three times on the AUR side, and there was no reason to assume flatpak was immune.

---

#### The four the Windows all-apps cell named once it could run to the end

Status: all four fixed, 2026-08-24. Found by sweep 32739529615, which is the first sweep where the Windows wizard reached its own verification instead of dying between phases.

Worth stating why they appeared together. The two sweeps before this one failed in the software phase and then on a deleted function return, so nothing downstream of the software phase had run since those defects were introduced. A run that cannot finish cannot tell you what else is wrong, which is why "the wizard now reports every phase" was worth more than it looked.

Razer Synapse exited -1 through Chocolatey while maven and vmware-workstation-player either side of it in the same batch exited 0, so the batch was not the problem. razer.com/synapse-4 states its operating system support as "Windows 11 x86-64, Windows 10" and names no Server edition, which is the same evidence that settled MiniTool Partition Wizard, so the mapping carries `client_only: true` and the wizard reports it skipped on a Server runner with that reason.

Tor Browser was reported installed after 36 seconds and then reported MISSING by the verification eight minutes later. Both were right. Its winget manifest is `Scope: user` with `DefaultInstallLocation: Desktop\Tor Browser` and declares no `AppsAndFeaturesEntries`, so it registers nothing in Programs and Features and `winget list --exact --id` has nothing to correlate against, however well it installed. A verdict of MISSING for a package that cannot be listed is a false negative, and softening it to unverifiable would have been worse: it would hide a genuine absence too. So the mapping gained `verify_path`, an optional second question asked only when winget cannot answer, and for this package the path is the one the vendor's own manifest documents.

That key came with a trap worth recording. Two parsers read `vars/Windows.yaml`: Ansible, which unescapes a double-quoted YAML scalar, and the PowerShell reader, which takes the raw text between the quotes. A path written with backslashes therefore arrives as one character in one and two in the other, measured, with `Test-Path` answering false against `C:\Users\Lukk\\Desktop\\Tor Browser`. A single backslash cannot be written either, being an invalid YAML escape. Forward slashes are what both parsers agree on, and Windows accepts them in a path, so the value carries no backslash at all and a Pester test now fails if one appears.

nvm-windows installed and was invisible to the process that had just installed it, so the wizard reported "nvm is not on PATH, rerun the wizard once" for both `nvm install lts` and `nvm use lts`. Telling the operator to run it again is the wizard giving up. The cause is that nvm-windows writes NVM_HOME and NVM_SYMLINK and then puts them into PATH by name, so refreshing PATH alone leaves an entry the process cannot expand, and `Update-ProcessPath` refreshed PATH alone. Two belts now: the whole machine and user environment is copied into the process before PATH is rebuilt, so a reference inside PATH can resolve, and nvm.exe is located explicitly under NVM_HOME, %APPDATA%\nvm and %ProgramData%\nvm and invoked by absolute path. If it is in none of them, that is now a named failure listing where it looked, not advice to try again.

Gridcoin exited 0 and left nothing at the directory the proof checked. The default install directory could not be read out of the binary: the installer is NSIS, confirmed by finding `Nullsoft.NSIS.exehead` in the file, and its script block is compressed in a form neither deflate nor LZMA would open here with no unpacker available. Rather than guess the vendor default, the installer is now told where to install, which makes the directory the proof checks the directory that was chosen. From the NSIS documentation, chapter 3: "/D sets the default installation directory ($INSTDIR), overriding InstallDir and InstallDirRegKey. It must be the last parameter used in the command line and must not contain any quotes, even if the path contains spaces. Only absolute paths are supported."

The quoting rule in that quote is a real hazard, since the chosen path contains a space and argument builders like to quote those. Measured on pwsh 7.6.5 rather than assumed: `Start-Process -ArgumentList @('/S', '/D=C:\Program Files\Gridcoin')` reaches the child as `/S /D=C:\Program Files\Gridcoin` with no quotes, byte for byte identical to building the command line by hand through `ProcessStartInfo.Arguments`. So the array form is safe and no raw-string escape hatch was needed.

---

#### An array splat made the manual Windows dispatch impossible to use

Status: fixed, 2026-08-24, in [.github/workflows/e2e-manual.yaml](../.github/workflows/e2e-manual.yaml), guarded by [e2e/tier1/powershell_splat.sh](../e2e/tier1/powershell_splat.sh).

Cause: PowerShell has two splat forms that read identically and behave differently. A hashtable splat binds by name. An array splat supplies positional arguments, with the leading dashes still attached to the strings, handed to the parameters in declaration order. The step built an array.

Effect: run 32762695978 died sixteen seconds in, before the wizard did anything, with an error naming a parameter nobody had passed:

```text
Cannot validate argument on parameter 'Software'. The argument "-AllowAdministrator" does not belong
to the set "defaults,all,none" specified by the ValidateSet attribute.
```

"-NonInteractive" went to `$Profile` and "-AllowAdministrator" went to `$Software`, which carries a ValidateSet, so the message pointed at neither of the two switches actually involved.

Reproduced in one command rather than reasoned about, against a scriptblock with the same parameter block: the array form raises that exact error and the hashtable form binds correctly.

Why it survived: this is the manual single-platform workflow, and 2026-08-24 was the first time anybody dispatched it at its Windows target. `e2e-matrix.yml` passes its arguments inline, so every Windows cell of every sweep stayed green over a dispatch path that could never work. A defect in a path nothing exercises is invisible until the day you need that path, which was the day four Windows fixes needed verifying without a three hour sweep.

Fix: a hashtable, plus one thing the array form had also been getting wrong silently. `EnableKey` and `DisableKey` are `[string[]]` in the wizard and comma separated in the workflow input, so the value is split now: passing "a,b" as one element would have reached the wizard as a single key named "a,b", matching no toggle.

The check that now guards it reads the workflow YAML as well as the PowerShell files, because a workflow step is where this one lived and an abstract syntax tree cannot reach into a YAML string.

---

#### A sixty minute ceiling on a hundred minute install, reported as a cancellation

Status: fixed, 2026-08-24, in [.github/workflows/e2e-manual.yaml](../.github/workflows/e2e-manual.yaml), guarded by [e2e/tier1/workflow_timeouts.sh](../e2e/tier1/workflow_timeouts.sh).

Cause: the Windows job in the single-platform workflow carried `timeout-minutes: 60`. Every Windows cell in the sweep carries 150 for the identical run, and on the same day that identical run took 94 minutes for `Windows all apps` and 100 for `Windows default apps`. Sixty could never have been enough for the software mode that workflow defaults to.

Effect: run 32763779284 was killed at 60 minutes and 32 seconds while still installing, and GitHub reported the run as `cancelled`.

That reporting is the reason this gets its own entry rather than a one line fix. A cancelled run carries no error, no failing step and no log tail to read, so it looks exactly like somebody pressing a button. The only tell is a duration sitting suspiciously close to a round number, and the way to confirm it is to compare the job's start and end timestamps against its declared ceiling. Both of the two failures in a row on this workflow, the array splat before it and this, produced messages that pointed away from the cause.

Fix: 150, matching the sweep, with the reason and the measured durations written beside it. The check now compares the largest ceiling among the sweep's install jobs for a platform against the smallest in the single-platform workflow and fails when the latter is lower. Install jobs are told from plan jobs by their runner and a ceiling of at least thirty minutes rather than by name, so a job added to either workflow is covered without anybody remembering to list it.

The general shape, which is the third instance of it today: an entry point nothing exercises rots quietly. The sweep stayed green over a manual dispatch path whose argument binding could never work and whose timeout could never fit, and both were found within an hour of the first time anybody used it.

---

#### The runner filled, and only the last line of the job said so

Status: fixed, 2026-08-24, in [.github/workflows/e2e-manual.yaml](../.github/workflows/e2e-manual.yaml), guarded by [e2e/tier1/workflow_parity.sh](../e2e/tier1/workflow_parity.sh).

Cause: a `windows-latest` runner ships roughly 20 GB of preinstalled toolchains this project never touches. Every Windows cell in the sweep deletes them before installing anything. The single-platform workflow never had that step.

Effect: run 32770609386 filled the disk 65 minutes in with 81 packages to install. From that point winget failed every remaining package with the same line:

```text
failed after 1s: exit -2147009284. An unexpected error occurred while executing the command:
 0x80073cfc : The application cannot be started. Try reinstalling the application to fix the problem.
```

Six packages in a row reported that, and the real cause appeared exactly once, in the last line of the job:

```text
##[error]There is not enough space on the disk. : 'C:ctions-runner\cached.336.0\_diaglocks\...'
```

A reader who stopped at the first error would have gone hunting for a broken package or a bad MSIX. `0x80073cfc` is an APPX activation failure, which reads like the package's fault and is not.

Fix: the sweep's cleanup step, taken verbatim rather than retyped so the two cannot drift in what they delete, plus the artefact upload the job also lacked. That second omission is why reading this failure took four attempts through three API routes: `gh run view --log-failed` returned nothing, `gh run view --log` stopped before the wizard step, and the jobs logs endpoint refused to print until told the output contains terminal escape sequences.

This is the third defect of the same shape in one evening, and the reason the guard is a parity check rather than a third one-off fix. All three were in the single-platform workflow, all three were things the sweep already did correctly, and all three were found within two hours of the first time anybody dispatched that workflow at its Windows target. The lesson is not about disk space: it is that a second entry point to the same work drifts silently until somebody uses it, and the only defence is a check that compares the two rather than trust that whoever edited one edited both.

The check compares capability rather than text, since the two files may word a step however they like. Every action the sweep's install jobs use must be used by the single-platform job, and if the sweep frees disk space so must the single-platform job, detected by the paths a step deletes rather than by its name so a renamed step still counts and a step renamed to look like a cleanup while deleting nothing does not.

---

#### The install phase installed what the verification called not applicable

Status: fixed, 2026-08-25, in [setup/windows/WindowsSoftware.ps1](../setup/windows/WindowsSoftware.ps1), [setup/windows/WindowsVerify.ps1](../setup/windows/WindowsVerify.ps1) and [setup/ansible/vars/Windows.yaml](../setup/ansible/vars/Windows.yaml).

Two defects, found together on run 32778481303, the first Windows run of the day that got all the way to its own verification.

The first is the shape this repository keeps paying for. Three mapping keys say a package cannot run on a machine, and each phase decided from them separately. The winget loop honoured all three. The Chocolatey path honoured only `requires_nvidia_gpu`, added a day earlier and never extended to the other two. The verification honoured all three. So a Chocolatey package carrying `client_only` was installed by one phase and declared not applicable by the other, in the same run, and the run passed:

```text
choco exited 0 for razer-synapse-4
synapse                        not applicable choco: razer-synapse-4
```

The second is that the flag was wrong anyway. razer.com/synapse-4 lists its operating system support as "Windows 11 x86-64, Windows 10" and names no Server edition, which looked like the same case as MiniTool Partition Wizard. It is not. On this run the Chocolatey package installed on a Windows Server runner and exited 0, pulling RazerAppEngine, Synapse 4, Chroma, Central and GameManager. The exit -1 that prompted the flag came from the run whose disk filled, which is a different fault entirely.

That is worth stating as a rule: a vendor support matrix says what the vendor will support, not what the installer refuses to do. Partition Wizard was right because its installer returns Inno Setup exit 1 before it starts. Synapse was wrong because nothing was ever measured refusing.

Fix: one function, `Test-WindowsPackageSkip`, decides from one set of machine facts, and all three callers ask it. The verification now reads none of the three keys itself. Exercised on both machine shapes rather than reasoned about. On this development machine, which is Client, not elevated, with one NVIDIA GeForce RTX 2080, every package installs. Against the runner's shape, Server, elevated, no adapter:

```text
synapse            installs on a Server runner
nvidia_app         SKIP: this is NVIDIA graphics software and Win32_VideoController...
partition_wizard   SKIP: the vendor ships this for client editions of Windows only...
spotify            SKIP: its installer refuses to run from an administrator context...
chrome             installs on a Server runner
```

Six Pester tests cover it, including a mapping carrying none of the optional properties, which is the shape that crashes under `Set-StrictMode -Version Latest` when a property is read without a guard.

---

#### Batching to save time does not survive measurement

Status: measured 2026-08-25. Homebrew formulae now loop, and the reasons in [e2e/tier1/batched_managers_allowed.txt](../e2e/tier1/batched_managers_allowed.txt) were rewritten because the ones written a day earlier claimed a benefit that is not there.

The claim under test was mine: that apt, dnf and pacman earn their batch because the solver runs once instead of N times and because the trigger phase, rebuilding the manual page index and the desktop and icon caches, runs once per transaction rather than once per package.

Measured in `debian:trixie`, twenty-two packages taken from the real Debian mapping, `apt-get update` run in both and not timed, two samples each way, plus one pair with recommends on a desktop-heavy subset where the trigger phase does the most work:

```text
set A, 22 packages, no recommends       batched 250s and 199s      looped 278s and 244s
set B, 7 desktop packages, recommends   batched 274s               looped 264s
```

Both shapes of set A ended with the same 701 packages installed, and both shapes of set B with the same 952, so the end state is identical and only the route differs.

Looping cost 11 and 23 per cent on set A and saved 4 per cent on set B. Two identical batched runs of set A differed from each other by 20 per cent, which is the same size as the effect being measured. In absolute terms the largest difference was 45 seconds inside a container scenario that runs for thirty to a hundred minutes, so at the most favourable reading batching is worth about two per cent of a cell.

The trigger argument in particular did not show up. Set B is where it should have been largest and it was the set where looping was faster.

So the time argument is dead and the allowed file no longer makes it. What remains, and what the measurement deliberately does not test, is correctness: every package in that set had a satisfiable dependency closure, so the solver was never asked to choose between conflicting constraints. That is the case where a loop genuinely differs from a batch, by picking a library version for one package that the next cannot accept, or by choosing a provider per package where the providers conflict. The CachyOS `lib32-vulkan-driver` chain recorded in [the arch_core alignment task](../setup/ansible/roles/arch_core/tasks/main.yaml) is exactly that shape.

The three package managers stay batched for that reason alone, written down as such. Anyone reaching for a batch to save time should read this entry as a no.

---

#### Nothing batches any more, and the guard moved to where the risk actually is

Status: done, 2026-08-25, at the owner's decision. apt, dnf and pacman were the last three and they now install one package per call, like every other manager in [dynamic_install.yaml](../setup/ansible/roles/software_installer/tasks/dynamic_install.yaml).

Why the last three went. Two arguments had kept them, and neither survived contact with the owner's question, which was simply how much time batching actually saves.

The speed argument was measured the same day and is recorded in the entry above this one. At best about two per cent of a container scenario, inside run-to-run noise of the same size.

The correctness argument was real and is the interesting half. A single solve cannot pick a library version, or a provider for a virtual package, that a later package then rejects. A loop can. The owner's answer was that this is a job for a guard rather than for a batch, and that is right for a reason worth writing down: a batch does not detect a contradiction, it prevents you from ever asking. When one did occur, all it produced was one failure with no way to tell which package caused it, which is exactly how one bad package name silently dropped every pacman package from a run while the play stayed green.

So each family now asks its own package manager, after the installs, whether the set it produced is coherent, and names what is broken when it is not:

```text
apt-get check
dnf check --dependencies
pacman -Dk
```

All three are read-only and take about a second. Each is followed by a task that records the failure in the play summary so the exit code reports it, and by a message that says what the state means and what to do about it. For pacman that message names the specific fix, which is to name the provider you want in the OS dictionary rather than the virtual package, because the CachyOS `lib32-vulkan-driver` chain in [the arch_core alignment task](../setup/ansible/roles/arch_core/tasks/main.yaml) is exactly that shape.

What else came out with the batches. Every per-manager install now reports per package: which ones failed, what the manager said about each, and a play summary entry marking the run failed. dnf and pacman moved off their native modules onto `command` in the process, not for the installing but for the reporting, since those modules report failure only through the result's `failed` key that this repository forbids reading. And the collector that used to work out which batch had failed, by matching the word "batched" in a task name, was deleted: nothing carries that word now and a dead collector is a shape already shipped twice here.

The tier 1 check lost its allowlist along with its last entry. There is no longer a file listing managers permitted to batch, because a file of exceptions is an invitation to add the next one.

---

#### A queued sweep that was not waiting for runners, and said nothing about it

Status: understood and worked around, 2026-08-25. Not a defect in the tree, a trap in how the sweep is
dispatched, and it cost about twenty minutes before anybody asked the right question.

The final sweep was dispatched while an earlier idempotency run still had two Windows install cells
open. It sat at `pending` with no jobs at all, and the watcher reported the only thing it could see:

```text
CHECK: 0 passed, 0 failed, 0 running, 0 queued
```

That reads exactly like a slow start. It was not. [e2e-matrix.yml](../.github/workflows/e2e-matrix.yml)
carries a concurrency group:

```text
concurrency:
  group: e2e-matrix-sweep
  cancel-in-progress: false
```

Both runs are the same workflow, so they share that group, and `cancel-in-progress: false` means a
second run waits for the first to finish entirely rather than replacing it or competing for runners.
The blocking cells had a 150 minute ceiling, so the new sweep would have waited up to two and a half
hours before starting its own three.

What makes this worth an entry rather than a shrug is that nothing in the run's own state says so. A
run blocked by a concurrency group and a run waiting for a busy runner pool look identical from the
jobs API: no jobs, no queue, `pending`. The only way to tell is to read the workflow for a
`concurrency:` key and then look at what else is open in that group.

What to do about it, in order. Before dispatching a sweep, check whether another run of the same
workflow is open. If one is, decide deliberately whether it still has anything to prove, and cancel it
if it does not. Here it did not: its container tier was already 7 of 7 green, which was the entire
reason it had been dispatched, and its remaining Windows cells were a repeat of work the previous
sweep had passed on a tree differing only by a `changed_when` string and documentation.

The group itself is correct and should stay. Two sweeps running at once would fight over the twenty
concurrent jobs the account allows and both would crawl.

---

#### A winget manifest whose download is gone, and four network steps with no retry

Status: both fixed, 2026-08-25. Found by the Windows defaults cell of the final sweep 32839893770, which reported exactly two failures and named both.

The first is upstream rot that no check here could have predicted. `hwinfo` was mapped to winget as `REALiX.HWiNFO`, and the install failed with `0x80190194 : Not found (404)`. Measured afterwards: the newest manifest, version 8.50, names `https://www.sac.sk/download/utildiag/hwi_850x.exe`, and that URL answers 404, as does `hwi_848x.exe` from the version before it. The vendor's own download page answers 403 to a plain fetch, so there was no URL to substitute either.

Worth noting what this defeats. Tier 2 resolves winget package identifiers, and that identifier resolves perfectly: the manifest exists and is current. What is dead is the file the manifest points at, one level below what the check can see. A winget install can therefore fail on a package that every static check calls healthy.

Fixed by moving to Chocolatey, and the reason it is the right answer rather than merely a different one was measured. The `hwinfo.install` nupkg was fetched and unpacked: `tools/hwi64.exe` is inside it at 18,669,136 bytes and `chocolateyinstall.ps1` installs that local file with `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART`. It downloads nothing at install time, so it has no mirror to rot. The cost is version, 8.30.0 against the dead manifest's 8.50, and a working 8.30 beats a 404 on 8.50.

The second is ours. Installing Ansible inside WSL on a Debian family distribution ran four steps in sequence, every one of which reaches the network, with no retry on any of them and no check afterwards that anything had landed. `add-apt-repository --yes --update ppa:ansible/ansible` exited 1 after printing "Adding repository." and took the phase with it.

The PPA was not the cause, which is worth stating because it was the obvious suspect. It publishes for this suite: `https://ppa.launchpadcontent.net/ansible/ansible/ubuntu/dists/resolute/Release` answers 200, and the distribution's own `ansible` exists for resolute too. What failed was the apt update that `--update` performs, and nothing retried it.

Three changes. Every step retries three times with a pause, since apt keeps what it already fetched so a retry costs only what was lost. The PPA step is now the only optional one, so a PPA outage costs a newer ansible-core rather than costing Ansible, and the summary line names the step that was skipped. And the phase now asks `which ansible-playbook` before reporting success, because it used to report installed on the strength of the last step exiting zero, which is the shape this repository has been burnt by repeatedly.

---

#### The Razer Synapse installer on macOS drops the connection under Ansible

Status: fixed, 2026-08-25, in [macos_install.yaml](../setup/ansible/roles/software_installer/tasks/macos_install.yaml).

Cause: `installer -pkg RazerSynapseInstaller.pkg -target /` disrupts the local transport, and the task immediately after it could not be reached. From the macOS defaults cell of run 32864564543:

```text
[15:53:26] [+15.2s] CHANGED: [localhost]   installer: The install was successful.
[15:53:42] [+15.2s] unreachable: [localhost] TASK: Remove the staged Razer Synapse pkg
RECAP: localhost: ok=128 changed=49 unreachable=1 failed=0 skipped=281
```

Read the recap carefully, because it is the interesting part. `failed=0` and `unreachable=1`. Nothing evaluated itself as failing. On a local connection unreachable means Ansible could not deliver the module to a host it was already running on, which is a transport problem rather than a task problem. Sixty-five packages had installed by then and this was the last thing the software installer did.

Intermittent, which is why it took this long to see. The same cell passed in run 32839893770 an hour earlier and in every macOS cell before that. Whether it bites depends on how long Razer's postinstall work keeps the session busy, and the window here was sixteen seconds.

Fix: `wait_for_connection` between the install and the cleanup, with a 180 second ceiling. That is the mechanism Ansible provides for exactly this, something you just installed disrupted the transport, so wait for it to answer again.

Three things it deliberately is not. Not a `rescue`, and not `ignore_errors`, because both would hide a genuine failure of the install itself. Not a merge of the two tasks into one either, which was my first instinct: a disruption long enough to kill the next task would kill whatever came after it too, so dodging the exposure at that one seam only moves the problem. And if the connection never returns inside the ceiling, the play still fails.

---

### Upstream tooling bugs

#### The ansible-core 2.19 and 2.20 result-deserialization race

Status: open upstream, mitigated in this repository, first introduced commit `dd07664d28c4ba1dcf6c6763b3ce4dc44637a6b9` (2026-05-19).

Long-running native Ansible modules occasionally fail with "Module result deserialization failed: No start of json char found" on ansible-core 2.19.0 through 2.19.9 and 2.20.0 through 2.20.5, a race between the module's cleanup of its ansiballz zip payload and the controller's lazy JSON import, worse under heavy `/tmp` activity from `dpkg` and `systemd-tmpfiles`. This repository mitigates it two ways, `ansible.builtin.raw` bypasses the Python module subsystem entirely for the three Debian callsites that reliably cross the duration threshold, and the Ansible temp directories were moved out of `/tmp` into `~/.ansible/`.

The fix belongs upstream in pull request #86739 against `ansible/ansible`. Checked 2026-08-15: still open, `merged_at` null, last touched upstream 2026-07-02, and the ansible-core on this machine is 2.19.9, which is inside the affected range. So the workaround stays. Full detail, the mandatory recurring check before touching or reverting the workaround, and the exact affected version ranges live in [AGENTS.md](../AGENTS.md), which is the authoritative copy of this entry, not this ledger. Do not revert the `raw` callsites or the `~/.ansible/` temp paths without running that check first.

---

### Idempotency

#### The pacman no-op marker is on stderr, and the condition read stdout

Status: fixed, 2026-08-25, in [dynamic_install.yaml](../setup/ansible/roles/software_installer/tasks/dynamic_install.yaml).

Introduced the same day, by the change that removed the last batches. The new per-package pacman task needed a `changed_when`, and I guessed it instead of measuring it: it looked for `is up to date -- skipping` in stdout.

Caught within the hour by the Arch idempotency cell of sweep 32816442922, which applies the defaults configuration twice and fails on any task reporting a change on the second pass. It reported exactly one offender, `software_installer : Install Pacman packages, one at a time`.

Measured in an `archlinux` container afterwards. Installing a package that is already present exits 0 and prints ` there is nothing to do` on stdout, while the line that names the package, `warning: jq-1.8.2-1 is up to date -- skipping`, goes to stderr. So the condition looked for a string on a stream it never appears on, and the task therefore reported a change on every rerun.

This is the fifth instance in this section of the same defect: a `changed_when` reading stdout for something the tool writes to stderr. The lesson has been written down here before and I did it again, which is worth recording plainly.

The other two new conditions were measured at the same time rather than assumed, and both were already right. apt prints `0 upgraded, 0 newly installed, 0 to remove` on stdout for a no-op, absent on a real install, confirmed for a single package rather than trusted to carry over from the batch. dnf prints `Nothing to do` on stdout, with its repository progress on stderr. All three now carry the measurement in a comment beside them.


#### Five tasks in the SDK and AI tool roles reported a change on every rerun

Status: fixed in this change, in [nvm_unix.yaml](../setup/ansible/roles/sdk_manager/tasks/nvm_unix.yaml), [fvm_unix.yaml](../setup/ansible/roles/sdk_manager/tasks/fvm_unix.yaml), [android_sdk_unix.yaml](../setup/ansible/roles/sdk_manager/tasks/android_sdk_unix.yaml), [pyenv_unix.yaml](../setup/ansible/roles/sdk_manager/tasks/pyenv_unix.yaml) and [local_llm.yaml](../setup/ansible/roles/ai_tools/tasks/local_llm.yaml).

Found by running the same playbook twice in one container on Debian and reading which tasks reported changed on the second pass. Three of the five were doing the work twice, which is the expensive kind: FVM, Node and LM Studio were downloaded and unpacked again on every run, LM Studio being a bundle of roughly 110 MB whose installer re-extracts it in full. The other two did no work and said they had. Every artefact below was measured in a debian:trixie container rather than read off the installer's documentation, because two of the five defects are exactly what happens when a path is assumed.

| Task | Cause | What the guard keys on now |
|---|---|---|
| `Install FVM via install script` | One probe gated both FVM installs and it looked in `~/.fvm/bin`, `~/.pub-cache/bin` and PATH. Installer 2.0.0, from 2025-12, installs into `~/fvm/bin`, which is the one directory it did not look in, and which the locate task three tasks further down already knew about. So the probe never saw the script install's own result. | `creates: ~/fvm/bin/fvm` on the script install and `creates: ~/.pub-cache/bin/fvm` on the Arch `dart pub global activate` path, each guarding its own install rather than one probe guarding both. The container run left `~/fvm/bin/fvm` and nothing at all in `~/.fvm`, `~/.pub-cache` or `/usr/local/bin`. |
| `Install LM Studio via official script` | The stat checked `~/.local/bin/lms`, a path the installer has never written. It installs the CLI at `<lmstudio home>/bin/lms`, where the home is `~/.lmstudio` unless `~/.lmstudio-home-pointer` names another one. | A read-only probe that reads the pointer file when it exists and then tests the CLI with `test -x`. `creates` cannot express it, because the path is a fact read from the machine rather than a constant. |
| `Install Node LTS via NVM` | `changed_when` looked in stdout for "is already installed". NVM prints that with `nvm_err`, so it goes to stderr and the test could never be true. | A read-only `nvm which "lts/*"` probe, which is NVM's own answer, needs no network, and exits non-zero for the fresh case and for every half-installed shape tried: node deleted, node left non-executable, and the whole version directory removed with the alias files still in place. `creates` cannot express it, because the artefact path carries whichever version LTS resolves to on the day. |
| `Accept Android SDK licenses` | `changed_when` looked for "All SDK package licenses accepted", which sdkmanager prints both when it has just accepted them and when there was nothing to accept, so it was true either way. | A read-only `sdkmanager --licenses` with stdin closed, which prints the state and writes nothing. Measured with no licences accepted, with six of seven, and with all seven. `creates` cannot express it, because a licence is a file per licence and the set is not fixed, so keying on one file would permanently skip a machine that is missing one of the others. |
| `Wait for parallel Pyenv Python builds to finish` | Not a guard problem. Waiting is not a change, and the `changed_when` tested for "already installed" and "already exists" in stderr, neither of which `pyenv install --skip-existing` ever prints: it exits 0 having written nothing at all on either stream. "already exists" is what pyenv prints without that flag. | The past-tense marker python-build writes on success, "Installed Python-", so a build that really ran reports the change and a build that ran and failed is reported by `failed_when` instead. |

Three failure-masking conditions came out with them, all of the shape checklist item 3 and item 3a describe. The Node install's `failed_when` required `rc` to be defined before it could fail, so an async result carrying no `rc`, which is the shape a lost or killed job takes, passed silently. The Pyenv collector read `rc | default(0) != 0`, which calls that same shape a pass. The licence acceptance ended its pipeline with `|| true`, because `set -o pipefail` reports 141 when `yes` is killed by SIGPIPE, and that `|| true` swallowed sdkmanager's own status with it, leaving the `failed_when` beside it unable to fire at all. The answers are now fed from a file instead of a pipe, so the return code means what it says, and the task's `failed_when` asserts the post-condition that sdkmanager reports every licence accepted.

#### Seven tasks in the software installer and virtualization roles reported a change on every rerun, and one of them failed the second pass outright

Status: fixed in this change, in [dynamic_install.yaml](../setup/ansible/roles/software_installer/tasks/dynamic_install.yaml), [debian_repos.yaml](../setup/ansible/roles/software_installer/tasks/debian_repos.yaml), [custom_installs.yaml](../setup/ansible/roles/software_installer/tasks/custom_installs.yaml) and [virtualization_config/tasks/main.yaml](../setup/ansible/roles/virtualization_config/tasks/main.yaml).

Found by the same double run on Debian that produced the five rows above. Every string and every state below was measured by running the tool itself twice inside a container, `debian:trixie` for the package managers and the tier 3 Debian image with systemd as PID 1 for the service, rather than taken from documentation. Three of the seven had a `changed_when` that was already reading the tool's own output and still could not work, which is the point of measuring: the condition looked right in a diff every time somebody read it.

The seventh is a different kind of defect and the only one that failed a run. Its guard asked flatpak about an application id the bundle does not contain, so the guard never guarded anything, the install ran on every pass, and the second pass ended the play.

| Task | Cause | What it keys on now |
|---|---|---|
| `Install Flatpak packages (Debian, batched via raw to bypass 2.19 bug)` | `changed_when` looked for "Nothing to do.", which flatpak never prints for an install. Flatpak 1.16.6 prints `Installing <ref>` for a ref it installs and `Skipping: <ref> is already installed` for one that is present, both at rc 0, measured on Debian trixie and again on the Ubuntu image. | The presence of a line beginning `Installing `, so a batch where every ref was present is not changed and a mixed batch still is. |
| `Install QEMU/KVM and virt-manager packages (Debian) via apt-get` | The `changed_when` looked for apt's "0 upgraded, 0 newly installed, 0 to remove" line while the call itself passed `-yqq`, and `-qq` makes apt-get print nothing at all when there is no work. Measured as zero bytes on a second install in a container, against 205 bytes carrying that line with `-y`. | The same line, with the flags now taken from `apt_raw_flags` in [group_vars/linux.yaml](../setup/ansible/group_vars/linux.yaml), which is the `-y` form the batched apt install already used. |
| `Install spice-vdagent (Debian guest) via apt-get` | The same `-yqq`. | The same fix, from the same variable. |
| `Install Docker CE (Debian) via apt-get` | The same `-yqq`. | The same fix, from the same variable. |
| `Add Google Chrome apt repository` | Not a reporting defect. `google-chrome-stable`'s own postinst runs `install_deb822_sources` on every install, recognises the line this task writes, rewrites it into `/etc/apt/sources.list.d/google-chrome.sources` and deletes `/etc/apt/sources.list.d/google-chrome.list`. So the task genuinely rewrote a deleted file on every run and left two definitions of one repository behind. Read out of the installed postinst in a container that had just installed Chrome from this repository. | A `stat` of the vendor's own `.sources` file, with the repository line added only while that file is absent, which is the first install and nothing after it. |
| `Enable and start libvirtd service (Linux)` | Also not a reporting defect. libvirtd is socket-activated and its unit carries `Environment=LIBVIRTD_ARGS="--timeout 120"` on Debian, Fedora and Arch alike, so the daemon exits two minutes after the last client disconnects and systemd leaves `libvirtd.socket` listening. A task demanding the service be started really did start it, on every pass longer than that. Measured: after 150 idle seconds the old task reported `"changed": true`, and `virsh -c qemu:///system uri` answered anyway with only the sockets up. | Two tasks. `libvirtd.socket` started and enabled, which a socket unit sustains without exiting, and `libvirtd.service` enabled without a state, so boot-time guest autostart is kept and the idle exit is left alone. Both reported `"changed": false` in both states. |
| `Install Gridcoin flatpak bundle (Linux)` | The guard ran `flatpak info org.gridcoin.Gridcoin`. The bundle installs `us.gridcoin.GridcoinResearch`, so the guard answered "not installed" forever, the install ran every time, and the second run failed the play with `error: Failed to install bundle us.gridcoin.GridcoinResearch: us.gridcoin.GridcoinResearch already installed`. | The guard is gone and the result is classified instead, because a guard on the application id alone would also have silently skipped a bumped pin. rc 0 is a change, rc non-zero carrying flatpak's own already-installed wording is neither changed nor failed, and every other non-zero result still fails. |

Three of these tasks also carried the checklist item 3a defect while they were being read. The three `apt-get ... | tee` pipelines in the virtualization role had a `failed_when` on `rc` with no `set -o pipefail` above them, so the status they tested was tee's and no apt failure in that role could ever have failed a run. The `set -o pipefail` that the batched apt install already had is now on all three.

#### The first GitHub sweep: six defects, of which two were ours, two were the harness, and two were the network

Status: five fixed in this change, one left open with a named cause, in [container.sh](../e2e/tier3/container.sh), [e2e-matrix.yml](../.github/workflows/e2e-matrix.yml), [linux_live.yaml](../setup/ansible/profiles/linux_live.yaml), [openspec_unix.yaml](../setup/ansible/roles/ai_tools/tasks/openspec_unix.yaml), [debian_repos.yaml](../setup/ansible/roles/software_installer/tasks/debian_repos.yaml) and [fedora_repos.yaml](../setup/ansible/roles/software_installer/tasks/fedora_repos.yaml).

The first full sweep on GitHub ran 48 container cells and passed 18. Reading the 30 failures apart is the point of this entry, because they were not 30 defects: they were six causes, and only two of them lived in the software this repository installs.

| What failed | How many cells | Cause | What it is now |
|---|---|---|---|
| Every Pop!_OS cell | 6 | `popos.Dockerfile` starts `FROM installationhelper-e2e-ubuntu:latest`, and Docker cannot resolve a local image that has never been built. Every job died on "pull access denied, repository does not exist" about eighty seconds in, before any playbook ran. It worked on the developer machine only because the Ubuntu image happened to be lying around there. | The harness walks the `FROM` chain and builds each link first, refusing a chain deeper than four or one naming a Dockerfile that is absent. Proven by deleting the local Ubuntu tag and watching the Pop!_OS build put it back. |
| Every `live-profile` cell | 6 | Ours. `profiles/linux_live.yaml` turns `install_nodejs` off, which is right for a live session, and turns off five of the six tools whose only Linux install path is npm through NVM. It missed `install_bruno_cli`, which `group_vars/all.yaml` enables. The npm helper then reported NVM absent and failed the run, on every distribution. | The toggle is off in the profile, and [e2e/tier1/profile_prerequisites.sh](../e2e/tier1/profile_prerequisites.sh) derives the npm-only toggle set from the task graph and fails any profile that disables `install_nodejs` while leaving one of them on. The check was run against the known-bad tree first and named `install_bruno_cli`. |
| Every Fedora cell | 7 | Not established. `sudo` fails on the first task that escalates, with "PAM account management error: Authentication service cannot retrieve authentication info" followed by "sudo: a password is required", two seconds into the play. The same image escalates cleanly on this developer machine from the first second of boot, with a base pulled fresh the same day, so it is a property of the host rather than of the image. Removing the setuid bit was tried as a hypothesis and produces a different message, so that is not it. | Open. The harness now asks whether `sudo -n true` works before it starts the playbook, and on failure records the binary's mode, the account as the name service sees it, the sudoers rule, `sudo -l` and the daemon's storage driver and kernel. That turns a twenty-minute mystery reported against whatever task came first into a named abort in five seconds with the evidence attached. |
| Every CachyOS cell | 7 | Upstream, transient. The batched pacman install hit `unresolvable package conflicts detected`, with `lib32-mesa` dropped from the target list because it conflicts with `lib32-mesa-git` from the `cachyos-v3` repository. Re-resolving the same 35 packages against a freshly built image two hours later succeeds, so it was repository or mirror state mid-rebuild rather than anything in this repository. | Nothing to fix here, and the entry exists so the next reader does not go looking. What it does prove is the cost: a batch is one call, so one transient conflict lost all 35 packages and the whole software phase. |
| Ubuntu `kde-full` | 1 | Network. One TCP reset fetching the Tailscale keyring ended the software phase, and the libvirtd task then failed after it because virt-manager was never installed. | Every network task in `debian_repos.yaml` and `fedora_repos.yaml` retries three times with ten seconds between attempts. Eighteen tasks had no retry at all while the vendor downloads in `custom_installs.yaml` already had one, which was an inconsistency rather than a decision. |
| Debian `kde-configure-only` | 1 | Network. One reset from `deb.debian.org`, one `.deb` into eighteen, fetching the KDE widget build dependencies. | The Debian and Fedora build-dependency installs retry three times as well. A package that genuinely does not exist still fails, ten seconds later than before. |
| Every `idempotency` cell | 6 | Already fixed before the sweep ran. The sweep was dispatched at `56185fd`, one commit before the twelve idempotency fixes landed, so those results describe a tree that no longer exists. | Nothing. They have to be re-run, and until they are, they prove nothing either way. |

One more defect came out of dispatching rather than of any cell. `start_from_stage` did nothing: asked to start at stage 2, the workflow skipped stage 2 as well and reported failure eight seconds in. A skipped ancestor suppresses its descendants even when the job between them succeeded, because an `if` carrying no status-check function gets an implicit `success()` over the whole ancestry rather than over the direct `needs` alone. Naming `cancelled()` replaces that implicit check and leaves the gate output deciding. Not `always()`, which would keep launching container jobs after someone pressed cancel.

The lesson worth keeping is the ratio. Thirty red cells looked like a broken repository and were two real defects, one of which the gate now catches statically. Reading them apart took the artefacts, not the job list.

#### Fedora refuses to escalate in CI, and the cause was on the host all along

Status: cause found on the tenth attempt, in the host rather than in this repository, and fixed in [e2e-matrix.yml](../.github/workflows/e2e-matrix.yml). The harness names it in twenty-five seconds with the remedy attached, in [container.sh](../e2e/tier3/container.sh).

The cause. Ubuntu's AppArmor profile for `unix_chkpwd` grants only `capability audit_write`, and AppArmor attaches profiles by binary path, so a container process running `/usr/sbin/unix_chkpwd` is confined by the host's profile. pam_unix hands shadow lookups to that helper when the caller's real uid is not root. Fedora ships `/etc/shadow` at mode 000, so even a root helper needs `CAP_DAC_OVERRIDE` to read it, and the profile withholds exactly that. The kernel records it as `apparmor="DENIED" operation="capable" profile="unix-chkpwd" capname="dac_override"`, on the host, which is why nine rounds of measurement inside the container could not see it.

Why only Fedora, and it is the file mode rather than anything about Fedora's PAM. Debian and Ubuntu ship `/etc/shadow` at 0640 root:shadow with a setgid-shadow helper, and Arch ships 0600 root:root, so in both cases the ordinary permission bits are enough and the capability is never requested. Fedora's 000 gives nobody any bits at all.

Why root's own sudo passed. With a real uid of 0, pam_unix reads the file itself and never invokes the confined helper.

The fix is the one linux-pam and apparmor.d both document, applied to the runner before the harness starts: write `capability dac_override,` into `/etc/apparmor.d/local/unix-chkpwd` and reload the profile. It touches only the runner, which is discarded at the end of the job, and it skips itself with a message on a host that has no such profile. Found through [apparmor.d issue 958](https://github.com/roddhjav/apparmor.d/issues/958) and corroborated by [linux-pam issue 876](https://github.com/linux-pam/linux-pam/issues/876), where the reporter records the same thing this investigation did: identical images, fails on an Ubuntu 24.04 host, passes on Arch.

The lesson is the one worth keeping. Twelve hypotheses were tested inside the container and every one was eliminated, correctly, because the answer was never in there. When every measurement of a system says it is healthy, the next question is what is measuring it from outside.

This entry exists so nobody repeats the nine rounds. Every Fedora cell in CI dies two seconds into the play, on the first task that escalates, with `sudo: PAM account management error: Authentication service cannot retrieve authentication info` followed by `sudo: a password is required`. The same image runs a full defaults scenario on a developer machine in 45 minutes at `ok=199 changed=94 failed=0` with verification passing, so the tree is not the problem and neither is the image.

Measured in CI and eliminated, in the order they were asked:

| Hypothesis | What was measured | Verdict |
|---|---|---|
| The setuid bit is missing | `---s--x--x root root`, and removing the bit deliberately produces a different message naming itself | not it |
| The filesystem is nosuid | the overlay mount options, no nosuid | not it |
| no-new-privileges is set | `NoNewPrivs: 0`, and setting it deliberately produces a different message naming itself | not it |
| The account is missing or expired | present in passwd and in shadow, locked with `!` the way useradd leaves it, no expiry fields set | not it |
| The sudoers rule is unreadable | present at mode 0440, and `/etc/sudoers` carries its `#includedir` line at line 120 | not it |
| A different PAM profile or sssd | authselect profile `local`, a one-line account stanza of `pam_unix.so`, sssd not installed, nsswitch `files systemd`, all identical to a working machine | not it |
| Different package versions | sudo 1.9.17-8.p2, pam 1.7.2-1, glibc 2.43-5, systemd 259.8-1, character for character the same as a working machine | not it |
| The setuid transition does not happen | a setuid-root copy of `id` reports effective uid 0 | not it |
| The setuid process has no capabilities | a setuid-root copy of `cat` reads its own status: `000001ffffffffff` permitted and effective, and it reads the mode 000 `/etc/shadow` outright | not it |
| The name service cannot answer for a setuid process | a setuid-root copy of `getent` returns the shadow entry for the account | not it |
| sudo drops to the invoking user around the PAM call | sudo's own debug trace, the whole window between the two `sudo_pam_approval` markers, shows uid `[1000, 0, 0]` throughout and no perms change inside it | not it |
| pam_unix will explain itself if asked | the module's `debug` option produces no log line at all, because it returns AUTHINFO_UNAVAIL from `get_account_info` without logging | no answer |

What is left is inside the sudo process on that host, and the two tools that would see it are both unusable for this exact failure. The kernel drops the setuid grant for a traced or preloaded binary, so `strace` and `LD_PRELOAD` both change the thing being measured into something that cannot reproduce the fault. Root's own sudo passes PAM, which is consistent with that and narrows nothing further.

The one thing worth stating plainly: nine rounds cost about ten minutes of runner time in total, because the preflight aborts before any install starts. Before the preflight existed, the same information cost twenty minutes a round and arrived attributed to Google Chrome's repository task, which had nothing to do with it. That is the whole argument for asking a cheap question early.

#### balenaEtcher, suppressed on Debian, and I removed the suppression for the wrong reason

Status: suppression removed and coverage restored, but not by the reasoning below. Read the correction at the end of this entry before trusting any of it.

On 2026-08-17 the vendor .deb refused to install on `debian:trixie` with `Dependency is not satisfiable: polkit-1-auth-agent|policykit-1-gnome|polkit-kde-1`, so the toggle was turned off for the Debian image with the reason recorded beside it. That file said the application "cannot be installed by any means" on a headless Debian or Ubuntu, and as of today that sentence is false.

Measured on 2026-08-21 against the same package, version 2.1.6, whose control file still declares the same alternative dependency: `apt-get install ./balena-etcher_2.1.6_amd64.deb` exits 0 on both `debian:trixie` and `ubuntu:26.04`, and `dpkg -l` reports it installed. apt satisfies the virtual `polkit-1-auth-agent` by choosing `ukui-polkit`, which is a real cost rather than a free pass: it drags in `systemsettings`, `polkitd`, `biometric-auth` and the rest of that chain onto a machine with no desktop. Anyone provisioning a headless server should know that, and it is now the kind of thing the run itself shows rather than something a suppression hides.

The suppression was keyed on the image name `debian`, so it never applied to the `ubuntu` or `popos` images, which had been installing this package all along without anybody noticing the inconsistency.

Correction, written the same day. Everything above measured the wrong command. The playbook does not run `apt-get install ./file.deb`. It uses `ansible.builtin.apt` with the `deb:` option, which drives dpkg and cannot choose between the four providers of the virtual `polkit-1-auth-agent`, so it answers "Dependency is not satisfiable" and leaves the package unpacked and unconfigured. Removing the suppression on the strength of a command the code does not use turned four Debian cells red in the next sweep, on `defaults`, `live-profile`, `idempotency` and `kde-configure-only`.

The suppression was correct for the install method that existed. What was wrong was the install method. So the fix is not to put the suppression back: the deb install now runs `apt-get install <path>`, which hands the local file to the solver, and balenaEtcher installs on Debian and Ubuntu for real users as well as in the harness. The cost is stated where the task is rather than hidden: apt satisfies that dependency with `ukui-polkit` and pulls `systemsettings`, `polkitd` and the rest of a desktop authentication stack onto a machine that may have no desktop. That is the package's own requirement, and a run that shows it happening is more honest than a suppression that hides it.

Two lessons out of one mistake, and the second is the expensive one. A suppression written from one measurement needs re-measuring, which is what found this. And a measurement is only worth what it measured: I ran the command a person would type instead of the one the code runs, on the same day I wrote three commit messages criticising exactly that. Reproduce what the code does, not what you would do.

#### Every long-running task on macOS failed at once, because macOS has no timeout command

Status: fixed in this change, in [derive_os_facts.yaml](../setup/ansible/tasks/derive_os_facts.yaml), [macos_core](../setup/ansible/roles/macos_core/tasks/main.yaml), fourteen role task files, and guarded by [timeout_indirection.sh](../e2e/tier1/timeout_indirection.sh).

`timeout` is GNU coreutils. The BSD userland macOS ships does not have it under that name, so every task that bounded a long command with `timeout N ...` failed there with `/bin/bash: line 1: timeout: command not found`. Twenty-seven call sites across fourteen files.

The consequence was not twenty-seven small failures, it was one large one. The first of them is in `sdk_manager`, so the role failed, and with it Node through NVM, pyenv, SDKMAN, FVM, the Android SDK, the npm tools that depend on Node, and JetBrains Toolbox. A macOS user with any of those enabled has never had them install through this playbook.

Not one of those call sites was wrong on Linux, which is exactly why it lasted: every Linux container run exercised them and passed. It took the first stage 3 run this repository has ever done, on 2026-08-21, and it showed up four minutes in.

The command is a fact now, `ih_timeout`, resolved once alongside `ih_family` in the playbook's pre-tasks, and `macos_core` installs Homebrew's coreutils so `gtimeout` exists before anything reaches for it. A task reads `{{ ih_timeout }} 900 bash -c ...` and neither knows nor cares which platform it is on, and a third platform is one line here rather than a sweep of the roles.

Because the fix is a convention rather than a mechanism, tier 1 now refuses a bare call at a command position, checks that the fact exists and names both commands, and checks that coreutils is installed. It also asserts the number of indirected call sites has not collapsed, so undoing the indirection fails loudly rather than quietly. Proven against a copy of the tree with one call site reverted, where it names the file and the line.

Two things this cost that are worth stating. The macOS wizard had already been fixed once today for a bash 3.2 problem, so the platform had been touched and this still was not found, because nothing ran the playbook there. And the tier 1 gate had been green throughout, which is the honest limit of a static check: it can only compare what the source says to what the source says.

#### Three optional features the Windows Server SKU does not have, reported as failures

Status: fixed in this change, in [WindowsSettings.ps1](../setup/windows/WindowsSettings.ps1).

`NetFx4-AdvSrvs`, `Containers-DisposableClientVM` and `ServicesForNFS-ClientOnly` are Windows client features. On a Server SKU, DISM answers `Feature name <x> is unknown`, and the wizard reported each as a failure. Every GitHub Windows runner is a Server SKU, so the settings cell could never pass, and the same three failures would have been shown to anyone running this on Windows Server as though the wizard were broken.

The installation type is now read once from `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion`, which is a registry value rather than the several seconds `Get-ComputerInfo` costs, and passed into the elevated child. An unknown feature on a Server SKU becomes a skip that says which edition does not offer it. On a client SKU it stays a failure, deliberately, because there it means this list has drifted from what Windows offers and somebody has to look at it.

Finding that turned up a second defect in the same function. The switch that maps the child's report onto results had branches for present, installed, reboot and failed, and no default. A state it did not recognise produced no result at all, which reads to the caller as a feature nobody asked about. The new skipped state was exactly what would have hit it. Both the branch and a default that reports an unrecognised state as a failure are now there.

#### The Windows cell failed because the runner has no WSL distribution

Status: fixed in this change, in [e2e-matrix.yml](../.github/workflows/e2e-matrix.yml).

The wizard's last phase installs Ansible inside WSL, and a bare runner has WSL with no distribution registered, so it correctly said "there is nothing to install Ansible into" and the cell failed. Everything else in that cell had installed cleanly.

The four Windows jobs now register Ubuntu 26.04 with `--no-launch` before the wizard runs. That exercises the real path rather than teaching the wizard to forgive an empty WSL, which is a state a user genuinely should hear about. `--no-launch` matters: a first launch stops at a prompt for a username and password, which in a job nobody is watching is an unbounded hang, and that is the same reasoning the wizard's own WSL install already carries.

#### The idempotency scenario, corrected: one genuine offender, not three

Status: fixed in this change, in [site.yaml](../setup/ansible/site.yaml) and [idempotent_changes_allowed.txt](../e2e/tier3/idempotent_changes_allowed.txt).

I said three of the twelve were genuine and that was wrong. Only one is.

`Clean APT cache (Debian)` combined `autoremove` and `clean` in one call. Removing orphaned packages is a state the machine converges on, so a second run with nothing to remove honestly reports no change. Emptying the download cache is an act rather than a state and the apt module marks it changed every time. Split in two, with `changed_when: false` on the clean half, which is what its Arch and macOS siblings twenty lines away already carried, so this was an inconsistency rather than a judgement.

`Download Antigravity Linux tarball` is not an offender at all. `get_url` does not re-download a file that is already there, and the reason it is not there is that the post-tasks delete the whole staging directory at the end of the previous run. Same kind as the Gridcoin and GpuTest archives, and it belongs in the allowlist with them. The correction matters because the fix for a task that cannot tell it already ran is a guard on the task, and the fix for work that genuinely cannot repeat is a line in that file, and confusing the two puts a defect behind an exemption.

#### A regex that read past the end of its line, and the fourteen fixtures that did not notice

Status: fixed in this change, in [derive_os_facts.yaml](../setup/ansible/tasks/derive_os_facts.yaml), and now compared per fixture by [os_family_derivation_case.yaml](../e2e/tier1/os_family_derivation_case.yaml).

The os-release parsing captured `[^"]*`, which excludes the quote character and not the newline. Every value a distribution writes unquoted therefore swallowed the rest of the file up to the next quote. On CachyOS, `ID=cachyos` came back as `cachyos\nID_LIKE=arch\nBUILD_ID=rolling\nVERSION_ID=20260816.0.574111\nANSI_COLOR=`.

It had been there since the file was written, in `ih_os_release_id_like` and `ih_os_release_ubuntu_codename`, and it never mattered. The family derivation asks whether `arch` is IN the value, and a substring test does not care what follows. So the wrong value produced the right answer on every distribution, for as long as anyone had been looking.

It surfaced the moment a new consumer asked for equality instead. A CachyOS-only task gated on `ih_os_release_id == 'cachyos'` was compared against four lines of file and never ran, which cost six CachyOS cells in a sweep and an hour of looking at the wrong thing.

Two things are worth taking from it. The first is mechanical: bound a character class to the line when you are parsing a line-oriented format. The second is about tests. All fourteen fixtures have an unquoted `ID` with content after it, which is exactly the triggering shape, and all fourteen passed, because nothing compared those two facts to anything. An assertion on a value nobody compares is not a test of that value. Both are compared now, per fixture, and the check was proven by reverting the three regexes in a copy of the tree and watching it fail on the first fixture with the newline named in the message.

#### Four dnf repositories defined twice, two of them disagreeing, rewritten on every run

Status: fixed in this change, in [fedora_core](../setup/ansible/roles/fedora_core/tasks/main.yaml).

Fedora's idempotency scenario ran for the first time on 2026-08-21 and found something better than an idempotency defect. The Chrome, Brave, Sublime Text and VS Code dnf repositories were each defined in two places, `fedora_core/tasks/main.yaml` and `software_installer/tasks/fedora_repos.yaml`. Two of the four descriptions disagreed: one file called the Chrome repository `Google Chrome`, the other calls it `google-chrome`. So the two tasks overwrote each other's file on every run and both reported changed, permanently. Brave and VS Code happened to agree word for word and were idempotent by luck alone.

The duplicates are gone from `fedora_core`, leaving `fedora_repos.yaml` as the single owner, next to the Kubernetes, Lens and Tailscale repositories that were only ever defined there. `antigravity-rpm` stays because nothing else defines it.

The lesson is not about descriptions. Two definitions of one thing drift, and the only question is when. What made this visible was not a review of either file, it was running the playbook twice.

#### Two package-database refreshes reported as system changes

Status: fixed in this change, in [site.yaml](../setup/ansible/site.yaml) and [arch_core](../setup/ansible/roles/arch_core/tasks/main.yaml).

The same defect in two package managers, found in the same scenario a few hours apart.

`Clean APT cache (Debian)` asked apt for `autoremove` and `clean` in one call. Removing orphaned packages is a state the machine converges on, so a second run with nothing to remove honestly reports no change. Emptying the download cache is an act, and the apt module marks it changed every time.

`Sync package database and upgrade system (Arch)` asked pacman for `update_cache` and `upgrade` in one call, with exactly the same split of meaning. Its second pass output was three repository indexes downloading and not one package upgraded, reported as changed.

Both are now two tasks, with `changed_when: false` on the refresh half. In each case the same file already had siblings doing it correctly: the Arch and macOS cache cleans twenty lines from the apt one carried `changed_when: false` all along, so both were inconsistencies rather than judgements.

Worth stating because it generalises: a task that refreshes an index, empties a cache or otherwise does something whose result is not a state cannot be idempotent, and the honest place to say so is `changed_when` on that task, not an entry in an allowlist. The allowlist is for work that must genuinely happen again, like a file the run deliberately deleted.

#### CachyOS cannot install steam today, because its v3 repository disagrees with its own CDN

Status: superseded on 2026-08-28, and the heading above is wrong. It is kept rather than rewritten because the wrong turn is the useful part. Both files answer 200 on `mirror.cachyos.org` and 404 only on `cdn77.cachyos.org`, so the repository does not disagree with itself and steam installs on CachyOS. The suppression file is deleted and the correction is in the 2026-08-28 section above. The alignment task stays fatal for real users.

The chain is ours and the breakage is not. steam depends on the virtual `lib32-vulkan-driver`, whose first provider in repository order is `cachyos-v3/lib32-mesa-git`, which depends on `mesa-git`, which conflicts with the stable `mesa` that `qemu-full` installs earlier in the same run. Naming the stable `lib32-mesa` explicitly does not win, tested: pacman drops it in favour of the git build, because that is what satisfies `lib32-opengl-driver` from the repository CachyOS puts first. So the only way to install steam there is to align the whole graphics stack with the git builds up front, which is what `arch_core` now does.

That alignment cannot complete. The v3 database advertises `lib32-glibc 2.44+r24+g16be1518495f-1` and `lib32-gcc-libs 16.2.1+r23+gd564253eb6c8-1`, and the CDN answers 404 for both of those exact files. Measured against the URLs directly rather than inferred from a log, and confirmed against a freshly refreshed database naming the same versions.

A correction on my own first instinct, which is the reason this entry exists at all. I saw the 404 and read it as a mirror lagging behind the index, committed `-Syy` with three retries as the fix, and said so. That is the wrong diagnosis: a refresh fetches a fresh index and the fresh index names the same missing builds. The `-Syy` is kept because a forced refresh costs one index download and does cover the case it was written for, but it was not the case in front of me, and a fix that reads as if it addressed the problem is worse than no fix.

Two things this leaves. Suppressing one package is what lets the other thirty-four be tested at all, because a pacman batch is one call and the conflict takes all of them down together. And the suppression carries the two URLs precisely so that whoever reads it next can settle it in ten seconds rather than repeating the afternoon: if they answer 200, delete the file.

#### A `creates` guard naming a path the package does not install, for the third time today

Status: fixed in this change, in [custom_installs.yaml](../setup/ansible/roles/software_installer/tasks/custom_installs.yaml).

The Fedora idempotency scenario had a clean first pass and three not-allowed changes on the second, all AppImageLauncher: the download, the `rpm --install --upgrade --replacepkgs` and the removal of the staged file.

The install task guarded itself with `creates: /usr/bin/appimagelauncher`. Nothing writes that path. Read out of the package rather than guessed, `rpm -qlp` on the pinned 2.2.0 RPM lists `/usr/bin/AppImageLauncher`, `/usr/bin/AppImageLauncherSettings`, `/usr/bin/ail-cli` and `/usr/bin/appimagelauncherd`, and no lowercase `appimagelauncher` at all. So the guard could never fire, `--replacepkgs` reinstalled the package on every run, and the task reported changed for ever. The download and the removal around it are honest: the run deletes the staged RPM, so it really is absent at the start of the next one, and those two are allowlisted with that reason.

Third guard of this exact shape found in one day. FVM looked in `~/.fvm` while its installer writes `~/fvm`, LM Studio looked in `~/.local/bin` while it writes `~/.lmstudio/bin`, and this one had the right directory and the wrong capitals. The rule that falls out of all three: the path a guard checks has to be read out of the thing that creates it, and on Linux the case is part of the name. None of the three was visible in a diff, and all three were found by the same thing, running the configuration twice.

#### The reason a failed apt batch gives is the one line that gets truncated

Status: fixed in this change, in [container.sh](../e2e/tier3/container.sh).

Debian's `kde-configure-only` cell failed inside the batched apt install, and afterwards nothing said why. apt prints the whole dependency list before its error, the callback truncates a task's output after roughly a thousand lines, and the error is at the end, so the single line a reader needs is exactly the line that gets cut. The playbook does have a task that tails `/var/log/installation-apt-batch.log` for this purpose, and it never ran, because the failure it exists to explain aborts the role before reaching it.

Both apt transcripts, `installation-apt-batch.log` and `installation-virt-apt.log`, are now copied out of the container for every scenario next to `installation_errors.log`. Unconditionally, because a passing run's transcript is a few kilobytes and is the baseline you compare a failing one against.

The general shape is worth keeping: a diagnostic that only runs when the run survives is not a diagnostic for the case that matters. Collect the evidence from outside the thing that is failing.

#### The sweep that was meant to confirm a day of Windows work never ran a single Windows job

Status: fixed in this change, in [e2e-matrix.yml](../.github/workflows/e2e-matrix.yml).

Run 32513917159 finished 44 passed and 12 failed. Nine of the twelve were Linux container cells, and the other three were the gate plus two consequences of it: all seven stage 3 jobs, three macOS and four Windows, reported skipped. The sweep existed to prove the Windows Android SDK install, the seven user-scope environment variables, the Server SKU feature handling and the WSL registration, and it proved none of them, because six CachyOS cells failed over a repository whose index disagrees with its own content delivery network.

The cause was the dependency graph, not the failures. Every stage 3 job read `needs: stage2_gate` with `needs.stage2_gate.outputs.ok == 'true'`, so a red Linux sweep switched off every other platform. A Debian mirror dropping a connection is not evidence about a Windows installer.

Stage 3 now hangs off `stage1_gate`, the static gate over toggles, mappings, pinned values and both wizards, which is the one that genuinely protects it: if those are broken no platform is worth booting. The Linux node stays, renamed `stage2_verdict`, because turning thirty matrix cells into one red or green line is worth a job on its own, and its exit code is still what makes the run fail. It gates nothing now, and its unread `ok` output is gone rather than left to look load-bearing.

One deliberate consequence: with `start_from_stage=stage-2` the Windows and macOS jobs run alongside the container sweep instead of after it, which is both faster and a truer statement of what depends on what.

#### An async budget that could not fit the retry loop inside it

Status: fixed in this change, in [pyenv_unix.yaml](../setup/ansible/roles/sdk_manager/tasks/pyenv_unix.yaml).

Debian's all-software cell lost Python 3.12.13 to `curl: (35) TLS connect error: unexpected eof while reading` from python.org, and the fix for that was three attempts inside the async job, since Ansible's own `retries` cannot reach a task launched with `poll: 0`. The arithmetic was not carried through: three attempts at a 1500 second ceiling plus two 20 second waits is 4540 seconds, and the job still declared `async: 1800`, which is a hard kill rather than a target.

So the loop could only ever help against a fast failure, which is what the observed one was. A build that ran slowly and timed out left 300 seconds for the two attempts behind it, and whichever one was running when 1800 passed was killed with nothing said about it. `async` is now 4800, and the collector's wait went from 80 retries to 170 at 30 seconds, 85 minutes, so it outlasts the ceiling rather than giving up on a job that is still working.

The general shape: a retry loop and a timeout have to be sized against each other, and a number that was right for one attempt is wrong for three. The four builds run concurrently, so this is a worst-case ceiling and not a cost anybody pays.

#### Thirty lines kept from the wrong end of a thousand

Status: fixed in this change, in [dual_logger.py](../setup/ansible/callback_plugins/dual_logger.py), asserted by [ansible_static.sh](../e2e/tier1/ansible_static.sh).

Debian's kde-configure-only cell failed inside the batched apt install, and afterwards no log anywhere said why. The callback truncates a task's captured output to thirty lines, and it kept the first twenty-nine. apt prints what it is about to install first, one line per dependency, and says `E: Failed to fetch` at the very end, so of 1098 lines the run kept the dependency list and threw away the diagnosis. The playbook does have a task that tails `/var/log/installation-apt-batch.log` for exactly this, and it never ran, because the failure it exists to explain aborts the role before reaching it.

Truncation now keeps a third of the budget from the head, where a command names what it is doing, and the rest from the tail, where it fails, with a marker naming how many lines went so the two halves are not read as contiguous. A tier 1 assertion imports the real function out of the plugin, feeds it 500 lines ending in `E: Failed to fetch` and requires that line to survive. Proven both ways before it was committed: against a copy of the tree carrying the head-only version it reports `dropped the tail, last line is '... [truncated, 471 more lines]'`, and against the fixed one it passes.

Beside it, `installation-apt-batch.log` and `installation-virt-apt.log` are now copied out of every container scenario, so the package manager's own transcript survives the container even when the truncation was not the problem.

Worth stating plainly: this had cost nothing visible, because a run that passes never truncates anything a reader wants. It only ever bites on the run you most need to read, which is why it lasted this long.

#### Three apostrophes in a comment stopped every Linux run from loading

Status: fixed in this change, in [pyenv_unix.yaml](../setup/ansible/roles/sdk_manager/tasks/pyenv_unix.yaml), caught from now on by [ansible_static.sh](../e2e/tier1/ansible_static.sh).

The pyenv retry loop added earlier the same day carried its reasoning as shell comments inside the task body, and that prose contained the words `Ansible's`, `Debian's` and `python-build's`. Three apostrophes is an odd number of single quotes, and Ansible runs `split_args` over a free-form module argument, the body of shell, command, raw and script, before anything executes, counting quotes across the whole string with no idea that some lines are comments. So the file stopped loading: every Linux scenario died at parse time with `failed at splitting arguments, either an unbalanced jinja2 block or quotes`, having installed nothing.

Measured, not deduced. Three local container scenarios were started to prove three unrelated fixes, and all three failed identically at `Origin: /work/setup/ansible/roles/sdk_manager/tasks/pyenv_unix.yaml:84:3`: debian kde-configure-only, fedora idempotency and cachyos defaults, exit code 4 in each. The same three quotes were then handed to `split_args` directly, which raised the same error.

The worse half is that the gate said the tree was fine. `ansible-playbook --syntax-check site.yaml` passed with the file in that state, because it follows `import_tasks` and does not follow `include_tasks`, and this file is reached dynamically. A hundred and thirty-nine assertions passed over a tree that could not run a single Linux install.

Two things changed. The prose moved above the task, where Ansible never reads it, which is where rationale belongs anyway. And tier 1 now walks every `*.yaml` under `setup/ansible`, descends into `block`, `rescue` and `always`, and hands all 123 free-form bodies to Ansible's own splitter, so a file no static analysis reaches is still checked. A file that will not parse as YAML at all is reported by the same check rather than skipped, because the syntax check does not own dynamically included files either and skipping would hide it twice. Proven in both directions before committing: reintroducing three apostrophes in that body makes the check name the file and the task, and removing them makes it pass.

The lesson is narrow and worth remembering exactly: a comment inside a shell body is not inert. It is part of the string Ansible parses.

#### A variable that nothing ever set, and the Server SKU change that read it

Status: fixed in this change, in [WindowsSettings.ps1](../setup/windows/WindowsSettings.ps1), caught from now on by [powershell_variables.sh](../e2e/tier1/powershell_variables.sh).

The Windows settings phase failed on every run of the sweep of 2026-08-22 with `The variable '$installationType' cannot be retrieved because it has not been set`. The Server SKU change of the day before interpolated that name into the elevated child script it builds, so that the child could tell "this edition does not offer that feature" from "this list has drifted", and nothing anywhere assigned it. `Set-StrictMode -Version Latest`, which every PowerShell file here sets deliberately, makes reading an unset variable a terminating error, so the wizard stopped before enabling a single feature.

It is now read from the registry by `Get-WindowsInstallationType`, which returns Client when the value cannot be read, on purpose: not knowing the edition must not turn a real failure into a skip.

The interesting half is why nothing caught it. The file parses. PSScriptAnalyzer has no rule for reading an undefined variable. The Pester unit tests never reach that function, because it shells out to an elevated child. The two existing Windows checks read the mapping and the toggles rather than this code path. Only a real Windows runner could find it, and only after stage 3 was allowed to run at all, which it had not been for the whole life of the sweep before this one.

So tier 1 now parses every `setup/**/*.ps1` to an abstract syntax tree, collects every variable read, and reports any name that no assignment, parameter, `foreach`, `data` statement or `[ref]` argument in the same file binds. It names `WindowsSettings.ps1:232` and `:233` against the tree that shipped, and passes on the fix.

#### Four network transients in one sweep, and a playbook that gave up on all four

Status: fixed in this change, across [dynamic_install.yaml](../setup/ansible/roles/software_installer/tasks/dynamic_install.yaml), [fonts_theme.yaml](../setup/ansible/roles/shell_zsh/tasks/fonts_theme.yaml), [fvm_unix.yaml](../setup/ansible/roles/sdk_manager/tasks/fvm_unix.yaml), [virtualization_config](../setup/ansible/roles/virtualization_config/tasks/main.yaml) and eight other files, held in place by [network_retries.sh](../e2e/tier1/network_retries.sh).

One sweep lost four cells to four unrelated upstream hiccups, none of them a fault of this repository and none of them survivable as the playbook then stood:

| Where | What it said |
|---|---|
| deb.debian.org | `OpenSSL system call error: Broken pipe`, at file 440 of 440 in a 1.15 GB apt batch |
| github.com | `Connection reset by peer`, downloading one of four Nerd Font files |
| github.com | `[35] SSL connect error`, fetching an AppImage inside a flatpak batch |
| python.org | `curl (35) TLS connect error: unexpected eof`, downloading a Python tarball |

Two of those are batched calls, and a batch is one call, so a single lost file meant thirty-four applications never installed and the scenario failed. A provisioning run that gives up on the first dropped packet is not fit for the job it exists to do, on a laptop any more than on a runner.

An audit of the whole playbook found 34 tasks that reach the network with no retry at all: the font downloads, three git clones, the udev rule downloads, every Homebrew task, both flatpak batches, the Docker and QEMU installs, the Homebrew bootstrap script, the Dart signing key and the Waydroid repository. All of them now retry. The two that cannot use the keyword, because Ansible's `retries` cannot reach a task launched with `poll: 0`, carry a three-attempt loop inside their own body instead, and FVM's async budget was raised from 1800 to 4800 to fit it, with its collector raised from 40 minutes of waiting to 85 so it outlasts the ceiling rather than giving up on a job that is still running.

The tier 1 check that keeps it that way asks the same question the audit did and fails on any answer but zero, with one allowlist entry, the Gridcoin bundle, which installs a file already on disk. An allowlist entry whose task stops matching the network rule fails the check too, so the file cannot outlive what it excuses.

Worth being blunt about the earlier version of this entry, which does not exist because I nearly wrote it: the first instinct was to call these four "runner flakiness" and re-run. Three of the four would have passed on a re-run, and the defect would have stayed.

#### Two and a half hours of silence, then a cancelled job, and no way to tell which package did it

Status: fixed in this change, in [WindowsSoftware.ps1](../setup/windows/WindowsSoftware.ps1). The package that hung is still unidentified, and the change is what makes the next run name it.

Both long Windows cells of the sweep of 2026-08-22 were cancelled at their 150 minute ceiling. Their transcripts are 1.7 kilobytes each and end like this:

```text
  >> Installing Windows software
  -------------------------------

PS>TerminatingError(): "The pipeline has been stopped."
```

That is the whole record of two and a half hours. The software phase printed its header, then nothing until the runner killed it, because the phase only ever printed one summary line and it printed it at the end. Nothing said which package was being installed, how many had already gone through, or how long any of them took. The same phase with four packages, in the from-nothing cell, finished in three and a half minutes, so the code path works and something in the larger set does not.

Two changes, neither of which is a guess about the cause:

Every winget call is now bounded, the install at fifteen minutes and the already-installed probe at three. The process is started rather than invoked through a pipeline, because a native command in a pipeline cannot be given a deadline: killing it needs the process object. A package that runs out of time is reported as failed with the reason, so one hung installer costs one package instead of the whole job. Proven on a real machine before committing, with a command told to sleep for ten minutes: it returned at exactly the deadline with TimedOut true, and a normal command still returned its exit code and its output.

And the phase now prints a line per package as it starts one, with its index, its key, its package identifier and, when it finishes, its status and how many seconds it took. The next run will name the package that hangs, which no amount of reading this code could.

The `Exception setting "CursorPosition"` line above the header is PSReadLine rendering into a runner console that has no real handle, not this repository's code, and it is harmless. Worth writing down so the next reader does not spend an hour on it, as I nearly did.

#### The Server SKU fix wrote a word the parser did not know

Status: fixed in this change, in [WindowsSettings.ps1](../setup/windows/WindowsSettings.ps1), asserted by [windows_settings.sh](../e2e/tier1/windows_settings.sh).

The elevated child that enables optional features writes `<state>|<feature>|<detail>` into a result file, and the parent reads it back with a regular expression that names the states it accepts. When the Server SKU work taught the child to write `skipped`, the parent's expression was left listing present, installed, reboot and failed. Three lines were dropped in silence, and the wizard reported "the elevated child reported nothing for this feature, so its state is unknown" about features the child had answered perfectly well: NetFx4-AdvSrvs, Containers-DisposableClientVM and ServicesForNFS-ClientOnly, the three client-only features on a Server runner.

One file, one line format, two halves that disagreed about its vocabulary. Tier 1 now reads both sets out of the file and compares them, so neither side can gain a word alone.

#### wsl bash -c returns nothing, and it is not the distribution's fault

Status: fixed in this change, in [setup.ps1](../setup/setup.ps1).

The wizard reported `cannot auto-install Ansible for distro family ''` on every Windows runner. My first diagnosis was that the runner's freshly registered Ubuntu-26.04 had never completed its first run, and I fixed the wizard to try each registered distribution in turn. That was worth doing and it was not the cause.

Measured on a real machine with a working Ubuntu:

```text
wsl -d Ubuntu --user root -- bash -c 'source /etc/os-release; echo "${ID_LIKE:-$ID}"'   rc=0, 0 bytes
wsl -d Ubuntu --user root -- cat /etc/os-release                                        rc=0, 399 bytes
```

A command handed to `bash -c` through wsl.exe does not survive PowerShell's native argument passing. The shell runs something harmless, prints nothing, and exits zero, so the caller cannot tell that from a distribution with no os-release at all. Removing the double quotes does not help, which was checked rather than assumed.

So no shell is involved any more. The family is read with `cat` and parsed on the PowerShell side, the presence check is `which ansible-playbook`, and the install is a list of argument arrays run one at a time, which needs no quoting and gives an exit code per step. All four shapes were exercised against this machine before committing.

#### A group named after the user, which is a Linux idea

Status: fixed in this change, in [derive_os_facts.yaml](../setup/ansible/tasks/derive_os_facts.yaml) and its two callers.

`Ensure .dart-tool directory exists` failed on macOS with `chgrp failed: failed to look up group runner`, and took the whole SDK phase with it. Two tasks set `group: "{{ non_root_user }}"`, which is true on Debian, Fedora and Arch because useradd creates a group per user, and false on macOS where everyone is in staff.

The group is now asked of the machine with `id -gn` and resolved once as `ih_non_root_group`, next to the timeout fact that exists for the same reason. Both tasks that guessed now read it.

Ledger rule 1 again, in a new place: a per-machine fact belongs in a derivation, not in a task. This one had been wrong on every Mac since it was written, and only a real macOS run could show it.

#### Nineteen files quietly became CRLF, and three checks failed pointing elsewhere

Status: fixed in this change, guarded by [line_endings.sh](../e2e/tier1/line_endings.sh).

The gate went from 142 passing assertions to three failures whose messages had nothing to do with the cause, the loudest being "8 tolerated tasks register a result nothing reads" about registers that are read all over the playbook.

The cause was mine, from the same afternoon. Edits applied through a Python script that opened files for writing without specifying a newline, which on Windows rewrites every line ending as CRLF. Nineteen files converted whole, and two of them twice, leaving `\r\r\n` so that a first repair pass that replaced `\r\n` still left CRLF behind. Every diff read clean throughout, because `core.autocrlf=input` normalises on the way in.

`.gitattributes` has said `* text=auto eol=lf` for a while and explains exactly this hazard. What it cannot do is stop a working tree from drifting after checkout, and nothing checked that. Now something does, over all 414 tracked text files.

The check is written in Python rather than grep, which is not a style choice:

```text
printf 'a\r\nb\n' > f && grep -c $'\r' f      prints 0 in Git Bash
```

Git Bash strips the carriage return before matching, so a grep-based check passes on precisely the machine that creates the problem, while awk in the same shell keeps it. That inconsistency is what made the original failure so hard to read.

The real risk was never the false failures. The container tiers copy this working tree into Linux, where a shebang ending in a carriage return means "no such file or directory".

#### The Windows runner ran out of disk, and that reads as a dead runner rather than a failed install

Status: fixed in this change, in [e2e-matrix.yml](../.github/workflows/e2e-matrix.yml).

The "every application turned on" cell failed at 73 minutes with no failing step and no artefact. The job annotation was the only thing that said anything:

```text
System.IO.IOException: There is not enough space on the disk.
  : 'C:\actions-runner\cached\2.336.0\_diag\Worker_...log'
```

The runner ran out of space while writing its own diagnostic log, so the steps have no conclusions at all and the wizard's transcript never got uploaded. Around a hundred Windows applications do not fit beside a hosted image that is already mostly toolchains.

Every Windows job now clears the preinstalled ones first, and each path was chosen because the image ships it and nothing here uses it: the image's own Android SDK, which is not the one `setup.ps1` installs at `C:\tools\android`, the hosted tool cache of Python, Node, Go and Java builds, and four language runtimes. Free space is printed before and after rather than asserted, because the number belongs to the image and changes without notice, and a figure in the log is what the next reader actually needs.

Worth keeping in mind for reading any Windows cell: a full disk does not look like a failure, it looks like nothing. No step conclusion, no artefact, no message in the log, and the run summary simply says the job failed.

#### One installer crashed once, and took the run's exit code with it

Status: mitigated in [WindowsSoftware.ps1](../setup/windows/WindowsSoftware.ps1), with five Pester cases in [e2e/tier1/windows/WindowsSoftware.Tests.ps1](../e2e/tier1/windows/WindowsSoftware.Tests.ps1).

Run 32949705703, the single-platform Windows dispatch of the defaults set on 2026-08-26, failed after 101 minutes with exactly one bad package out of 78:

```text
  ... [42/78] lm_studio (ElementLabs.LMStudio)
      failed after 42s: exit -1978335226. Starting package install...
Installer failed with exit code: 3221225477
  [*] Windows packages: 77 installed, 6 already present, 3 not attempted, 1 failed
```

`-1978335226` is `0x8A150006`, winget saying the installer it launched failed. `3221225477` is `0xC0000005`, an access violation inside the installer itself. Every other phase reported zero failures, and the verification agreed with the run: one item requested and not present.

Four things were measured before calling it transient, because an access violation from an installer has meant a full disk in this repository before.

The disk was not full. The run had 53.30 GB free half an hour later, and the cleanup step that reports that figure runs after the software phase, so there was at least that much when LM Studio ran. The earlier disk exhaustion happened at 46 GB with far more still to install.

The package was not new or broken. `gh api` on the winget-pkgs commit history for `manifests/e/ElementLabs/LMStudio` puts the newest manifest, version 0.4.21+2, at 2026-08-12, two weeks before either run.

The same package installed cleanly the day before. In run 32896085273 the line reads `[43/80] lm_studio (ElementLabs.LMStudio)` and the verification records it as installed.

And nothing in that day's changes touches installs. The cache reclaim added the same day runs after the whole software phase, so it cannot reach a package that installed thirty minutes earlier.

Same package, same version, same runner image, opposite outcomes, no disk pressure. So the mitigation is a retry rather than a fix, and it is the repository's own standing rule rather than a new idea: anything that reaches a network in a provisioning run gets a retry, and an install that downloads an installer does. `Install-WingetPackage` now makes two attempts, pausing fifteen seconds between them, and says so in the log as it happens rather than only in the summary. A package that lands on the second attempt is reported as installed with the first failure still named in its detail, so a retry can never be mistaken for a clean first pass.

A timeout is deliberately never retried. The deadline exists to stop a hang, and spending it twice on one package is the opposite of what it is for.

Two defects of my own on the way in, both caught by the tests failing rather than by review, and both worth recording because the next person writing a stub will meet them.

A `.cmd` stub counting its own invocations with `find /c /v "" < file` hangs. `Start-Process` does not redirect standard input, so `find` waits on the console rather than reading the file, and the first run of these tests sat there until the harness killed it at 300 seconds. Counted with one marker file per attempt instead, which needs no external command at all.

And a generated path lost its separator to an escape sequence. The stub was written by a script whose string contained `$Directory\a1`, where `\a` is the BELL character, so the batch file said `$Directory` followed by an invisible control character and wrote its marker nowhere. It looked like `$Directory1` on screen. Every path in generated content now goes in without a backslash escape in the generator.

The value the retry is worth is unproven until a Windows run passes with it, which is one dispatch away rather than something to assert here.

#### The Windows container tier could never have tested a Windows install

Status: removed on 2026-08-26, at the owner's instruction. `e2e/tier3/Invoke-WindowsE2E.ps1` and `e2e/tier3/windows.Dockerfile` are deleted, the Pester suite moved to [e2e/tier1/windows/WindowsSoftware.Tests.ps1](../e2e/tier1/windows/WindowsSoftware.Tests.ps1) where the check that runs it lives, and local Windows verification is Windows Sandbox, documented in [e2e/manual_test_matrix.md](../e2e/manual_test_matrix.md).

Not a defect that broke a run. A tier that was built, documented at length, wired into the mandatory instruction table in [AGENTS.md](../AGENTS.md), and could not do the one thing its name promised.

A Windows container is always Windows Server. Microsoft publishes container base images only from Windows Server, the newest being Server 2025 at build 26100, and there has never been a Windows 10 or 11 client image, which was read off Microsoft's own base image servicing page rather than remembered. Server Core has no AppX deployment subsystem, winget ships as an MSIX that needs it, so no winget package can install in any Windows container. Counted out of `setup/ansible/vars/Windows.yaml` on the day: 80 of the 89 mappings. What was left was the YAML parsing, the plan and the Chocolatey bootstrap, and the tier 1 gate proves all three on a developer machine in seconds.

Three things should have ended it earlier, and each was visible from the start.

No workflow ever called it. The two references in `e2e-matrix.yml` were comments, one of which said in as many words that going through it had never been exercised. A tier no pipeline runs and no human runs is not a tier.

Its own documentation carried the refutation. The Dockerfile's header said winget cannot work in it and named the number, and that paragraph was updated more than once without anybody asking what was left.

And it cost more than it returned every time it came up: a multi-gigabyte Server Core image, an isolation argument, and finally an instruction to switch the Docker daemon away from the Linux containers every other tier needs, which is the thing that made the owner ask why it existed at all.

The isolation argument is worth keeping, because it is the part that is easy to get backwards, and I did get it backwards in conversation before checking. Process isolation runs the image's system files on the host's kernel and needs the two builds to match. This project's machine is build 26200 and the newest published image is 26100, so process isolation could never work here and Hyper-V isolation was the only local option. A hosted Windows runner is 26100, the same as the image, so there process isolation is the mode that fits. The machine that looked capable was the one that could not, and the runner nobody had tried was the one that could.

What replaced it covers more, not less. The suite still runs in tier 1 in seconds and in stage 1 of the sweep on a hosted runner. Real installs happen on the hosted Windows cells, all 89 mappings, and locally in Windows Sandbox, which is client Windows at the host's own build, so it can do the winget path and the client-edition packages the Server runner has to skip. What no arrangement covers is unchanged and still listed on the manual page: a reboot, a hypervisor, the Store ids, and hardware.

#### Two wrong answers about the Windows download caches, and what the tools actually do with them

Status: the wizard now empties both caches mid-run, in [WindowsSoftware.ps1](../setup/windows/WindowsSoftware.ps1) and [setup.ps1](../setup/setup.ps1), guarded by [windows_cache_cleanup.sh](../e2e/tier1/windows_cache_cleanup.sh).

This follows the disk exhaustion above, and it is here for the two wrong answers on the way rather than for the fix.

The first wrong answer was mine, offered without measuring: that clearing the winget and Chocolatey download caches would free meaningful space, said in the same conversation as the rule about never claiming anything without measuring it first.

The second was the measurement that appeared to refute it. Both caches on a real machine that has installed the whole set repeatedly:

```text
%TEMP%\chocolatey   728 directories, 0 files
%TEMP%\WinGet     1,326 directories, 201 files, largest 17,378 bytes
```

Nothing to free, apparently. That reading was also wrong, and the thing that settled it was Chocolatey's own log rather than the directory:

```text
Downloading virtualbox 64 bit
  from 'https://download.virtualbox.org/virtualbox/7.2.14/VirtualBox-7.2.14-174565-Win.exe'
Downloading ... to C:\Users\<user>\AppData\Local\Temp\chocolatey\virtualbox\7.2.14\VirtualBox-7.2.14-174565-Win.exe
Download of VirtualBox-7.2.14-174565-Win.exe (169.81 MB) completed.
Elevating permissions and running ["C:\Users\<user>\AppData\Local\Temp\chocolatey\virtualbox\7.2.14\VirtualBox-7.2.14-174565-Win.exe" ...]
```

Chocolatey downloads into the cache, installs from the cache, and leaves the file there. The directory was empty 19 days later because Windows cleans its own temporary directory, which a one hour continuous integration job never gets. So a directory listing taken 19 days after the fact says nothing at all about what the disk holds during a run, and that is what made the second answer wrong.

Two more things measured rather than assumed, both of which change what the fix can be:

1. `choco cache` is not the command for this. Asked directly, `choco cache --help` on 2.7.3 answers that it works on the User HTTP Cache and, when elevated, the System HTTP Cache. That is the NuGet metadata. The installer payload is not part of it and has to be removed as files.
2. `<temp>\WinGet\cache` is not a download cache at all. It holds the source index, the manifests and version data winget resolves package ids against, and the verification phase queries winget after the cleanup runs, so it is kept and only its per-package siblings go.

The cleanup runs between the packages and the SDK installers, which is where run 32864564543 ran out: `wsl --install` failed with `Wsl/InstallDistro/0x80070070`, and the two failures either side of it were the same cause in disguise, an access violation from the Arduino installer and the Android SDK dying at 85 per cent while unzipping. It reports free space before and after rather than claiming a saving, so the number comes from the run.

Proven rather than reasoned about: against a fabricated cache tree, the step removed 4,194,304 bytes and free space on the volume rose by exactly 4,194,304 bytes, it left the winget source index in place, it reported `nothing cached here` for an absent directory, and with an installer held open by another process it named that path as a failure and carried on. Thirteen Pester cases cover those, and five mutations of the tree, the call deleted, the call moved after the SDK installers, its result not discarded, the source index no longer kept, and a `throw` added to the remover, each fail the tier 1 check.

Nothing was needed on Linux or macOS, and that is also measured. [site.yaml](../setup/ansible/site.yaml) already ends every successful run with `apt clean` and `apt autoremove`, `pacman -Sc`, `dnf clean all` and `dnf autoremove`, `brew cleanup --prune=all`, the Snap download cache and disabled revisions, and the unused Flatpak runtimes. Inside the tier 3 containers there is less than that to clean: the Debian and Ubuntu images ship `/etc/apt/apt.conf.d/docker-clean`, whose `DPkg::Post-Invoke` deletes every `.deb` the moment it is installed, and Fedora's dnf5 keeps no `keepcache` setting so its default of false applies, measured as zero `.rpm` files under `/var/cache/libdnf5` after an image build. Arch is the one that does accumulate everywhere, 85 packages and 53 MB sitting in `/var/cache/pacman/pkg` straight after an image build with no cleanup hook, which is what the `pacman -Sc` at the end of the run is for.

One asymmetry left on purpose. The Linux and macOS cleanups are gated on `playbook_succeeded`, so a failed run keeps its caches for the retry, while the Windows one runs regardless because it runs before the outcome is known and because headroom matters most on a run that is going badly.

#### The nightly hibernate task is gone, by owner decision

Status: removed in this change, at Lukk's instruction, from [WindowsSettings.ps1](../setup/windows/WindowsSettings.ps1), [windows.yaml](../setup/ansible/group_vars/windows.yaml), both wizards and every document that counted it.

The Windows settings cell reported one failure: the scheduled task registered, but hibernation is not allowed on the machine, so it would fire every night and do nothing. That report was correct, and it is ledger rule 5 working as intended rather than a defect to soften.

Lukk does not want the machine hibernating on a schedule, so the feature is deleted rather than suppressed in continuous integration. Gone with it: the `import_hibernate_task` toggle, `Register-HibernateTask`, its entry in the declared setting keys, its dispatch, its line in both wizard menus, and the `IsPwrHibernateAllowed` Win32 import that nothing else called. Windows now has three native system settings rather than four, and the documents that said four say three.

Untouched on purpose: the Linux `setup_hibernate` toggle, which is a different thing. It grants permission to hibernate through a PolicyKit rule and records the swap UUID for resume, and it schedules nothing.

One thing worth recording about the removal itself. Deleting the toggle took the two lines above it with it, `setup_wsl` and `enable_hyperv`, because the block boundary was found by searching backwards for a blank line. The tier 1 Windows check caught it immediately with "WindowsSettings.ps1 claims setting keys that no group_vars toggle defines", which is exactly the pair comparison it exists for.

#### A distribution mirror stumbled during an image build, and the scenario died before it started

Status: fixed in this change, in [container.sh](../e2e/tier3/container.sh).

The CachyOS idempotency cell of 2026-08-22 failed 30 seconds in, with the whole 300 minute scenario lost to this:

```text
ERROR: failed to build: failed to solve: process "... pacman -Syu --noconfirm --needed sudo
ansible-core which ..." did not complete successfully: exit code: 1
```

The image build, not the playbook. Every tier 3 image installs packages from a distribution mirror while it builds, and a mirror that stumbles takes the cell with it before a single task runs. That it was a flake rather than a defect is measurable rather than assumed: the CachyOS defaults and kde-full cells built the same image from the same commit minutes earlier and passed.

The build is now three attempts thirty seconds apart, and the output of the last one is printed when it gives up, because a genuine build error buried by a retry loop is worse than the flake the loop was hiding.

That is the sixth network transient today across four different hosts. The pattern is now hard to miss: anything that reaches a network in a provisioning run needs a retry, and the ones that did not have one are what today's work has mostly been.

#### The wizard crashed while correctly reporting a failure

Status: fixed in this change, in [WindowsCustomInstalls.ps1](../setup/windows/WindowsCustomInstalls.ps1).

The Windows defaults cell reached the custom installs and died there:

```text
TerminatingError(Invoke-WindowsCustomInstall): "Cannot convert argument "collection", with value:
"@{Key=nodejs; Package=nvm; Status=failed; Detail=the Chocolatey batch was still running after 30
minutes and was killed ...}", for "AddRange" to type "IEnumerable`1[System.Object]""
```

The Chocolatey batch timed out, which the code handles: it returns one result saying so, with the command to run by hand. Then `AddRange` refused it, because a lone `PSCustomObject` is not a collection. So the wizard crashed while reporting a failure it had dealt with properly, and everything after that line, the Android SDK and Gridcoin included, never ran.

All four calls now wrap the result in `[object[]]@( )`, the same wrapper `WindowsSettings.ps1` already uses, which makes one object and many behave alike. The shape to watch for: a function whose happy path returns a list and whose early exit returns a single object is a crash waiting for the day the early exit happens.

The same run confirmed the per-package progress output works. The transcript now reads `... [74/80] tor (TorProject.TorBrowser)` followed by `installed after 36s`, and the phase summary was 76 installed, 6 already present, 4 failed, where before it printed one line after two and a half hours of silence.

Three of those four failures are worth recording as facts about the environment rather than defects here. `glasswire` answered 403 Forbidden to its own download. `partition_wizard` ran its installer and got exit code 1. `spotify` refused with "The installer cannot be run from an administrator context", which is true and is caused by the cell passing `-AllowAdministrator`: a real user running the wizard unelevated does not hit it.

#### One Chocolatey package that never returns costs every package in the batch

Status: fixed in this change, in [WindowsSoftware.ps1](../setup/windows/WindowsSoftware.ps1).

Both Windows software cells of 2026-08-22 reported the same thing: `the Chocolatey batch was still running after 30 minutes and was killed, so those packages are NOT installed`. Between the two cells that cost nvm, geforce-experience and razer-synapse-4, and nothing in the log said which package was the one that hung.

Two changes, and neither is a bigger number on its own.

The child now installs one package per call, each with `--execution-timeout=600`, so Chocolatey itself gives up on the package that hangs, says which it was, and the packages behind it still get their turn. It prints the package before running it and the exit code after, like the winget phase does now.

And the deadline the wizard applies to the child is sized against that loop instead of picked: ten minutes per package plus ten for the bootstrap, never less than thirty. The old flat thirty covered three packages, and both cells had more than that, so the batch was killed while it was still legitimately working. A timeout smaller than the work it bounds does not protect a run, it invents failures.

#### The signature check crashed on exactly the file it exists to reject

Status: fixed in this change, in [WindowsCustomInstalls.ps1](../setup/windows/WindowsCustomInstalls.ps1).

`Install-DirectInstaller` downloads a vendor installer, checks its Authenticode signature, and refuses to run anything that is not validly signed. The rejection message named the signer:

```powershell
Detail = "refusing to run it: Authenticode status is $($sig.Status), signer '$($sig.SignerCertificate.Subject)'"
```

`SignerCertificate` is null when a file carries no signature at all, and `Set-StrictMode -Version Latest` makes reading `.Subject` off null a terminating error. So on an unsigned binary, which is the case the check exists to catch, the wizard crashed instead of reporting. The Windows defaults cell of 2026-08-22 died there, and the rest of the SDK phase and Gridcoin never ran.

The signer is now resolved defensively and says "none, the file carries no signature" when there is none. Which vendor binary is unsigned is not yet known, because the crash prevented the message that would have said so, and the next run will name it.

Third crash of this exact family today, after `AddRange` refusing a lone object and `$installationType` never being assigned. All three are the same mistake: a failure path written once, never executed, and wrong. Under strict mode an untested error branch is not a safety net, it is a second failure waiting behind the first.

#### A missing collection breaks every distribution, and the error names a line that never runs

Status: fixed in this change, in [container.sh](../e2e/tier3/container.sh).

The Debian all-software cell of 2026-08-22 died before installing anything:

```text
[ERROR]: couldn't resolve module/action 'kewlfft.aur.aur'.
Origin: /work/setup/ansible/roles/software_installer/tasks/dynamic_install.yaml:513:7
```

That task is guarded by `when: ih_family == 'Archlinux'` and could never have run in a Debian container. Ansible resolves module names at parse time, before any condition is evaluated, so one missing collection stops the file loading on every distribution and the message points at a line that is irrelevant to the failure.

The collection was missing because galaxy.ansible.com answered with something its own client could not parse:

```text
File ".../ansible/galaxy/api.py", line 386, in _call_galaxy
    res = path_cache['results']
KeyError: 'results'
ansible.errors.AnsibleError: Unexpected Exception, this is probably a bug: 'results'
```

Two changes. The install is retried three times, twenty seconds apart, because that is a network call like every other one this repository has had to learn about today. And a run that still cannot install its collections now stops there with that reason, instead of warning and letting the playbook fail five minutes later on something unrecognisable. A scenario whose prerequisites did not install has not started, and saying so is cheaper for the next reader than any amount of log archaeology.

#### The wizard ran end to end on Windows, and what it found

Status: the run is the finding. One reporting gap fixed in this change, in [WindowsSoftware.ps1](../setup/windows/WindowsSoftware.ps1). Four decisions are open and belong to the owner.

The Windows defaults cell of sweep 32585990680 is the first Windows run that reached its own summary. Every phase reported: 77 packages installed, 6 already present, 3 failed, 6 CLI tools, 8 SDK installs done and 4 failed, 9 environment variables written, the system settings applied, Ansible installed inside WSL, and the verification run. That is the whole wizard, on a real machine, for the first time.

What it found, separated by who owns it.

Facts about the environment, not defects here:

| Package | What happened |
|---|---|
| glasswire | its own download answers 403 Forbidden |
| partition_wizard | its installer exits 1 |
| spotify | refuses to run from an administrator context, which the cell creates by passing `-AllowAdministrator` |

Real findings that need a decision:

| Item | What happened |
|---|---|
| gridcoin | `Authenticode status is NotSigned, signer 'none, the file carries no signature'`. The pinned release binary is unsigned, so the check refuses it. Either the toggle goes, or the binary needs a pinned checksum instead of a signature |
| razer_cortex | exited 0 and installed nothing, so `/S` is not its silent switch |
| nodejs via nvm | `choco exited -1` |
| flutter via fvm | `choco exited 1` |

The last two had no explanation at all, which is the gap this change closes. The Chocolatey work happens in a separate elevated process, and when the wizard is not already elevated that process runs through `-Verb RunAs`, which forbids output redirection outright. So the parent could say the exit code and nothing else. The child now keeps its own transcript with `Start-Transcript`, which works in both the elevated and the RunAs case, and the failure quotes the last twelve lines of it. It also returns the worst exit code across the loop rather than the last one, so a failure in the middle is not hidden by a success after it.

#### Gridcoin is pinned by checksum, and Razer Cortex is gone

Status: both are owner decisions, taken on 2026-08-22 and implemented in this change.

Gridcoin's Windows installer carries no Authenticode signature, and the project publishes no checksum with its releases, so `Install-DirectInstaller` refused to run it. Lukk's decision was to pin the hash instead: the bytes were downloaded, measured and pinned as `gridcoin_win_installer` in the `[checksums]` table, and the installer now verifies against it. Where a checksum is pinned the signature is not consulted at all, which lets one unsigned vendor binary through deliberately rather than weakening the rule for every other download. Where none is pinned, an invalid or missing signature is still a refusal.

That needed a small amount of plumbing, because nothing on the Windows side could read the checksum table: the reader learned `--checksum <name>`, and the PowerShell adapter learned `Get-PinnedChecksum`, both with the same three-way answer the pins already had, which is value, absent, or a broken file.

Razer Cortex is removed entirely. It exited 0 and installed nothing under `/S`, Razer publishes no switch it will admit to, and it is a game launcher rather than device software. Razer Synapse 4 stays and installs cleanly through Chocolatey, which is what actually configures the devices. Gone with Cortex: the toggle, the pinned URL, the proof-table entry, the custom install block, its line in the software table and every comment that explained its silent switch.

Two things the gate caught during this work, both worth recording.

The pinned-value check reported `gridcoin_win_installer reads like a pin in the gridcoin family and nothing pins it`. It was right by its own rules: `[checksums]` is a second namespace, and PowerShell reads a checksum by quoted name exactly as it reads a pin, so the first checksum key ever referenced from PowerShell looked like a typo. The check now loads the checksum table and exempts it.

And that fix did not work at first, for a reason that has now cost this repository twice in one day. The probe reads the table through Python, Python on Windows writes CRLF to a pipe, and `mapfile` keeps the carriage return inside the value. The name matched nothing, the guard silently answered no, and the trace showed the list being filled correctly the whole time. Stripping the carriage return fixed it. A guard that answers no by accident is indistinguishable from a guard that is working.

#### Four Windows packages, four different reasons, all measured before anything was changed

Status: fixed in this change. Gridcoin's checksum was reverted at the owner's instruction the day after it was added.

The Gridcoin checksum went in and came straight back out. The reasoning against it is the owner's and it holds: the download is an HTTPS URL to the project's own GitHub release, a hash buys nothing he wants from it, and it fails the install every time the version moves and nobody remembers to re-measure. So the signature requirement is waived for that one installer by name, through `-AllowUnsigned` at the callsite, and every other download still needs a valid signature. The checksum reader flag and the PowerShell accessor built for it were removed with it rather than left as machinery nothing calls.

The rest were diagnosed against the live sources rather than guessed at:

| Package | What was measured | What changed |
|---|---|---|
| glasswire | the winget manifest's installer URL answers 403 from any machine, not only a runner: the S3 object behind it is gone | moved to Chocolatey, whose `glasswire` carries the same 3.9.1102 and was updated 2026-08-16 |
| bruno | the 4.1.0 manifest carries three installers, and winget picks the per-user nullsoft one, which exits 3221225477, an access violation, when the wizard runs elevated. The MSI beside it is declared `Scope: machine` | the mapping gained an optional `scope` field and Bruno asks for machine |
| nvm | Chocolatey's `nvm` is a meta-package in front of `nvm.install`, and it exited -1 with nothing in the log | moved to winget, `CoreyButler.NVMforWindows`, the vendor's own installer with no dependency chain |
| fvm | Chocolatey's `fvm` 4.1.5 declares `dart-sdk:[3.9.0]` as an exact dependency, so a 4 MB version manager arrived behind a whole pinned Dart SDK and exited 1 | installed from FVM's own release archive, `fvm-4.1.5-windows-x64.zip`, extracted to `%LOCALAPPDATA%\fvm\bin` |

GeForce Experience is gone entirely at the owner's request. The NVIDIA App that replaced it has no winget manifest, and that is measurable rather than remembered: `winget search "nvidia app"` returns nothing, no `Nvidia.NVIDIAApp` id exists, and winget-pkgs rejected the submissions in #140696, #179043 and #253660. Chocolatey does carry `nvidia-app` 11.0.8.299, which the documentation said did not exist, so that claim was corrected.

Left as it stands, and deliberately: `partition_wizard`. Its winget URL answers 200 with a 77 MB Inno installer, the manifest declares the right silent switches, and it exits 1 anyway. Nothing in the data explains that, and the installer's own log is the only thing that can, so the guessing stops here until a run collects it.

#### Partition Wizard, the answer that was there all along

Status: fixed in this change. The earlier entry saying only the installer's own log could explain it was giving up too early, and the owner said so.

The exit code was read and nothing else was. Three cheap checks settle it:

1. The downloaded installer identifies itself in its own bytes as `Inno Setup Setup Data (6.1.0)`. Inno's exit code 1 means "Setup failed to initialize", which is a refusal before installation starts, not a wrong switch.
2. The manifest's URL answers 200 with 77 MB and declares the correct silent switches, so neither is at fault.
3. MiniTool's own page says the Free edition supports "Windows 11, Windows 10, Windows 8.1/8, Windows 7", and Server needs their separate paid Server Edition: https://www.partitionwizard.com/free-partition-manager.html

A GitHub `windows-latest` runner is Windows Server, which this repository already detects and prints, since that is why three optional features report "not offered on this Windows edition (Server)". So the package installs on a normal machine and can never install on the runner.

The mapping now carries `client_only: true`, and on a non-Client edition the wizard reports it skipped with that reason. Spotify gained `user_context: true` for the same shape of problem: its installer refuses to run from an administrator context, which is true and deliberate on their side and only bites because the e2e cells start the wizard with `-AllowAdministrator`.

Both are facts about where the software can install rather than about whether the run worked, which is what a skip is for. The alternative, leaving them as permanent red, teaches a reader to ignore red.

#### nvm and fvm, and where those packages actually come from

Status: fixed in this change. Both moved again after the owner objected to the sources, and the objection was worth answering with evidence rather than assertion.

The Chocolatey packages were the third-party ones. `nvm` on Chocolatey is a wrapper maintained by a packager called asheroto that only depends on `nvm.install`, and it exited -1 with nothing in the log. `fvm` on Chocolatey declares `dart-sdk:[3.9.0]` as an exact dependency, so a 4 MB tool arrived behind a second pinned SDK and exited 1.

Where each now comes from, and the evidence for who publishes it:

nvm-windows. The upstream nvm project, nvm-sh/nvm, is Unix only, and its own README sends Windows users to `nvm-windows`, listing it under "for Windows, a few alternatives exist". That project is `coreybutler/nvm-windows`, 47443 stars, and it is what every Windows Node version manager instruction on the internet means by nvm. winget's `CoreyButler.NVMforWindows` manifest downloads `nvm-setup.exe` from that project's own releases with the SHA256 pinned in the manifest, and the manifest itself is reviewed in microsoft/winget-pkgs. That is the shortest chain available: the project's own binary, hash-pinned, through Microsoft's own manager.

To be exact about a phrase used carelessly earlier: coreybutler is the author of nvm-windows, not of nvm. They are different projects.

FVM. Installed with `dart pub global activate fvm`, from pub.dev, which is Google's package registry for Dart. pub.dev lists fvm under the verified publisher `leoafarias.com`, and the Dart SDK is already installed on Windows by `install_dart` in the software phase that runs before the SDK phase. That removes the downloaded archive entirely and keeps FVM on the registry its own documentation points at.

#### GeForce Experience out, NVIDIA App in, through the only manager that has it

Status: done in this change, at the owner's request.

`winget search "nvidia app"` returns nothing against the live source, there is no `Nvidia.NVIDIAApp` identifier, and winget-pkgs rejected the submissions in #140696, #179043 and #253660. Chocolatey carries `nvidia-app` 11.0.8.299, published 2026-07-14. So `install_nvidia_app` is mapped to Chocolatey, and `geforce_experience`, which NVIDIA discontinued, is gone.

#### The gate passed 145 assertions and the sweep died at stage 1

Status: fixed in this change, in [WindowsSoftware.ps1](../setup/windows/WindowsSoftware.ps1), and the hole closed by [windows_pester.sh](../e2e/tier1/windows_pester.sh).

Sweep 32697182413 stopped before it started. Stage 1's Pester job failed, the stage 1 gate said no, and stages 2 and 3 never ran:

```text
PropertyNotFoundException: The property 'Scope' cannot be found on this object.
at Resolve-WindowsSoftwarePlan, setup\windows\WindowsSoftware.ps1:204
```

The plan builder had started reading three optional mapping properties, `Scope`, `ClientOnly` and `UserContext`. The Pester suite builds mappings by hand with none of them, and under `Set-StrictMode -Version Latest` reading a property that is not there is a terminating error. All three are read defensively now, through `$m.PSObject.Properties['Scope']`, so a mapping that predates them plans exactly as it did before.

That is the fourth crash of this family in three days, after `$installationType` never being assigned, `AddRange` refusing a lone object, and `.Subject` read off a null certificate. Strict mode does not forgive an optional read, and every one of these was on a path nothing had executed.

The gate hole is the more useful half. The Pester suite existed only as a CI job, so a local run of the full tier 1 gate could pass 145 assertions over a tree that CI would refuse in twenty seconds. It now runs here too, the same file with the same tag exclusions, and it was proven both ways before being committed: against the tree that broke CI it reports the failure, and against the fix it passes 27 of 30 with one skip. The CI job stays, because it runs on a clean Windows runner and this machine cannot reproduce that.

#### A run graph nobody could read

Status: fixed in this change, in [e2e-matrix.yml](../.github/workflows/e2e-matrix.yml) and the new [e2e-linux-cell.yml](../.github/workflows/e2e-linux-cell.yml).

Three complaints from the owner about the Actions graph, all fair.

The whole Linux sweep rendered as one node reading "Matrix: stage2_sweep, 1/48 job completed". That is what GitHub does with a `strategy.matrix`: the cells are separate jobs in the sidebar but a single tile in the graph, so the picture of a run showed six stage 3 tiles by name and one anonymous box hiding forty-eight cells. Stage 2 is now forty-eight jobs, each calling a reusable workflow, so each gets its own named tile. The cost is a longer file, which is generated rather than hand-written, and the loss of `max-parallel`, which never bound anything: the account's own 20-job concurrency limit is what actually paced the matrix.

Stage 3 ran alongside stage 2 rather than after it. That was deliberate and it was explained badly. It was decoupled on 2026-08-21 because gating it on stage 2's result meant six CachyOS failures skipped all seven Windows and macOS jobs on the one sweep meant to prove a day of Windows work. The fix keeps both properties: stage 3 now depends on `stage2_verdict` without reading its result, so the graph runs in order and a red Linux cell still cannot hide a Windows regression.

The names were long and said little. "Stage 3 install on Windows: nothing on, then a few by name" is now "Windows four apps only", and the same treatment went through every job: "Tier 1 checks", "Windows unit tests", "Debian defaults", "CachyOS forced failure", "Verdict: Linux installs".

The `if` on each cell is what the deleted `stage2_plan` job used to compute. A dispatch of `scenario: defaults` with `distro: all` runs six jobs and skips forty-two, exactly as the plan's generated matrix did.

---

### Outside the Ansible playbook, found while touching local-dev/auth

This project's own scope statement above is the Ansible playbook and its wizard scripts. The entries below are
outside that, in the local development Docker Compose stack, and are recorded here because they were found while
building the local certificate authority for `local-dev/auth/certificates/localhost/`, and documenting how to trust
it, and the instruction for that work said to log it here.

#### The documented certificate generation command could never run on a clean checkout

Status: fixed in this change, in [local-dev/auth/README.md](../local-dev/auth/README.md).

The "Certificate generation" section of that README told the reader to run `openssl req -x509 -nodes -days 3650
-key ./local-dev/auth/certificates/localhost/localhostDomain.key -out ... -config ...`. The `-key` flag tells
openssl to sign with an existing private key file, and no command anywhere in the README, or in the repository,
ever produced `localhostDomain.key`. It shipped as a tracked file, so the command worked for anyone who already
had a checkout with that key committed, and would fail the instant the key was absent, for example on a fresh
clone made after a history rewrite, or if a future change stopped committing keys.

Proven by copying only `localhost.cnf` into an empty directory and running the documented command verbatim:

```text
Could not open file or uri for loading private key from ./localhostDomain.key: No such file or directory
```

The fix is the three-step flow the README now documents: create the root key and certificate, create the leaf key
and its signing request with `openssl req -new`, then sign the request with the root. Every file the flow needs is
produced by a command the reader already ran, so there is no step that depends on a file already existing outside
of git.

#### OpenSSL on Windows wrote the new certificate and key files with CRLF line endings

Status: not a live defect, corrected in this change. The original entry below overstated the risk. Kept, with the
correction, per this ledger's own rule to mark a wrong hypothesis rather than delete it.

This repository's own [.gitattributes](../.gitattributes) forces `eol=lf` on every text file, and states its own
reason at the top: a carriage return is invisible in a diff and breaks a check that passes under Git Bash and fails
under WSL or inside a container. Running the three documented `openssl` commands from Git Bash on Windows to build
`localDevCA.crt`, `localDevCA.key`, `localDevCA.srl`, `localhostDomain.crt` and `localhostDomain.key` produced every
one of them with CRLF line endings, because OpenSSL writes PEM output with the platform's native line ending and
Windows Git Bash's OpenSSL build is a native Windows binary. Proven with `xxd`, which showed `0d0a` after
`-----BEGIN CERTIFICATE-----` in every generated file, against `0a` alone in the certificate already committed at
`HEAD`.

That reading of the risk was wrong. `git check-attr text eol` against all four new files in
`local-dev/auth/certificates/localhost/` answers `text: auto` and `eol: lf` for every one of them, which means git
normalizes the carriage return out the moment a file is staged. The committed blob is LF whether or not anyone runs
a manual fix, so a checked-out CRLF certificate breaking some later reader was never a real exposure for the
committed form.

The one place worth actually checking was the working tree copy, since the Dockerfile's `COPY` reads that file
straight off disk rather than through git, so a freshly generated CRLF certificate goes into a built image exactly
as CRLF. Measured rather than assumed: a CRLF copy of the leaf certificate and key, confirmed with `xxd` to carry
`0d0a`, parsed cleanly with both `openssl x509 -noout -subject -issuer -serial` and `openssl rsa -check -noout`,
because a PEM file's base64 decoder treats a carriage return as ordinary whitespace. Built into a throwaway Keycloak
image from a scratch copy of `local-dev/auth` carrying that CRLF pair, and confirmed with `od -c` that the file
inside the running container still carried `\r\n` after `-----BEGIN CERTIFICATE-----`, the server started clean,
logging `Listening on: https://0.0.0.0:9443`, served the realm discovery endpoint over TLS with a plain `curl -k`
returning HTTP 200, and the handshake verified with `Verify return code: 0 (ok)` against the real committed root
via `openssl s_client -CAfile localDevCA.crt`.

So stripping the trailing carriage return with `sed -i 's/\r$//'` on the five generated files was belt and braces,
not a fix for a live failure. Nothing in the chain, not git, not OpenSSL, not Keycloak, breaks on a CRLF certificate
or key. The original conclusion, that anyone regenerating these files from Git Bash on Windows hits this and needs
the same manual fix, does not hold: this repository's own `.gitattributes` normalizes the committed form regardless,
and the working tree form that briefly carries CRLF works fine as an input to every tool that reads it.


#### The Windows curl advice named a mechanism its own error message ruled out

Status: fixed in this change, in [local-dev/auth/README.md](../local-dev/auth/README.md). Documentation only.
Nothing in the compose stack behaved differently at any point, and the defect was found before the section was
committed.

The "Trust the cert from application code" section said the Git Bash build of curl on Windows, which uses Schannel
as its TLS backend, "ignores `--cacert` entirely, it only ever trusts what is already in the Windows certificate
store", and concluded from that the only fix on Windows is importing the root into the operating system trust
store. Immediately below the claim it quoted the error it had actually measured:

```text
curl: (60) schannel: the revocation status is unknown
```

Those two statements cannot both be true. A backend that never opens the file has no chain to build and fails on
trust. Getting as far as a revocation question means a chain was built, which means the file was read. The
mechanism had been inferred from the fact of the failure rather than measured.

Proven by five runs from Git Bash on Windows, curl 8.19.0 with the Schannel backend, against
`https://keycloak:9443/realms/local/.well-known/openid-configuration` served by the `keycloak` container from
[local-dev/local-dev-docker-compose.yaml](../local-dev/local-dev-docker-compose.yaml):

1. `--cacert localDevCA.crt` on its own reproduced the documented error, exit 60.
2. Adding `--ssl-no-revoke` returned HTTP 200, exit 0.
3. Adding `--ssl-revoke-best-effort` instead of it returned HTTP 200, exit 0.
4. Pointing `--cacert` at an unrelated throwaway authority generated in a scratch directory outside the repository failed differently, and identically with `--ssl-no-revoke` added: `curl: (60) schannel: the certificate chain is incomplete`.
5. Dropping `--cacert` altogether failed on trust rather than on revocation: `curl: (60) schannel: SEC_E_UNTRUSTED_ROOT (0x80090325) - The certificate chain was issued by an authority that is not trusted.`

Runs 2 and 3 alone disprove the claim, because a flag that only relaxes revocation checking cannot make an ignored
file start being read. Run 4 shows what a genuine trust failure looks like from this same build, and run 5 shows
what the machine's own trust state produces with no file supplied at all. Runs 2 and 5 were repeated against
`keycloak.test`, the name this machine's hosts file actually carries, with the same outcomes, so none of it depends
on how the host name was resolved.

The revocation status is unknown because the leaf carries no CRL distribution point and no Authority Information
Access extension, which is what a locally generated authority produces, since it publishes neither a revocation
list nor an online responder. Confirmed with `openssl x509 -noout -text` on the leaf, and independently by
`certutil -verify -urlfetch localhostDomain.crt localDevCA.crt`, which reports `Certificate has no
revocation-check extension` and `Revocation check skipped`.

The Windows certificate store held nothing relevant for any of it. `Cert:\LocalMachine\Root` (76 certificates),
`Cert:\CurrentUser\Root` (76), both `CA` stores and both `My` stores contained no certificate whose subject matched
`Local-dev`, and a search by the root and leaf thumbprints matched nothing either. So no result above was
contaminated by the machine already trusting this authority, and the older `Local-dev` leaf that predates the local
certificate authority was not lingering in a store either.

An earlier report during the same work said Git Bash curl could not be made to trust a custom `--cacert` even with
`--ssl-no-revoke`, quoting `schannel: the certificate or certificate chain is based on an untrusted root`. Recorded
here because it was the second half of the contradiction, and because the likeliest reading is that it was run 5
rather than run 2: an untrusted-root error is what this build produces when no `--cacert` takes effect. That
reading was not reproduced directly, because the exact command behind that report was never written down. Both
failures exit 60, so the message text is the only thing that separates them, which is precisely why the exit code
is not enough to reason from.

The fix is the rewritten curl subsection. It gives `--ssl-revoke-best-effort` as the runnable Windows command,
names the operating system trust store import as the alternative that needs no flag at all, and explains the
failure as a revocation status that cannot be determined rather than as a file that was never read.
