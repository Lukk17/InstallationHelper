#!/usr/bin/env bash
#
# Tier 2: no two packages of the default Fedora set claim the same file.
#
# rpm refuses a transaction that installs a path another installed package already owns with
# different content, and dnf reports it only at the moment of installing. OpenCode desktop 2.0.29 and
# Lens both ship Electron's chrome-sandbox, so both rpms carry the build-id link
# /usr/lib/.build-id/aa/c9a26d3d137c8cedbe1c3f2deab3edd8f39f43, pointing into /opt/OpenCode in one
# and into /opt/Lens in the other, and on a real Fedora machine the second one failed with "file ...
# from install of opencode-2.0.29-1.x86_64 conflicts with file from package lens". Nothing before
# this could have said so: tier 2 asked whether each name and each location exists, which both did.
#
# So this downloads what the default set installs from a vendor, inside a throwaway non-privileged
# container of the image e2e/tier3/fedora.Dockerfile pins, and lists every file of every package with
# rpm -qp, without installing any of it. A vendor rpm is a dnf_url mapping that is on by default or an
# .rpm a role downloads under a toggle that is on by default. A vendor repository package is a package
# the default set asks dnf for, a mapping or a companion package, that dnf resolves from one of the
# repo_ids under third_party_repositories in vars/RedHat.yaml, together with everything it requires
# from such a repository. All of that is read out of the shipped files by e2e/lib/render_dnf_sources.py.
#
# It fails when two packages claim the same path that is not a directory, unless the route that
# installs one of them leaves that path out: a dnf_url mapping with exclude_path is installed by rpm
# with --excludepath, and setup/ansible/roles/software_installer/tasks/dynamic_install.yaml reads the
# same field. It fails as well when a repository, a download or a listing does not come back, naming
# it, because a package that was never listed is a package nobody checked.
#
# One download per call, for the reason recorded as defect class 9 in AGENTS.md: a batch loses the
# whole set to one failure and cannot name which one broke.
#
# It runs only on a GitHub-hosted runner, owner decision 91, and anywhere else it reports one SKIP and
# downloads nothing. On 2026-10-22 the downloads of a local tier 2 run filled the disk Docker writes
# to on the owner's computer (docs/regression_ledger.md 10.162). The sweep runs it in stage 1, in the
# "Tier 1 checks" job of .github/workflows/e2e-matrix.yml, with bash e2e/run.sh --tier 2 --only
# rpm_file_conflicts.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
# shellcheck source=../lib/throwaway_machine.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/throwaway_machine.sh"

if ! throwaway_machine_verdict "${GITHUB_ACTIONS:-}" "${RUNNER_OS:-}" "${RUNNER_ENVIRONMENT:-}" >/dev/null; then
    info "Tier 2: no two packages of the default Fedora set claim the same file"
    skip "rpm file conflicts, which downloads the default Fedora set and runs only on a GitHub-hosted runner" \
         "nothing was downloaded here (owner decision 91). The sweep runs it in stage 1, or dispatch: gh workflow run e2e-matrix.yml -f scenario=forced-failure -f distro=fedora"
    finish "rpm file conflicts"
fi

source "$(dirname "${BASH_SOURCE[0]}")/../lib/package_probe.sh"
# The shell end of the pinned values port, the one thing here that reads a pin. See setup/pinned_values.
source "${REPO_ROOT}/setup/pinned_values/pinned_values.sh"

require_cmd docker
require_python "the default Fedora set could not be read" "rpm file conflicts"

info "Tier 2: no two packages of the default Fedora set claim the same file"

image="$(probe_image_for fedora)"
if [[ -z "${image}" ]]; then
    fail "no image is pinned in e2e/tier3/fedora.Dockerfile, so nothing was downloaded" "${PROBE_TIER3_DIR}/fedora.Dockerfile"
    finish "rpm file conflicts"
fi

work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT

interpreter="$(pinned_values_python)" || { fail "the pinned values could not be read" "no Python 3.11 or newer"; finish "rpm file conflicts"; }
if ! "${interpreter}" "${PINNED_VALUES_CORE}" --json >"${work}/pins.json"; then
    fail "the pinned values could not be read, so no download location is known" "${PINNED_VALUES_CORE} --json failed"
    finish "rpm file conflicts"
fi
sources_status=0
"${PYTHON}" -I "${E2E_ROOT}/lib/render_dnf_sources.py" "${REPO_ROOT}" "${work}/pins.json" >"${work}/sources.tsv" || sources_status=$?
if [[ ${sources_status} -ne 0 ]]; then
    fail "render_dnf_sources.py exited ${sources_status}, so the default Fedora set is unknown" "its own error is above"
    finish "rpm file conflicts"
