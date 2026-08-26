# Tier 3 base image for Arch Linux scenario runs.
#
# Deliberately close to a fresh Arch install rather than convenient. Only what a
# real machine has before setup.sh runs is preinstalled: systemd (in the base
# image), sudo, and ansible-core with its Python. base-devel, git, rust and the AUR
# helpers are NOT here on purpose, because arch_core is supposed to install them and
# a preinstalled convenience would hide it if that ever broke.
#
# systemd runs as PID 1 so tasks that enable units are genuinely exercised. That
# needs --privileged and the host cgroup mount at run time, see container.sh.
FROM archlinux:base

# The locale data has to be restored before anything else. The published Arch container image
# slims itself with NoExtract rules that strip usr/share/i18n, so /usr/share/i18n/SUPPORTED is
# absent and system_core's locale generation fails with "No such file or directory" on a file
# every real Arch install has. Dropping those rules and reinstalling glibc costs a few tens of
# megabytes and buys a container that actually exercises the locale tasks. Suppressing the
# task instead would have turned a genuine step into an untested gap, which is the failure
# mode this whole directory exists to prevent.
#
# One transaction after that, then drop the package cache so the image stays small.
RUN sed -i -E '/^NoExtract.*(locale|i18n)/d' /etc/pacman.conf \
    && pacman -Syu --noconfirm --needed \
        sudo \
        ansible-core \
        which \
    && pacman -S --noconfirm --overwrite '*' glibc \
    && pacman -Scc --noconfirm

# ansible-core is whatever Arch publishes, and it cannot be pinned to an exact version here:
# Arch is rolling, it carries exactly one version and the previous one is gone from every
# mirror the moment it is superseded, so an exact pin would break the build rather than hold it steady.
# It built at 2.21.2 on 2026-08-20, with 2.21.3 already published in extra.
#
# What can be pinned is the range, and it is the same half-open range setup/setup.sh enforces on a
# real machine, 2.19.0 accepted up to but not including 2.22.0. Every release inside it still carries
# the ansiballz result-deserialization race documented in AGENTS.md, because the upstream fix is
# unmerged, so this range is about running a version the playbook has been exercised on, not about
# escaping that bug.
#
# Checked at build time on purpose. An image outside the range is a broken image, and this fails the
# build in seconds rather than a scenario twenty-five minutes in.
ARG ANSIBLE_CORE_MIN_VERSION=2.19.0
ARG ANSIBLE_CORE_MAX_VERSION_EXCLUSIVE=2.22.0
RUN CORE="$(ansible-playbook --version | head -1)" python3 -c 'import os, re, sys; found = re.search("core ([0-9.]+)", os.environ["CORE"]); version = lambda s: tuple(int(n) for n in (re.findall("[0-9]+", s) + ["0", "0"])[:3]); low, high = os.environ["ANSIBLE_CORE_MIN_VERSION"], os.environ["ANSIBLE_CORE_MAX_VERSION_EXCLUSIVE"]; core = found.group(1) if found else ""; sys.exit(0 if found and version(low) <= version(core) < version(high) else "this image has ansible-core " + (core or "an unreadable version") + ", outside the range " + low + " <= version < " + high + " that setup/setup.sh accepts")'

# The playbook runs as a normal user who escalates with sudo, matching how a person
# runs setup.sh. This sudoers file is named so that site.yaml's cleanup task, which
# removes 99-ansible-user, cannot take the harness's own escalation away mid-run.
ARG E2E_USER=lukk
RUN useradd --create-home --shell /bin/bash ${E2E_USER} \
    && install -d -m 0750 /etc/sudoers.d \
    && printf '%s ALL=(ALL) NOPASSWD: ALL\n' "${E2E_USER}" > /etc/sudoers.d/00-e2e-runner \
    && chmod 0440 /etc/sudoers.d/00-e2e-runner

# Ansible writes its temp dirs, fact cache and galaxy cache under the invoking user's
# home, per ansible.cfg. The parent .ansible directory has to belong to the user too,
# not just the leaves, or ansible-galaxy cannot create galaxy_cache alongside them.
RUN install -d -o ${E2E_USER} -g ${E2E_USER} /home/${E2E_USER}/.ansible \
    && install -d -o ${E2E_USER} -g ${E2E_USER} \
        /home/${E2E_USER}/.ansible/tmp \
        /home/${E2E_USER}/.ansible/facts-cache

STOPSIGNAL SIGRTMIN+3
CMD ["/usr/lib/systemd/systemd"]
