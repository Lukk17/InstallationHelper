# Regression ledger

Current as of 2026-08-21. Every entry below is written against the tree at that date, and the one still-open finding says so in its own status line.

This is the list of defects the Ansible playbook and its wizard scripts have actually suffered, mined from the project's git history and from a container audit run the same day this page was written. Every entry states the cause, what it broke, and where the fix lives, or says plainly that it is still open. The point is prevention. Read the checklist below before touching anything under [setup/](../setup/), then use the grouped entries as a reference for the failure mode you are about to repeat.

The older, pre-Ansible bash-script era of this repository (2022 to early 2024, the plain `ubuntu/*.sh` and `windows/installer.ps1` scripts) is excluded. Those commits carry no message body explaining cause and effect, and the files they touched no longer exist, so nothing in that history can be verified against current code.

---

### Checklist before calling playbook work done

1. If you touched anything that names a Linux group, a package name, or a service name, check whether that name is the same string on Debian, Fedora and Arch. If it is not, the mapping belongs in the per-distribution `vars/{OS}.yaml` dictionary, never hardcoded in a shared task file. This is the exact mistake in the Arch OpenRazer device group entry below.
2. Do not assume a package exists in a distribution's official repository just because it exists in Debian's. Check the actual repository for every OS family the toggle claims to support. This is the mistake behind the Arch OpenRazer kernel module entry, the Arch Arduino removal, and the toggle plumbing entries for `install_putty` and `install_gradle`.
3. Never let `failed_when` or a block's `rescue` turn a real failure into a passing play. If you write a `failed_when` with more than one condition, work out by hand whether Ansible ANDs or ORs them, then write a test that proves it. If a `rescue` block exists, make it name the task that failed, not just print a generic warning. See the pacman batch entry and the install-block rescue entry.
3a. A `failed_when` on `rc` is only as good as the `rc` it reads, and with `raw`, `shell` or `command` that is the shell's status, not your program's. A pipeline reports its last command, so `apt-get ... | tee log` reports tee and tee always succeeds. A command list reports the last one, so anything ending `&& echo A || echo B` reports an echo and can never be non-zero. Both were live in this repository and both had a `failed_when: rc != 0` sitting uselessly beside them. Prepend `set -o pipefail` to any pipeline whose status you intend to check, never end such a command with an echo, and prove it by making the inner command exit non-zero and watching the task fail. See the raw pipeline entry.
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

A harness under [e2e/](../e2e/) mechanises part of this checklist. Items 4 and 5 are fully covered by its tier 1 checks, which run in seconds and are proven to fail against the code from before each fix. Item 2 is covered by tier 2, in two halves that cover different things. The `vars/{OS}.yaml` dictionary names are resolved over HTTP for Arch, the Arch User Repository, Flathub, Homebrew, Chocolatey and winget, and deliberately not for apt or dnf, because most of those names come from repositories the playbook adds while it runs and resolving them beforehand would report healthy packages as missing. The names written directly into role task files are resolved for all four Linux families, apt and dnf included, inside the same pinned base images the tier 3 scenarios use, with the handful that genuinely need a run-time repository listed in [runtime_repo_packages.txt](../e2e/tier2/runtime_repo_packages.txt) rather than silently forgiven. So for apt and dnf, a stale name in a role is caught in seconds and a stale name in a dictionary is caught only by tier 3. Items 1 and 6 are covered by tier 3, which runs the real playbook in a container. Coverage there is uneven and worth stating exactly, because a green tier 3 is easy to read as more than it is. Arch has run all seven scenarios. Debian and Fedora have since also run the defaults scenario, on 2026-08-17: Fedora passed clean, Debian did not, failing on a balena-etcher dependency the container image cannot satisfy (`Dependency is not satisfiable: polkit-1-auth-agent|policykit-1-gnome|polkit-kde-1`, run `2026-08-17T10-13-03Z_debian_defaults`), an open finding not yet triaged. Ubuntu has run smoke and nothing else. So five of the seven scenarios remain something a person has to do by hand on Debian and Fedora, six on Ubuntu, and the desktop environment scenarios in particular have never run outside Arch. macOS has no container at all and Windows has never been run in one, its gate being a separate PowerShell entry point that needs the Docker daemon switched to Windows containers. Items 3, 7, 8, 9 and 10 are not mechanised at all and remain review discipline.

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