fi

mapfile -t vendor_ids < <(awk -F'\t' '$1 == "repoid" { print $2 }' "${work}/sources.tsv" | sort -u)
mapfile -t asked < <(awk -F'\t' '$1 == "package" { print $2 }' "${work}/sources.tsv" | sort -u)
declare -A excluded_of=()
rpm_labels=()
while IFS=$'\t' read -r kind label _ excluded; do
    [[ "${kind}" == rpm ]] || continue
    rpm_labels+=("${label}")
    [[ "${excluded}" != "-" ]] && excluded_of["${label}"]="${excluded}"
done <"${work}/sources.tsv"
repo_count="$(awk -F'\t' '$1 == "repo" || $1 == "repofile"' "${work}/sources.tsv" | wc -l)"
if [[ ${#vendor_ids[@]} -eq 0 || ${#asked[@]} -eq 0 || ${#rpm_labels[@]} -eq 0 || ${repo_count} -eq 0 ]]; then
    fail "the default Fedora set read as empty, so this check would prove nothing" \
         "${#vendor_ids[@]} vendor repository ids, ${repo_count} repositories, ${#asked[@]} packages, ${#rpm_labels[@]} vendor rpms"
    finish "rpm file conflicts"
fi

# The script travels as the container's command argument and nothing is bind-mounted, for the reason
# probe_missing_in_image in e2e/lib/package_probe.sh gives: this runs inside the gate container, whose
# temporary directories the daemon cannot see. Every value is quoted with printf %q on the way in.
{
    printf 'vendor_ids=%q\n' "|$(IFS='|'; echo "${vendor_ids[*]}")|"
    printf 'asked=('; printf ' %q' "${asked[@]}"; printf ' )\n'
    while IFS=$'\t' read -r kind a b _; do
        case "${kind}" in
            repo)     printf 'add_repo %q %q\n' "${a}" "${b}" ;;
            repofile) printf 'add_repofile %q %q\n' "${a}" "${b}" ;;
            rpm)      printf 'rpms+=(%q %q)\n' "${a}" "${b}" ;;
        esac
    done <"${work}/sources.tsv"
} >"${work}/inputs.sh"
cat >"${work}/probe.sh" <<'PROBE'
set -u
mkdir -p /work/repo /work/url
add_repo() {
    printf '[%s]\nname=%s\nbaseurl=%s\nenabled=1\ngpgcheck=0\nrepo_gpgcheck=0\n' "$1" "$1" "$2" > "/etc/yum.repos.d/$1.repo"
}
add_repofile() {
    if curl -fsSL --retry 3 --connect-timeout 20 -o "$1" "$2"; then
        sed -i -E 's/^(repo_)?gpgcheck=1/\1gpgcheck=0/' "$1"
    else
        echo "MISSING repository file $1 from $2"
    fi
}
rpms=()
PROBE
cat "${work}/inputs.sh" >>"${work}/probe.sh"
cat >>"${work}/probe.sh" <<'PROBE'
for id in $(dnf -q repolist --enabled 2>/dev/null | awk 'NR > 1 { print $1 }'); do
    case "${vendor_ids}" in
        *"|${id}|"*) dnf -q makecache --repo "${id}" >/dev/null 2>&1 || echo "MISSING repository ${id}, whose metadata did not download" ;;
    esac
done
# The packages the set asks for that a vendor repository provides, then what those require from one,
# until nothing new appears. A query reads the metadata dnf already holds and installs nothing, so one
# call answers for a whole list without losing anything to one name.
vendor_only() {
    while read -r name repo; do
        case "${vendor_ids}" in *"|${repo}|"*) echo "${name}" ;; esac
    done | sort -u
}
vendor_set="$(dnf -q repoquery --latest-limit 1 --qf '%{name} %{repoid}\n' "${asked[@]}" 2>/dev/null | vendor_only)"
while [ -n "${vendor_set}" ]; do
    required="$(dnf -q repoquery --providers-of=requires --latest-limit 1 --qf '%{name} %{repoid}\n' ${vendor_set} 2>/dev/null | vendor_only)"
    grown="$(printf '%s\n%s\n' "${vendor_set}" "${required}" | grep -v '^$' | sort -u)"
    [ "${grown}" = "${vendor_set}" ] && break
    vendor_set="${grown}"
