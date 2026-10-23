#!/usr/bin/env bash
#
# Tier 1: every apt repository the playbook writes names the release its vendor publishes for this
# machine, on Debian, Ubuntu and their derivatives alike.
#
# Docker, Tailscale and HashiCorp publish one suite per Debian or Ubuntu release, and Docker and
# Tailscale one path per lineage, ubuntu or debian, and nothing for a derivative. The playbook wrote
# all three with Ansible's own distribution_release, which is the derivative's own name: zara on Linux
# Mint 22.2 and gigi on LMDE 7, measured with ansible-core 2.21.5, and the vendors answer 404 for
# both. The release now comes from one fact, ih_apt_codename in
# setup/ansible/tasks/derive_os_facts.yaml, and docs/manual/debian-ubuntu/install.sh applies the
# same rule by hand.
#
# Asserted:
#   1. no task file under setup/ansible reads the release from anywhere but the derivation, and the
#      Debian manual route does not ask lsb_release for it;
#   2. the derivation still sets ih_apt_codename, which keeps 1 from passing on an empty tree;
#   3. per os-release fixture of Debian 13, Ubuntu 26.04, Linux Mint 22 and 22.2, LMDE 6 and 7 and Pop!_OS 22.04,
#      the Docker, Tailscale and HashiCorp lines carry the lineage path and the codename the vendor
#      publishes, rendered from the shipped task files with the facts the shipped derivation gives;
#   4. no rendered line that depends on the release names a derivative's own codename, or names
#      a variable nothing defines;
#   5. the UPSTREAM_DISTRO and UPSTREAM_CODENAME lines of docs/manual/debian-ubuntu/install.sh give
#      the same answer per fixture, and its guide carries the same two lines;
#   6. the OpenRazer PPA is rendered for Pop!_OS, the one distribution os_release_ids names in
#      vars/Debian.yaml, with its Ubuntu codename, and for no other fixture, docs/regression_ledger.md
#      10.186.
# e2e/tier2/resolve_apt_repositories.sh then asks every vendor whether those lines answer.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
# shellcheck source=../lib/apt_repositories.sh
source "${E2E_ROOT}/lib/apt_repositories.sh"

require_cmd ansible-playbook
require_python "the apt repository lines could not be rendered" "apt vendor repositories"

DERIVATION="${ANSIBLE_DIR}/tasks/derive_os_facts.yaml"
MANUAL_SCRIPT="${REPO_ROOT}/docs/manual/debian-ubuntu/install.sh"
MANUAL_GUIDE="${REPO_ROOT}/docs/manual/debian-ubuntu/debian_ubuntu_manual_install.md"
FIXTURE_DIR="${E2E_ROOT}/tier1/os_release_fixtures"
RELEASE_READS='distribution_release|ansible_lsb|lsb_release|DISTRIB_CODENAME'

info "Tier 1: apt vendor repositories name the release the vendor publishes"

# --- 1. one place reads the release ----------------------------------------------------------------
# Whole-line comments are dropped first, because the files that avoid the trap document it.
reads="$(
    grep -rnE "${RELEASE_READS}" "${ANSIBLE_DIR}" --include='*.yaml' --include='*.yml' --include='*.j2' --include='*.sh' 2>/dev/null \
        | grep -v "^${DERIVATION}:" \
        | grep -vE ':[0-9]+:[[:space:]]*#' || true
)"
if [[ -z "${reads}" ]]; then
    pass "no task file under setup/ansible reads the release except tasks/derive_os_facts.yaml"
else
    fail "task files read the release themselves instead of ih_apt_codename, which names the derivative on Linux Mint and LMDE" \
         "$(sed -E "s|^${REPO_ROOT}/||" <<<"${reads}" | tr '\n' ' ')"
