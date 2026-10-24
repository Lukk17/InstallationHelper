#!/usr/bin/env bash
#
# Tier 1: the wizard's checklist says which applications turning Snapd off skips on this machine.
#
# With install_snapd off the playbook installs no snapd and skips every mapping whose manager is snap,
# setup/ansible/tasks/snap_availability.yaml. The person ticking the checklist in setup/setup.sh has to
# learn that before the run, not from a [WARN] line forty minutes into it, so the checklist header
# carries snapd_note, built from snap_dependents. Until 2026-10-18 nothing said so anywhere, and on
# Debian snapd was installed whatever the toggle said.
#
# The list has to come from the mappings and from nothing else, the way the playbook's does, so a snap
# mapping added tomorrow is named without anybody editing the wizard. Asserted:
#   1. pick_software puts snapd_note into the checklist header, so the note reaches the screen at all.
#   2. On every family, and on every derivative merged over its family, snap_dependents names exactly the
#      toggles whose mapping has manager snap, compared with the same merge done here by a YAML loader.
#   3. Against a copy of the dictionaries carrying fixture snap mappings, one in a family and one that a
#      derivative turns into a snap mapping while it turns another family snap mapping into flatpak, it
#      names the fixtures and only those, and snapd_note names their labels.
#   4. snapd_note is empty when the checklist offers no Snapd entry, and says that nothing is skipped
#      when nothing on the machine installs through snap.
#   5. On every Debian-family os-release fixture, with a fixture snap mapping in place, snapd_note under
#      the os-release ID read the way setup.sh's detect_os reads it, and the lineage its debian_lineage
#      derives, says on Ubuntu itself, ID ubuntu, that snapd ships with the system and names nothing as
#      skipped, and everywhere else names the fixture, Pop!_OS and Linux Mint included, and the ID and
#      lineage it acts on are the id and base e2e/tier1/os_family_derivation.yaml expects the playbook
#      to derive for that fixture. Owner
#      decision 80: Ubuntu ships snapd, so the playbook neither installs nor removes it there, and
#      turning the toggle off skips nothing, which the checklist has to say rather than claiming the
#      opposite, as it did from commit 0de82cc. Owner decision 84: only Ubuntu itself, so an
#      Ubuntu-lineage derivative follows install_snapd like Debian, which commit c99ef74 got wrong.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

SETUP_SH="${REPO_ROOT}/setup/setup.sh"
FIXTURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/os_release_fixtures"

info "Tier 1: the wizard names what turning Snapd off skips"

require_python "the checklist names what turning Snapd off skips" "snap dependents menu"

functions_text="$(sed -n '/^format_label()/,/^}/p;/^debian_lineage()/,/^}/p;/^snap_dependents()/,/^}/p;/^snapd_note()/,/^}/p' "${SETUP_SH}")"
labels_text="$(sed -n '/^declare -A LABEL_OVERRIDES=(/,/^)$/p' "${SETUP_SH}")"
picker_text="$(sed -n '/^pick_software()/,/^}/p' "${SETUP_SH}")"
for name in format_label debian_lineage snap_dependents snapd_note; do
    if ! grep -q "^${name}() {" <<<"${functions_text}"; then
        fail "setup.sh defines ${name}" "it was not found, so the checklist cannot name what turning Snapd off skips"
        finish "snap dependents menu"
    fi
done

if grep -qE '^[[:space:]]*note="\$\(snapd_note\)"' <<<"${picker_text}" \
        && grep -qE 'header\+=.*\$\{note\}' <<<"${picker_text}"; then
    pass "pick_software puts snapd_note into the checklist header"
else
    fail "pick_software puts snapd_note into the checklist header" "the note is built and never shown"
fi

IFS=$'\n\t'
eval "${labels_text}"
eval "${functions_text}"

# expected_dependents <vars dir> <family> <os-release ID>  ->  install_<key> per line, by a YAML loader
expected_dependents() {
    "${PYTHON}" - "$1" "$2" "$3" <<'PYEOF'
import pathlib
import sys

import yaml

vars_dir, family, release_id = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
mapping = dict((yaml.safe_load((vars_dir / (family + '.yaml')).read_text(encoding='utf-8')) or {}).get('software_mapping') or {})
derivative = vars_dir / 'derivatives' / (release_id + '.yaml')
if release_id and derivative.is_file():
    mapping.update((yaml.safe_load(derivative.read_text(encoding='utf-8')) or {}).get('software_mapping') or {})
print('\n'.join(sorted('install_' + key for key, entry in mapping.items() if (entry or {}).get('manager') == 'snap')))
PYEOF
}

