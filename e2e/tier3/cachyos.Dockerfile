# Tier 3 base image for CachyOS scenario runs.
#
# CachyOS is Arch with its own repositories in front of Arch's, built for newer instruction sets,
# and that is exactly why it earns a container of its own rather than being assumed covered by the
# Arch one. A package name resolves against CachyOS's repositories first, so a name that exists in
# both can come from a different build, and a name that exists only in Arch's is still reachable.
# Neither of those is exercised by the Arch image.
#
# It is also the distribution most Linux gamers actually run: the Steam hardware survey for July
# 2026 puts it at 14.3 percent of Linux users, second only to SteamOS and ahead of plain Arch at
# 8.3 percent, and it has held first place on DistroWatch's page hits since mid-2025.
#
# The v3 tag is deliberate. CachyOS publishes a baseline image plus one per instruction-set level,
# and its installer selects v3 on essentially any processor from the last decade, so v3 is what a
# real machine gets. Testing the baseline would test a configuration almost nobody runs.
FROM cachyos/cachyos-v3:latest

# The same locale restoration the Arch image needs, for the same reason: a published Arch-family
# container strips /usr/share/i18n with NoExtract rules, so system_core's locale generation fails on
# a file every real install has. Suppressing that task instead would turn a genuine step into an
# untested gap.
#
# Only what a real CachyOS install has before setup.sh runs is added: sudo, ansible-core and which.
# base-devel, git, rust and the AUR helpers are deliberately absent, because arch_core installs them
# and a preinstalled convenience would hide it if that ever broke. systemd comes from the base image
# and runs as PID 1 so unit-enabling tasks are genuinely exercised, which needs --privileged and the
# host cgroup mount at run time, both handled by container.sh.
RUN sed -i -E '/^NoExtract.*(locale|i18n)/d' /etc/pacman.conf \
    && pacman -Syu --noconfirm --needed \
        sudo \
        ansible-core \
        which \
    && pacman -S --noconfirm --overwrite '*' glibc \
    && pacman -Scc --noconfirm

# The playbook runs as a normal user who escalates with sudo, matching how a person runs setup.sh.
# The sudoers file is named 00-e2e-runner so that site.yaml's cleanup, which removes
# 99-ansible-user, cannot take the harness's own escalation away mid-run.
ARG E2E_USER=lukk
RUN useradd --create-home --shell /bin/bash ${E2E_USER} \
    && install -d -m 0750 /etc/sudoers.d \
    && printf '%s ALL=(ALL) NOPASSWD: ALL\n' "${E2E_USER}" > /etc/sudoers.d/00-e2e-runner \
    && chmod 0440 /etc/sudoers.d/00-e2e-runner

# Ansible writes its temp dirs, fact cache and galaxy cache under the invoking user's home, per
# ansible.cfg. The parent .ansible directory has to belong to the user too, not just the leaves, or
# ansible-galaxy cannot create galaxy_cache alongside them.
RUN install -d -o ${E2E_USER} -g ${E2E_USER} /home/${E2E_USER}/.ansible \
    && install -d -o ${E2E_USER} -g ${E2E_USER} \
        /home/${E2E_USER}/.ansible/tmp \
        /home/${E2E_USER}/.ansible/facts-cache

STOPSIGNAL SIGRTMIN+3
CMD ["/usr/lib/systemd/systemd"]