done
for name in ${vendor_set}; do
    mkdir -p "/work/repo/${name}"
    if dnf -q download --destdir "/work/repo/${name}" "${name}" >/dev/null 2>&1 \
            && ls "/work/repo/${name}"/*.rpm >/dev/null 2>&1; then
        echo "GOT repository ${name}"
    else
        echo "MISSING repository package ${name}, which did not download"
    fi
done
i=0
while [ "${i}" -lt "${#rpms[@]}" ]; do
    label="${rpms[${i}]}" location="${rpms[$((i + 1))]}"
    i=$((i + 2))
    mkdir -p "/work/url/${label}"
    if curl -fsSL --retry 3 --connect-timeout 20 -o "/work/url/${label}/package.rpm" "${location}"; then
        echo "GOT vendor ${label}"
    else
        echo "MISSING vendor rpm ${label}, which did not download from ${location}"
    fi
done
for file in /work/repo/*/*.rpm /work/url/*/package.rpm; do
    [ -f "${file}" ] || continue
    label="$(basename "$(dirname "${file}")")"
    if ! rpm -qp --nosignature --qf "[FILE\t${label}\t%{=NAME}\t%{FILEMODES:perms}\t%{FILENAMES}\n]" "${file}" 2>/dev/null; then
        echo "MISSING listing of ${label}, which rpm could not read"
    fi
done
echo PROBE_COMPLETE
PROBE

# Downloading about a gigabyte and a half of rpms is minutes on a home line, so the bound is generous
# and reached only by a container that has stopped making progress.
probe_status=0
timeout 1800 docker run --rm "${image}" bash -c "$(cat "${work}/probe.sh")" >"${work}/probe.out" 2>"${work}/probe.err" || probe_status=$?
if ! grep -qx 'PROBE_COMPLETE' "${work}/probe.out"; then
    fail "the listing container did not finish, so no file was compared" \
         "docker run ${image} exited ${probe_status}: $(tail -3 "${work}/probe.err" | tr '\n' ' ')"
    finish "rpm file conflicts"
fi

mapfile -t missing < <(sed -n 's/^MISSING //p' "${work}/probe.out")
got_repo="$(grep -c '^GOT repository ' "${work}/probe.out" || true)"
got_vendor="$(grep -c '^GOT vendor ' "${work}/probe.out" || true)"
if [[ ${#missing[@]} -eq 0 ]]; then
    pass "every vendor repository answered and all ${got_repo} vendor repository packages and ${got_vendor} vendor rpms of the default set downloaded"
else
    fail "${#missing[@]} part(s) of the default Fedora set could not be listed, so nobody checked their files" \
         "$(printf '%s; ' "${missing[@]}")"
fi
if [[ ${got_vendor} -ne ${#rpm_labels[@]} ]]; then
    fail "${got_vendor} of the ${#rpm_labels[@]} vendor rpms the default set downloads were listed" "$(printf '%s ' "${rpm_labels[@]}")"
fi

# FILE <label> <name> <perms> <path>. A directory is shared by design. A path the route installing a
# package leaves out never reaches the disk, so it cannot conflict.
excluded_list="$(for label in "${!excluded_of[@]}"; do printf '%s\t%s\n' "${label}" "${excluded_of[${label}]}"; done)"
conflicts="$(
    awk -F'\t' -v excluded="${excluded_list}" '
        BEGIN {
            n = split(excluded, lines, "\n")
            for (i = 1; i <= n; i++) { if (split(lines[i], kv, "\t") == 2) skip[kv[1]] = kv[2] }
        }
        $1 != "FILE" || substr($4, 1, 1) == "d" { next }
        ($2 in skip) && ($5 == skip[$2] || index($5, skip[$2] "/") == 1) { next }
        {
            listed++
            if (!(($5, $3) in seen)) { seen[$5, $3] = 1; owners[$5] = owners[$5] (owners[$5] == "" ? "" : ", ") $3; count[$5]++ }
        }
        END {
            print "LISTED " listed + 0
            for (path in count) if (count[path] > 1) print path " is claimed by " owners[path]
        }' "${work}/probe.out" | sort
)"
listed="$(sed -n 's/^LISTED //p' <<<"${conflicts}")"
claims="$(grep -v '^LISTED ' <<<"${conflicts}" || true)"
if [[ "${listed:-0}" -eq 0 ]]; then
    fail "no file of any package was listed, so no conflict could have been found" "$(head -3 "${work}/probe.err" | tr '\n' ' ')"
elif [[ -z "${claims}" ]]; then
    pass "none of the ${listed} files those packages install is claimed by two of them, outside what each route leaves out"
else
    fail "$(grep -c . <<<"${claims}") path(s) are claimed by two packages of the default Fedora set, so rpm refuses whichever installs second" \
         "$(tr '\n' ';' <<<"${claims}")"
fi

finish "rpm file conflicts"