fi
manual_reads="$(grep -nE 'lsb_release' "${MANUAL_SCRIPT}" "${MANUAL_GUIDE}" 2>/dev/null | sed -E "s|^${REPO_ROOT}/||" || true)"
if [[ -z "${manual_reads}" ]]; then
    pass "the Debian manual install script and guide take the release from UPSTREAM_CODENAME, never lsb_release"
else
    fail "the Debian manual route asks lsb_release for the release, which names the derivative on Linux Mint and LMDE" \
         "$(tr '\n' ' ' <<<"${manual_reads}")"
fi

# --- 2. the exemption must not be vacuous ----------------------------------------------------------
if grep -q '^    ih_apt_codename: ' "${DERIVATION}" 2>/dev/null; then
    pass "tasks/derive_os_facts.yaml sets ih_apt_codename"
else
    fail "tasks/derive_os_facts.yaml no longer sets ih_apt_codename, so the release has no single source" "${DERIVATION}"
fi

# --- 3 and 4. render every line per fixture --------------------------------------------------------
if ! apt_repositories_render; then
    fail "the repository lines could not be rendered, so nothing below was asserted" "${APT_RENDER_FAULT}"
    finish "apt vendor repositories"
fi

# expect_line <fixture> <label> <substring>  ->  pass or fail on whether a rendered line carries it
expect_line() {
    local fixture="$1" label="$2" wanted="$3" lines
    lines="$(awk -F'\t' -v f="${fixture}" '$1 == f { print $5 }' <<<"${APT_LINES}")"
    if grep -qF -- "${wanted}" <<<"${lines}"; then
        pass "${fixture}: ${label} is ${wanted}"
    else
        fail "${fixture}: no rendered line for ${label} carries ${wanted}" \
             "$(grep -F "$(cut -d' ' -f1 <<<"${wanted}" | sed -E 's|^(https://[^/]+).*|\1|')" <<<"${lines}" | tr '\n' ' ')"
    fi
}

