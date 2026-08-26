# Tier 3 base image for Fedora scenario runs.
#
# Deliberately close to a fresh Fedora install rather than convenient. Only what a
# real machine has before setup.sh runs is preinstalled: systemd, sudo, and
# ansible-core with its Python. Build tooling, git, curl and any package manager
# helper are NOT here on purpose, because fedora_core is supposed to install them
# and a preinstalled convenience would hide it if that ever broke.
#
# systemd runs as PID 1 so tasks that enable units are genuinely exercised. That
# needs --privileged and the host cgroup mount at run time, see container.sh.
#
# Fedora containers cannot build DKMS modules, because the running kernel belongs to
# the host rather than to the container. Anything in the playbook that depends on
# DKMS will report missing kernel headers here, which is an expected limitation of
# running under a container, not a regression to chase.
FROM fedora:44

# Fedora images use dnf5, not the older dnf/yum, confirmed by inspecting the image
# directly (dnf itself is a symlink to dnf5 here). fedora:44 ships ansible-core
# 2.20.7, already inside the project's 2.19/2.20 target, so nothing extra is needed
# to get a current enough version. sudo is already present in this base image, but
# it is still listed explicitly so the install list documents the real dependency
# and stays correct if a future Fedora base image drops it. which and procps-ng are
# both genuinely absent from the base image, confirmed by running it directly: ps
# does not exist at all, and neither does a which binary, so both are named here
# rather than assumed present the way they are on Debian and Ubuntu. systemd itself
# is also absent as a binary, and only its libraries are pulled in by other packages, so
# it has to be installed explicitly to get an init to run at all.
RUN dnf5 install -y \
        sudo \
        ansible-core \
        systemd \
        procps-ng \
        which \
    && dnf5 clean all

# ansible-core is whatever Fedora 44 publishes, and it cannot be pinned to an exact version here:
# the release repository carries exactly one version and updates replace it in place, so an exact
# `ansible-core-<version>` would start failing the build the day the repository rotates. fedora:44
# ships 2.20.7 today.
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

# Checked directly against fedora:44: /lib is already a symlink to /usr/lib, as it
# has been on Fedora for years, so /usr/lib/systemd/systemd is both the canonical
# and the only real path to the binary the systemd package installs above. There is
# no separate systemd-sysv split here the way there is on Debian and Ubuntu.
STOPSIGNAL SIGRTMIN+3
CMD ["/usr/lib/systemd/systemd"]
