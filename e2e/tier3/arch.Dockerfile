# Tier 3 base image for Arch Linux scenario runs.
#
# Deliberately close to a fresh Arch install rather than convenient. Only what a
# real machine has before setup.sh runs is preinstalled: systemd (in the base
# image), sudo, and ansible-core with its Python. base-devel, git, rust and the AUR
# helpers are NOT here on purpose, because arch_core is supposed to install them and
# a preinstalled convenience would hide it if that ever broke.
#
# systemd runs as PID 1 so tasks that enable units are genuinely exercised. That
# needs --privileged and the host cgroup mount at run time, see arch_container.sh.
FROM archlinux:base

# One transaction, then drop the package cache so the image stays small.
RUN pacman -Syu --noconfirm --needed \
        sudo \
        ansible-core \
        which \
    && pacman -Scc --noconfirm

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