while IFS= read -r case_json; do
    [[ -z "${case_json}" ]] && continue
    fixture="$(apt_case_field "${case_json}" fixture)"
    base="$(apt_case_field "${case_json}" base)"
    codename="$(apt_case_field "${case_json}" codename)"
    own="$(sed -nE 's/^VERSION_CODENAME="?([^"]*)"?$/\1/p' "${FIXTURE_DIR}/${fixture}")"

    expect_line "${fixture}" "the Docker key" "https://download.docker.com/linux/${base}/gpg"
    expect_line "${fixture}" "the Docker repository" "https://download.docker.com/linux/${base} ${codename} stable"
    expect_line "${fixture}" "the Tailscale key" "https://pkgs.tailscale.com/stable/${base}/${codename}.noarmor.gpg"
    expect_line "${fixture}" "the Tailscale repository" "https://pkgs.tailscale.com/stable/${base} ${codename} main"
    expect_line "${fixture}" "the HashiCorp repository" "https://apt.releases.hashicorp.com ${codename} main"

    varying="$(awk -F'\t' -v f="${fixture}" '$1 == f && $3 == "1" { print $4 " -> " $5 }' <<<"${APT_LINES}")"
    wrong=""
    if [[ "${own}" != "${codename}" ]]; then
        wrong="$(grep -E "(^|[ /])${own}([ /.]|$)" <<<"${varying}" || true)"
    fi
    undefined="$(grep -F '<undefined:' <<<"${varying}" || true)"
    varying_count="$(grep -c . <<<"${varying}" || true)"
    if [[ "${varying_count}" -eq 0 ]]; then
        fail "${fixture}: no rendered line depends on the release or the lineage, so nothing here is proven" "${APT_LINES:0:300}"
    elif [[ -z "${wrong}${undefined}" ]]; then
        if [[ "${own}" != "${codename}" ]]; then
            pass "${fixture}: none of the ${varying_count} lines that depend on the release names the derivative's own ${own} or an undefined variable"
        else
            pass "${fixture}: none of the ${varying_count} lines that depend on the release names an undefined variable"
        fi
    else
        fail "${fixture}: rendered lines name the distribution's own codename ${own}, which its vendors do not publish, or an undefined variable" \
             "$(tr '\n' ' ' <<<"${wrong}${undefined}")"
    fi
done <<<"${APT_CASES}"

# --- 6. the OpenRazer PPA only where vars/Debian.yaml names the distribution ----------------------
while IFS= read -r case_json; do
    [[ -z "${case_json}" ]] && continue
    fixture="$(apt_case_field "${case_json}" fixture)"
    if [[ "${fixture}" == pop-os ]]; then
        expect_line "${fixture}" "the OpenRazer PPA" "https://ppa.launchpadcontent.net/openrazer/stable/ubuntu $(apt_case_field "${case_json}" codename) main"
    elif awk -F'\t' -v f="${fixture}" '$1 == f { print $5 }' <<<"${APT_LINES}" | grep -qF 'ppa.launchpadcontent.net/openrazer'; then
        fail "${fixture}: the OpenRazer PPA is rendered, and vars/Debian.yaml names it for Pop!_OS only" "$(awk -F'\t' -v f="${fixture}" '$1 == f && /openrazer/ { print $4 }' <<<"${APT_LINES}")"
    else
        pass "${fixture}: the OpenRazer PPA is not rendered"
    fi
done <<<"${APT_CASES}"

# --- 5. the manual route answers the same ----------------------------------------------------------
distro_line="$(grep -m1 -E '^UPSTREAM_DISTRO=' "${MANUAL_SCRIPT}" || true)"
codename_line="$(grep -m1 -E '^UPSTREAM_CODENAME=' "${MANUAL_SCRIPT}" || true)"
if [[ -z "${distro_line}" || -z "${codename_line}" ]]; then
    fail "docs/manual/debian-ubuntu/install.sh no longer sets UPSTREAM_DISTRO and UPSTREAM_CODENAME, so its repositories have no rule to compare" "${MANUAL_SCRIPT}"
else
    if grep -qxF -- "${distro_line}" "${MANUAL_GUIDE}" && grep -qxF -- "${codename_line}" "${MANUAL_GUIDE}"; then
        pass "the Debian guide carries the same UPSTREAM_DISTRO and UPSTREAM_CODENAME lines as install.sh"
    else
        fail "the Debian guide's UPSTREAM_DISTRO or UPSTREAM_CODENAME line differs from install.sh" "${MANUAL_GUIDE}"
    fi
    disagreements=()
    compared=0
    while IFS= read -r case_json; do
        [[ -z "${case_json}" ]] && continue
        fixture="$(apt_case_field "${case_json}" fixture)"
        wanted="$(apt_case_field "${case_json}" base) $(apt_case_field "${case_json}" codename)"
        # The two lines run as written, with only the os-release path pointed at the fixture.
        manual="$(
            # shellcheck disable=SC2034  # read by the eval below
            fixture_path="${FIXTURE_DIR}/${fixture}"
            # shellcheck disable=SC2016  # expanded by the eval below, where fixture_path is set
            os_release_ref='"${fixture_path}"'
            eval "${distro_line//\/etc\/os-release/${os_release_ref}}"
            eval "${codename_line//\/etc\/os-release/${os_release_ref}}"
            printf '%s %s' "${UPSTREAM_DISTRO}" "${UPSTREAM_CODENAME}"
        )"
        compared=$((compared + 1))
        [[ "${manual}" == "${wanted}" ]] || disagreements+=("${fixture}: install.sh gives '${manual}', the vendors publish '${wanted}'")
    done <<<"${APT_CASES}"
    if [[ ${compared} -gt 0 && ${#disagreements[@]} -eq 0 ]]; then
        pass "install.sh gives the same lineage and codename as ih_base and ih_apt_codename for all ${compared} fixtures"
    else
        fail "install.sh disagrees with the playbook about the lineage or codename" "$(printf '%s | ' "${disagreements[@]}")"
    fi
fi

finish "apt vendor repositories"
