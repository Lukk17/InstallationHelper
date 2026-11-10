# Tier 3 base image for Ubuntu scenario runs.
#
# Ubuntu is ansible_os_family "Debian", so it loads the same
# setup/ansible/vars/Debian.yaml dictionary the Debian scenario uses. It still gets
# its own image because its package versions, its snap support and its release
# codename differ from Debian's, and that is exactly where a Debian-only assumption
# in the playbook would break without anyone noticing.
#
# Deliberately close to a fresh Ubuntu install rather than convenient. Only what a
# real machine has before setup.sh runs is preinstalled: systemd, sudo, and
# ansible-core with its Python. Build tooling, git, curl and any package manager
# helper are NOT here on purpose, because system_core is supposed to install them
# and a preinstalled convenience would hide it if that ever broke.
#
# systemd runs as PID 1 so tasks that enable units are genuinely exercised. That
# needs --privileged and a private cgroup namespace at run time, see container.sh.
FROM ubuntu:26.04

# DEBIAN_FRONTEND only needs to exist for the length of this build step. An ARG
# rather than an ENV keeps it out of the image's runtime environment, so it cannot
# quietly change how the playbook's own apt tasks behave when the container runs.
ARG DEBIAN_FRONTEND=noninteractive

# ubuntu:26.04 (resolute) ships ansible-core 2.20.1 in the universe component, which
# is already enabled by default in this image's sources, confirmed against the real
# archive index. That is inside the range setup/setup.sh accepts on its own, so unlike
# an older Ubuntu release this image needs no Ansible PPA. The next person changing
# this file should re-check that fact before removing this comment. procps is not
# listed either: unlike Debian, Ubuntu carries it at Priority: required and it is
# already present in this base image, confirmed by running the image directly, so
# ps already works without adding anything. which is not listed for the same reason
# as Debian: debianutils is Essential and already provides it. systemd-sysv is what
# actually produces /sbin/init and the systemd binary. The base image only carries
# libsystemd0, a library with no init in it.
RUN apt-get update && apt-get install -y \
        sudo \
        ansible-core \
        systemd-sysv \
    && rm -rf /var/lib/apt/lists/*

# ansible-core is whatever Ubuntu 26.04 publishes, and it cannot be pinned to an exact version here:
# the release pocket carries exactly one version, and a security update replaces it in place, so
# an exact `ansible-core=<version>` would start failing the build the day the archive rotates. 26.04
# ships 2.20.1, measured on 2026-11-10.
#
# What can be pinned is the range, the same half-open range setup/setup.sh enforces on a real machine.
# setup.sh is the only place it is written: e2e/tier3/container.sh reads ANSIBLE_CORE_MIN_VERSION and
# ANSIBLE_CORE_MAX_VERSION_EXCLUSIVE out of it and passes both as build arguments, so neither has a
# default here, and a build that is not given both fails below and names the harness. Every release
# inside the range still carries the ansiballz result-deserialization race documented in
# setup/ansible/ansible_architecture.md, because the upstream fix is unmerged, so the range is about
# running a version the playbook has been exercised on, not about escaping that bug.
#
# Checked at build time on purpose. An image outside the range is a broken image, and this fails the
# build in seconds rather than a scenario twenty-five minutes in.
ARG ANSIBLE_CORE_MIN_VERSION
ARG ANSIBLE_CORE_MAX_VERSION_EXCLUSIVE
RUN { [ -n "${ANSIBLE_CORE_MIN_VERSION}" ] && [ -n "${ANSIBLE_CORE_MAX_VERSION_EXCLUSIVE}" ]; } || { echo "the build arguments ANSIBLE_CORE_MIN_VERSION and ANSIBLE_CORE_MAX_VERSION_EXCLUSIVE were not both given. setup/setup.sh is the only place the accepted ansible-core range is written, and e2e/tier3/container.sh reads both out of it and passes them, so build this image through e2e/run.sh --tier 3, which runs container.sh" >&2; exit 1; } \
    && CORE="$(ansible-playbook --version | head -1)" python3 -c 'import os, re, sys; found = re.search("core ([0-9.]+)", os.environ["CORE"]); version = lambda s: tuple(int(n) for n in (re.findall("[0-9]+", s) + ["0", "0"])[:3]); low, high = os.environ["ANSIBLE_CORE_MIN_VERSION"], os.environ["ANSIBLE_CORE_MAX_VERSION_EXCLUSIVE"]; core = found.group(1) if found else ""; sys.exit(0 if found and version(low) <= version(core) < version(high) else "this image has ansible-core " + (core or "an unreadable version") + ", outside the range " + low + " <= version < " + high + " that setup/setup.sh accepts")'

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

# Checked directly against ubuntu:26.04: /lib is a symlink to /usr/lib on this
# merged-usr image, so /lib/systemd/systemd and /usr/lib/systemd/systemd name the
# same file, the one systemd-sysv installs above. /sbin/init does not exist in the
# base image at all and only appears once systemd-sysv is installed, at which point
# it is itself a further symlink down to this same binary, so CMD names the real
# file rather than the alias chain on top of it.
STOPSIGNAL SIGRTMIN+3
CMD ["/lib/systemd/systemd"]
