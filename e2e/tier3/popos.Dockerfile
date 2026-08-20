# Tier 3 base image for a machine that identifies as Pop!_OS.
#
# Read this before trusting a green run on it, because what this image is and what it is not both
# matter.
#
# System76 publishes no container image for Pop!_OS. There is no official base to build on, and the
# only thing on Docker Hub is a zero-star personal snapshot, which would mean testing one stranger's
# machine rather than a distribution. So this image is Ubuntu with Pop!_OS's own /etc/os-release
# written over it, which is exactly what Pop!_OS is on the two axes this harness can test:
#
#   the family derivation      Pop publishes ID=pop with ID_LIKE="ubuntu debian" and UBUNTU_CODENAME,
#                              and Ansible's own table has never heard of it, so it answers with the
#                              distribution's own name and every os_family condition in this
#                              repository would go false. That is the defect the derived ih_family
#                              exists for, and this image is the only place it is exercised against a
#                              real playbook run rather than against a fixture.
#   the package set            identical to Ubuntu's, because Pop is Ubuntu plus System76's own
#                              repositories, and the playbook installs nothing from those.
#
# What it therefore does NOT prove: anything about System76's packages, their kernel, their firmware
# tooling, their NVIDIA handling, or a Pop-specific default that ships in one of their packages. If
# a defect lives there, this image cannot see it, and neither can any container.
#
# The os-release below is written from the base image's own values rather than copied from a fixed
# Pop release, on purpose. A file claiming Pop 22.04 on top of Ubuntu 26.04 packages would be a
# machine that has never existed, and a task keying on the codename would then be tested against a
# lie. This keeps VERSION_ID and UBUNTU_CODENAME honest to whatever Ubuntu is underneath and changes
# only the identity fields Pop actually changes. The real thing, captured from System76's own archive,
# is at e2e/tier1/os_release_fixtures/pop-os and is what the tier 1 derivation check asserts against.
FROM installationhelper-e2e-ubuntu:latest

# Written with the base image's own version fields so the result is internally consistent. Pop
# dpkg-diverts /etc/os-release onto /etc/pop-os/os-release on a real machine, and both paths are
# created here so anything reading either one finds the same answer.
RUN . /etc/os-release \
    && install -d /etc/pop-os \
    && printf '%s\n' \
        'NAME="Pop!_OS"' \
        "VERSION=\"${VERSION_ID} LTS\"" \
        'ID=pop' \
        'ID_LIKE="ubuntu debian"' \
        "PRETTY_NAME=\"Pop!_OS ${VERSION_ID}\"" \
        "VERSION_ID=\"${VERSION_ID}\"" \
        'HOME_URL="https://pop.system76.com"' \
        'SUPPORT_URL="https://support.system76.com"' \
        'BUG_REPORT_URL="https://github.com/pop-os/pop/issues"' \
        'PRIVACY_POLICY_URL="https://system76.com/privacy"' \
        "VERSION_CODENAME=${UBUNTU_CODENAME}" \
        "UBUNTU_CODENAME=${UBUNTU_CODENAME}" \
        'LOGO=distributor-logo-pop-os' \
        > /etc/pop-os/os-release \
    && cp /etc/pop-os/os-release /etc/os-release

# /etc/lsb-release matters as much as /etc/os-release here, and getting this wrong made the first
# version of this image test the easy case instead of the hard one.
#
# Ansible's Debian parser reads whichever distribution file it finds, and one line decides
# everything: `elif 'Ubuntu' in data: distribution = 'Ubuntu'`, a plain case-sensitive substring
# test, in module_utils/facts/system/distribution.py. The Ubuntu base image ships /etc/lsb-release
# carrying DISTRIB_ID=Ubuntu, so with only os-release replaced Ansible still answered Ubuntu, the
# family came out Debian on its own, and the derivation this image exists to exercise was never put
# under any strain. Measured, not assumed: the first build of this image reported
# family=Debian distribution=Ubuntu from inside the container.
#
# A real Pop machine does not look like that. pop-default-settings diverts /etc/lsb-release onto
# /etc/pop-os/lsb-release, and its generator writes DISTRIB_ID=${ID^}, the capitalised ID, so the
# file says DISTRIB_ID=Pop. Read from System76's own packaging rather than guessed:
# pop-os/default-settings, debian/pop-default-settings.postinst for the diversion list and
# src/lsb-release.sh for the contents.
RUN . /etc/os-release \
    && printf '%s\n' \
        "DISTRIB_ID=Pop" \
        "DISTRIB_RELEASE=${VERSION_ID}" \
        "DISTRIB_CODENAME=${UBUNTU_CODENAME}" \
        "DISTRIB_DESCRIPTION=\"${PRETTY_NAME}\"" \
        > /etc/pop-os/lsb-release \
    && cp /etc/pop-os/lsb-release /etc/lsb-release

# Asserted at build time rather than discovered during a run, and the second assertion is the one
# that matters. If the identity did not take, this image is Ubuntu wearing a different tag and every
# run on it proves nothing while looking like coverage. So the build refuses unless Ansible itself
# answers something other than Ubuntu.
#
# What running this actually measured, and it corrects what an earlier draft of this comment claimed.
# Ansible 2.19 does know Pop: its OS_FAMILY_MAP lists Pop!_OS under Debian, so inside this image it
# answers distribution=Pop!_OS with family=Debian, and the derived ih_family agrees rather than
# rescues. Pop is therefore not one of the distributions the derivation was written for. CachyOS,
# EndeavourOS and Nobara are, and none of them appears in that table.
#
# So the value of this image is two things rather than three. It runs the whole playbook on a machine
# whose ID is neither ubuntu nor debian, which is the shape of every derivative and which nothing
# else here exercises against real packages. And it is the canary for the day Ansible's table changes
# or Pop changes its identity, because the assertion below fails the build rather than letting a
# silent family fallback take a run down twenty minutes in.
#
# Family is deliberately not asserted here. Requiring Debian would encode Ansible's current table as
# a fact about Pop, and the point of ih_family is that this repository does not depend on it.
RUN . /etc/os-release \
    && test "${ID}" = pop \
    && printf '%s' "${ID_LIKE}" | grep -q ubuntu \
    && test -n "${UBUNTU_CODENAME}" \
    && echo "identity: ID=${ID} ID_LIKE=${ID_LIKE} UBUNTU_CODENAME=${UBUNTU_CODENAME}"

RUN REPORTED="$(ansible -i localhost, localhost -c local -m ansible.builtin.setup -a 'filter=ansible_distribution' 2>/dev/null | grep -oE '"ansible_distribution": "[^"]*"' | head -1)" \
    && echo "ansible reports ${REPORTED}" \
    && case "${REPORTED}" in \
        *Ubuntu*) echo "this image still looks like Ubuntu to Ansible, so it would not exercise a derivative at all" >&2; exit 1 ;; \
       esac

STOPSIGNAL SIGRTMIN+3
CMD ["/lib/systemd/systemd"]