Status: fixed in [e2e/tier3/Invoke-WindowsE2E.ps1](../e2e/tier3/Invoke-WindowsE2E.ps1).

Cause: two defects in the command generated for the container. `Invoke-Pester` was called without `PassThru`, so it returned nothing, and the script then ran `exit $r.FailedCount` on a null. Separately, the `-SkipSlow` branch interpolated the string `-ExcludeTagFilter @('Slow','Network')` onto a line of its own inside the generated script, where a leading hyphen is an operator PowerShell does not have.

Effect: with `-SkipSlow` the generated script was a parse error and the run failed before Pester started. Without it, the gate exited 0 no matter how many tests failed. Both were proven directly: `$r = $null; exit $r.FailedCount` exits 0, and feeding that exclude line to `[scriptblock]::Create` throws at the character where the array begins. The fixed form was proven the other way too, with throwaway suites: a green suite exits 0 and a suite with two failures exits 2, and the script now also refuses a run that discovered no tests rather than calling it a pass.

#### A test suite that only passed with an environment variable nobody sets

Status: fixed in [e2e/tier3/windows/WindowsSoftware.Tests.ps1](../e2e/tier3/windows/WindowsSoftware.Tests.ps1).

Cause: the suite located the repository through `$env:E2E_REPO_ROOT` with a fallback to `C:\work`, the path inside the Windows container. The variable is set by the container entry point and by nothing else.

Effect: run the normal way from the repository, the suite reported 31 tests discovered and 0 passed, every one failing in `BeforeAll`. It had been reported as 28 passing, measured in a session that had exported the variable by hand. It now walks up from its own directory to find the repository, keeps the variable as an explicit override, and throws a clear error rather than guessing when neither works. Verified from the repository root and from an unrelated working directory, 28 passed and 0 failed in both.

---

### Open findings, not yet fixed

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

### Upstream tooling bugs

#### The ansible-core 2.19 and 2.20 result-deserialization race

Status: open upstream, mitigated in this repository, first introduced commit `dd07664d28c4ba1dcf6c6763b3ce4dc44637a6b9` (2026-05-19).

Long-running native Ansible modules occasionally fail with "Module result deserialization failed: No start of json char found" on ansible-core 2.19.0 through 2.19.9 and 2.20.0 through 2.20.5, a race between the module's cleanup of its ansiballz zip payload and the controller's lazy JSON import, worse under heavy `/tmp` activity from `dpkg` and `systemd-tmpfiles`. This repository mitigates it two ways, `ansible.builtin.raw` bypasses the Python module subsystem entirely for the three Debian callsites that reliably cross the duration threshold, and the Ansible temp directories were moved out of `/tmp` into `~/.ansible/`.

The fix belongs upstream in pull request #86739 against `ansible/ansible`. Checked 2026-08-15: still open, `merged_at` null, last touched upstream 2026-07-02, and the ansible-core on this machine is 2.19.9, which is inside the affected range. So the workaround stays. Full detail, the mandatory recurring check before touching or reverting the workaround, and the exact affected version ranges live in [AGENTS.md](../AGENTS.md), which is the authoritative copy of this entry, not this ledger. Do not revert the `raw` callsites or the `~/.ansible/` temp paths without running that check first.

---

### Idempotency

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

Status: not fixable here. steam is suppressed on the CachyOS image in [container_limits.cachyos.yaml](../e2e/tier3/container_limits.cachyos.yaml), with the two URLs to re-measure written beside it. The alignment task stays fatal for real users.

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