# family_of_id <os-release ID>  ->  the family whose dictionary the derivative is merged over
family_of_id() {
    local fixture like
    fixture="$(grep -lE "^ID=\"?$1\"?$" "${FIXTURE_DIR}"/* 2>/dev/null | sed -n 1p || true)"
    [[ -n "${fixture}" ]] || return 0
    like=" $(sed -nE 's/^ID_LIKE="?([^"]*)"?$/\1/p' "${fixture}") "
    case "${like}" in
        *" arch "*) echo Archlinux ;;
        *" debian "* | *" ubuntu "*) echo Debian ;;
        *" fedora "* | *" rhel "*) echo RedHat ;;
    esac
}

# The cases: every family on its own, then every derivative over its family.
cases=("Debian:" "RedHat:" "Archlinux:" "Darwin:")
for derivative in "${ANSIBLE_DIR}"/vars/derivatives/*.yaml; do
    [[ -f "${derivative}" ]] || continue
    id="$(basename "${derivative}" .yaml)"
    family="$(family_of_id "${id}")"
    if [[ -z "${family}" ]]; then
        fail "${id}: no os-release fixture names its family, so its merge was not compared" "${derivative}"
        continue
    fi
    cases+=("${family}:${id}")
done

# --- 2: the real dictionaries ----------------------------------------------------------------------
disagreements=()
for case in "${cases[@]}"; do
    OS_FAMILY="${case%%:*}" OS_RELEASE_ID="${case#*:}"
    wizard="$(snap_dependents)"
    loader="$(expected_dependents "${ANSIBLE_DIR}/vars" "${OS_FAMILY}" "${OS_RELEASE_ID}")"
    [[ "${wizard}" == "${loader}" ]] || disagreements+=("${case}: the wizard names [${wizard//$'\n'/ }], the mappings [${loader//$'\n'/ }]")
done
if [[ ${#disagreements[@]} -eq 0 ]]; then
    pass "on all ${#cases[@]} families and derivatives snap_dependents names exactly the toggles mapped to snap"
else
    fail "snap_dependents disagrees with the mappings" "$(printf '%s; ' "${disagreements[@]}")"
fi

# --- 3: fixture snap mappings ----------------------------------------------------------------------
# A copy of the dictionaries, with each fixture written as the first entry of software_mapping, which is
# where an ordinary edit puts a line and where the wizard's awk has to find it.
work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT
mkdir -p "${work}/ansible"
cp -r "${ANSIBLE_DIR}/vars" "${work}/ansible/vars"
add_mapping() {
    sed -i "/^software_mapping:/a\\  $2: { manager: \"$3\", package: \"$4\" }" "$1"
}
add_mapping "${work}/ansible/vars/Debian.yaml" fixture_snap_app snap fixture-snap-app
add_mapping "${work}/ansible/vars/Archlinux.yaml" fixture_snap_kept snap fixture-snap-kept
add_mapping "${work}/ansible/vars/Archlinux.yaml" fixture_snap_replaced snap fixture-snap-replaced
add_mapping "${work}/ansible/vars/Archlinux.yaml" fixture_flatpak_turned_snap flatpak org.example.Fixture
mkdir -p "${work}/ansible/vars/derivatives"
cat > "${work}/ansible/vars/derivatives/fixture_id.yaml" <<'YAML'
---
software_mapping:
  fixture_snap_replaced: { manager: "flatpak", package: "org.example.Replaced" }
  fixture_flatpak_turned_snap: { manager: "snap", package: "fixture-turned-snap" }
YAML

fixture_problems=()
for case in "Debian::install_fixture_snap_app" \
            "Archlinux::install_fixture_snap_kept install_fixture_snap_replaced" \
            "Archlinux:fixture_id:install_fixture_flatpak_turned_snap install_fixture_snap_kept" \
            "RedHat::"; do
    OS_FAMILY="${case%%:*}" rest="${case#*:}"
    OS_RELEASE_ID="${rest%%:*}" wanted="${rest#*:}"
    ANSIBLE_DIR="${work}/ansible"
    got="$(snap_dependents | tr '\n' ' ' | sed 's/ $//')"
    [[ "${got}" == "${wanted}" ]] || fixture_problems+=("${OS_FAMILY}${OS_RELEASE_ID:+ with ${OS_RELEASE_ID}}: named [${got}], expected [${wanted}]")
done
OS_FAMILY=Debian OS_RELEASE_ID="" ANSIBLE_DIR="${work}/ansible"
PRELOADED_KEYS=(install_git install_snapd install_fixture_snap_app)
note="$(snapd_note)"
[[ "${note}" == *'"Fixture snap app"'* ]] || fixture_problems+=("snapd_note on Debian does not name \"Fixture snap app\": ${note}")
if [[ ${#fixture_problems[@]} -eq 0 ]]; then
    pass "fixture snap mappings in a family and in a derivative are named, and one a derivative replaces is not"
else
    fail "snap_dependents does not follow the mappings" "$(printf '%s; ' "${fixture_problems[@]}")"
fi

# --- 4: the two quiet cases ------------------------------------------------------------------------
quiet_problems=()
# Read by the snapd_note eval'd out of setup.sh, which shellcheck cannot see.
# shellcheck disable=SC2034
PRELOADED_KEYS=(install_git install_fixture_snap_app)
note="$(snapd_note)"
[[ -z "${note}" ]] || quiet_problems+=("with no Snapd entry on the checklist the note still reads: ${note}")
OS_FAMILY=RedHat
# shellcheck disable=SC2034
PRELOADED_KEYS=(install_git install_snapd)
note="$(snapd_note)"
[[ "${note}" == *"skips no application"* ]] || quiet_problems+=("with no snap mapping the note does not say nothing is skipped: ${note}")
if [[ ${#quiet_problems[@]} -eq 0 ]]; then
    pass "snapd_note is empty without a Snapd entry and says nothing is skipped when nothing needs snap"
else
    fail "snapd_note says the wrong thing in a quiet case" "$(printf '%s; ' "${quiet_problems[@]}")"
fi

# --- 5: Ubuntu itself ships snapd ------------------------------------------------------------------
# The lineage and the os-release ID the playbook derives for each fixture, read from the play that drives
# derive_os_facts.yaml.
fixture_facts="$("${PYTHON}" - "${E2E_ROOT}/tier1/os_family_derivation.yaml" <<'PYEOF'
import sys

import yaml

for play in yaml.safe_load(open(sys.argv[1], encoding='utf-8')):
    for case in (play.get('vars') or {}).get('ih_cases') or []:
        if case.get('family') == 'Debian':
            print('%s %s %s' % (case['fixture'], case['base'], case['id']))
PYEOF
)"
id_problems=()
ubuntu_cases=0
derivative_cases=0
debian_cases=0
# shellcheck disable=SC2034
PRELOADED_KEYS=(install_git install_snapd install_fixture_snap_app)
OS_FAMILY=Debian ANSIBLE_DIR="${work}/ansible"
while IFS=" " read -r fixture base id; do
    [[ -n "${fixture}" ]] || continue
    # shellcheck source=/dev/null
    OS_RELEASE_ID="$(. "${FIXTURE_DIR}/${fixture}" 2>/dev/null; printf '%s\n' "${ID:-}")"
    DEBIAN_LINEAGE="$(debian_lineage "${FIXTURE_DIR}/${fixture}")"
    if [[ "${OS_RELEASE_ID}" != "${id}" || "${DEBIAN_LINEAGE}" != "${base}" ]]; then
        id_problems+=("${fixture}: setup.sh reads the ID ${OS_RELEASE_ID} on ${DEBIAN_LINEAGE} lineage, the playbook ${id} on ${base}")
        continue
    fi
    note="$(snapd_note)"
    if [[ "${id}" == ubuntu ]]; then
        ubuntu_cases=$((ubuntu_cases + 1))
        [[ "${note}" == *"ships with Ubuntu"* && "${note}" != *"skips"* && "${note}" != *"Fixture snap app"* ]] \
            || id_problems+=("${fixture}: on Ubuntu itself the note reads: ${note}")
        continue
    fi
    if [[ "${base}" == ubuntu ]]; then
        derivative_cases=$((derivative_cases + 1))
    else
        debian_cases=$((debian_cases + 1))
    fi
    [[ "${note}" == *'skips "Fixture snap app"'* && "${note}" != *"ships with Ubuntu"* ]] \
        || id_problems+=("${fixture}: with ID ${id} on ${base} lineage the note does not name \"Fixture snap app\" as skipped: ${note}")
done <<<"${fixture_facts}"
if [[ ${ubuntu_cases} -eq 0 || ${derivative_cases} -eq 0 || ${debian_cases} -eq 0 ]]; then
    id_problems+=("only ${ubuntu_cases} Ubuntu, ${derivative_cases} Ubuntu-lineage derivative and ${debian_cases} Debian-lineage fixtures were read out of os_family_derivation.yaml, so the three were not compared")
fi
if [[ ${#id_problems[@]} -eq 0 ]]; then
    pass "on ${ubuntu_cases} Ubuntu fixtures the note says snapd ships with the system and skips nothing, on ${derivative_cases} Ubuntu-lineage derivative and ${debian_cases} Debian-lineage fixtures it names the snap application"
else
    fail "snapd_note does not follow the os-release ID" "$(printf '%s; ' "${id_problems[@]}")"
fi

finish "snap dependents menu"
