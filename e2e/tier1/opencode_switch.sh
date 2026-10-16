#!/usr/bin/env bash
#
# Tier 1: the OpenCode version switch decides the same way for every family, removes the version not selected,
# and moves the data folder the selected version cannot open, both ways, without deleting anything. A switch to
# version 1 sets version 2 data aside and brings no version 1 backup back, so version 1 starts clean. A switch to
# version 2 brings the newest version 2 backup back.
#
# opencode_use_v1 picks version 1 or 2, and setup/ansible/tasks/opencode_version.yaml turns that into the npm
# package and the desktop route of each version, for site.yaml and verify_install.yaml alike. The role then removes
# the other version's desktop app with roles/ai_tools/tasks/opencode_desktop_other.yaml and moves the data folder
# with roles/ai_tools/tasks/opencode_data.yaml. Both of those change a real machine and neither can be shown by
# reading it, so opencode_switch.yaml runs the shipped files against fake flatpak, dpkg-query, apt-get, pacman,
# rpm and dnf commands and a fake data folder under a temporary directory, twice per case, the second time to
# prove nothing moves or is removed again.
#
# The fake databases carry only the text the real ones carry, CREATE TABLE `session` for version 1 and
# CREATE TABLE `session_v2` for version 2, which is what the switch searches for. That text was read out of the
# databases @opencode/cli 2.0.29 and opencode-ai 1.19.1 created in node:24-slim on 2026-10-15.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/wsl_delegate.sh"

delegate_to_wsl_when_no_ansible e2e/tier1/opencode_switch.sh

TIER1_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info "Tier 1: the OpenCode version switch"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
cp "${TIER1_DIR}/opencode_switch.yaml" "${TIER1_DIR}/opencode_switch_case.yaml" "${TIER1_DIR}/opencode_switch_pass.yaml" "${work}/"
ln -s "${ANSIBLE_DIR}/vars" "${work}/vars"
mkdir -p "${work}/bin" "${work}/home"

# One fake per command the switch can run on Linux. Each logs its arguments and answers from the case's
# "installed" file, one manager:package per line.
write_fake() {
    local name="$1" manager="$2" probe_flag="$3" remove_flag="$4"
    cat > "${work}/bin/${name}" <<FAKE
#!/usr/bin/env bash
state="\${IH_FAKE_STATE:?}"
echo "${name} \$*" >> "\${state}/calls.log"
pkg="\${*: -1}"
case " \$* " in
    *" ${probe_flag} "*)
        if [[ "${name}" == dpkg-query ]]; then
            grep -qx "${manager}:\${pkg}" "\${state}/installed" && printf 'install ok installed' && exit 0
            exit 1
        fi
        grep -qx "${manager}:\${pkg}" "\${state}/installed"
        ;;
    *" ${remove_flag} "*)
        grep -vx "${manager}:\${pkg}" "\${state}/installed" > "\${state}/installed.new" || true
        mv "\${state}/installed.new" "\${state}/installed"
        ;;
    *) exit 2 ;;
esac
FAKE
    chmod +x "${work}/bin/${name}"
}
write_fake flatpak flatpak info uninstall
write_fake dpkg-query dpkg -W __never__
write_fake apt-get dpkg __never__ remove
write_fake pacman pacman -Q -R
write_fake rpm rpm -q __never__
write_fake dnf rpm __never__ remove

# npm, for the shared helper the command line tool goes through, answering the three calls it makes. The output
# lines are the ones npm 11 prints, which the helper reads: "removed <n> packages" and "up to date".
cat > "${work}/bin/npm" <<'FAKE'
#!/usr/bin/env bash
state="${IH_FAKE_STATE:?}"
echo "npm $*" >> "${state}/calls.log"
pkg="$3"
case "$1" in
    list)
        grep -qx "npm:${pkg}" "${state}/installed" || exit 1
        printf '/fake/lib\n`-- %s@1.0.0\n' "${pkg}"
        ;;
    uninstall)
        if grep -qx "npm:${pkg}" "${state}/installed"; then
            grep -vx "npm:${pkg}" "${state}/installed" > "${state}/installed.new" || true
            mv "${state}/installed.new" "${state}/installed"
            echo "removed 1 package in 1s"
        else
            echo "up to date in 1s"
        fi
        ;;
    install)
        echo "npm:${pkg}" >> "${state}/installed"
        echo "added 1 package in 1s"
        ;;
    *) exit 2 ;;
esac
FAKE
chmod +x "${work}/bin/npm"
mkdir -p "${work}/home/.nvm"
printf 'nvm() { return 0; }\n' > "${work}/home/.nvm/nvm.sh"

# A fake that is not found falls through to the real command on this machine, and the switch removes packages
# with it. That happened while this check was written: a wrong fake directory reached the real pacman, which
# refused only because the check does not run as root. So every command a Linux route can run has to resolve to
# its fake under the PATH the play gives it, or nothing runs. The commands are read off the shipped table.
mapfile -t route_commands < <(
    sed -n '/opencode_desktop_commands:/,/^- name:/p' "${ANSIBLE_DIR}/tasks/opencode_version.yaml" \
        | grep -E '^ +(probe|remove): ' | grep -vE 'brew|defaults read|rm -rf' \
        | sed -E "s/^ +(probe|remove): [\"']?//; s/^DEBIAN_FRONTEND=[a-z]+ //" | awk '{print $1}' | sort -u
)
unfaked=()
for command_name in "${route_commands[@]}"; do
    [[ "$(PATH="${work}/bin:${PATH}" command -v "${command_name}")" == "${work}/bin/${command_name}" ]] \
        || unfaked+=("${command_name}")
done
route_commands+=(npm)
[[ "$(PATH="${work}/bin:${PATH}" command -v npm)" == "${work}/bin/npm" ]] || unfaked+=(npm)
if [[ ${#route_commands[@]} -lt 7 || ${#unfaked[@]} -gt 0 ]]; then
    fail "every command a Linux desktop route runs resolves to a fake, so nothing real is removed" \
         "read ${#route_commands[@]} commands (${route_commands[*]}), not faked: ${unfaked[*]:-none}"
    finish "OpenCode version switch"
fi
pass "every command a Linux desktop route runs resolves to a fake: ${route_commands[*]}"

# make_data <folder> <v1|v2|v2-wal|migrated> <marker>: a fake OpenCode data folder holding one version's database.
make_data() {
    mkdir -p "$1"
    case "$2" in
        v1) printf 'SQLite format 3\0CREATE TABLE `session` (\n' > "$1/opencode.db" ;;
        v2) printf 'SQLite format 3\0CREATE TABLE `session_v2` (\n' > "$1/opencode.db" ;;
        v2-wal) printf 'SQLite format 3\0' > "$1/opencode.db"
                printf 'WAL\0CREATE TABLE `session_v2` (\n' > "$1/opencode.db-wal" ;;
        migrated) printf 'SQLite format 3\0CREATE TABLE `session` (\0CREATE TABLE `session_v2` (\n' > "$1/opencode.db" ;;
    esac
    printf '%s\n' "$3" > "$1/marker"
}

# new_case <name> <installed lines...>: the state and data directories of one case.
new_case() {
    mkdir -p "${work}/cases/$1/state" "${work}/cases/$1/data"
    : > "${work}/cases/$1/state/calls.log"
    printf '%s\n' "${@:2}" | grep . > "${work}/cases/$1/state/installed" || true
}

# Version 2 selected, the version 1 Flathub app installed, version 1 data in the folder and a version 2 backup
# beside it whose database is still in the write-ahead log: the app goes, the version 1 data is set aside and
# the version 2 backup comes back.
new_case debian-to-v2 "flatpak:ai.opencode.opencode" "npm:opencode-ai"
make_data "${work}/cases/debian-to-v2/data/opencode" v1 "v1 data"
make_data "${work}/cases/debian-to-v2/data/opencode.v2-backup-20260101-000000" v2-wal "v2 backup"

# Version 1 selected, the version 2 .deb installed, version 2 data and no version 1 backup: the package goes and
# the folder is set aside, so version 1 starts clean.
new_case debian-to-v1 "dpkg:opencode" "npm:@opencode/cli"
make_data "${work}/cases/debian-to-v1/data/opencode" v2 "v2 data"

# Version 1 selected on Arch with version 2 data and two version 1 backups: the version 2 data is set aside and
# neither version 1 backup comes back, because version 1 starts clean, which the owner decided on 2026-10-15.
new_case arch-to-v1 "pacman:opencode-desktop-bin"
make_data "${work}/cases/arch-to-v1/data/opencode" v2 "v2 data"
make_data "${work}/cases/arch-to-v1/data/opencode.v1-backup-20260101-000000" v1 "older v1 backup"
make_data "${work}/cases/arch-to-v1/data/opencode.v1-backup-20260202-000000" v1 "newer v1 backup"

# Version 1 selected with no data folder and a version 1 backup beside where it would be: nothing moves, the
# backup is not brought back.
new_case v1-leaves-v1-backup
make_data "${work}/cases/v1-leaves-v1-backup/data/opencode.v1-backup-20260101-000000" v1 "v1 backup"

# Version 1 selected on Fedora: the version 2 .rpm goes.
new_case fedora-to-v1 "rpm:opencode"

# Version 2 selected with version 1 data and no version 2 backup: nothing moves, because version 2 migrates
# version 1 data in place, measured with 2.0.29 on 2026-10-15.
new_case fedora-to-v2-keeps-v1-data "flatpak:ai.opencode.opencode"
make_data "${work}/cases/fedora-to-v2-keeps-v1-data/data/opencode" v1 "v1 data"

# Version 2 selected on version 1 data that version 2 has already migrated, which carries both tables, with an
# older version 2 backup beside it: the folder is version 2 data and stays, the backup stays too.
new_case migrated-stays-v2
make_data "${work}/cases/migrated-stays-v2/data/opencode" migrated "migrated data"
make_data "${work}/cases/migrated-stays-v2/data/opencode.v2-backup-20260101-000000" v2 "older v2 backup"

# Version 2 selected on a machine that already has only version 2: nothing to do.
new_case already-v2 "dpkg:opencode"
make_data "${work}/cases/already-v2/data/opencode" v2 "v2 data"

case_json() {
    local name="$1" family="$2" use_v1="$3" run="$4" cli="${5:-false}"
    printf '{"name": "%s", "family": "%s", "use_v1": %s, "run": %s, "cli": %s, "state": "%s", "data": "%s"}' \
        "${name}" "${family}" "${use_v1}" "${run}" "${cli}" "${work}/cases/${name}/state" "${work}/cases/${name}/data"
}
cases=(
    "$(case_json decide-debian-v2 Debian false false)"
    "$(case_json decide-debian-v1 Debian true false)"
    "$(case_json decide-redhat-v2 RedHat false false)"
    "$(case_json decide-redhat-v1 RedHat true false)"
    "$(case_json decide-arch-v2 Archlinux false false)"
    "$(case_json decide-arch-v1 Archlinux true false)"
    "$(case_json decide-darwin-v2 Darwin false false)"
    "$(case_json decide-darwin-v1 Darwin true false)"
    "$(case_json debian-to-v2 Debian false true true)"
    "$(case_json debian-to-v1 Debian true true true)"
    "$(case_json arch-to-v1 Archlinux true true)"
    "$(case_json v1-leaves-v1-backup Archlinux true true)"
    "$(case_json fedora-to-v1 RedHat true true)"
    "$(case_json fedora-to-v2-keeps-v1-data RedHat false true)"
    "$(case_json migrated-stays-v2 Debian false true)"
    "$(case_json already-v2 Debian false true)"
)
extra="{\"ih_fake_bin\": \"${work}/bin\", \"ih_loader\": \"${ANSIBLE_DIR}/tasks/load_os_dict.yaml\", \"ih_version\": \"${ANSIBLE_DIR}/tasks/opencode_version.yaml\", \"ih_role\": \"${ANSIBLE_DIR}/roles/ai_tools/tasks\", \"ih_host_path\": \"${PATH}\", \"non_root_user\": \"$(id -un)\", \"non_root_home\": \"${work}/home\", \"ih_timeout\": \"timeout\", \"ih_cases\": [$(IFS=,; echo "${cases[*]}")]}"

# dual_logger is this repository's stdout callback and writes ~/installation_*.log on every play, so the
# default callback is used, as in derivative_merge.sh.
play_out="$(
    ANSIBLE_STDOUT_CALLBACK=default ANSIBLE_FORCE_COLOR=0 \
        ansible-playbook -i localhost, "${work}/opencode_switch.yaml" -e "${extra}" 2>&1 || true
)"
if ! grep -q "IH_OC_DONE cases=${#cases[@]}" <<<"${play_out}"; then
    fail "the switch play did not finish" "$(grep -E 'fatal:|FAILED!|failed=[1-9]|ERROR' <<<"${play_out}" | head -4 | tr '\n' ' ')"
    finish "OpenCode version switch"
fi

decided() { grep -oE "IH_OC_DECIDED case=$1 .*" <<<"${play_out}" | head -1 | tr -s ' ' | sed -E 's/"?$//'; }
passed() { grep -oE "IH_OC_PASS case=$1 pass=$2 removed=[A-Za-z]+ moves=[0-9]+" <<<"${play_out}" | head -1 | sed -E 's/.* removed=//'; }
cli_passed() { grep -oE "IH_OC_PASS case=$1 pass=$2 .* cli_removed=[A-Za-z]+ cli_installed=[A-Za-z]+" <<<"${play_out}" | head -1 | sed -E 's/.* cli_removed=/removed=/; s/ cli_installed=/ installed=/'; }

expect_decision() {
    local name="$1" want="$2" got
    got="$(decided "${name}")"
    if [[ "${got}" == *"${want}"* ]]; then
        pass "${name}: ${want}"
    else
        fail "${name}: the decision is not ${want}" "${got:-no decision was reported}"
    fi
}
expect_decision decide-debian-v2 "version=v2 other=v1 cli=@opencode/cli other_cli=opencode-ai route=apt_url:opencode other_route=flatpak:ai.opencode.opencode mapped=apt_url:opencode v1key=absent"
expect_decision decide-debian-v1 "version=v1 other=v2 cli=opencode-ai other_cli=@opencode/cli route=flatpak:ai.opencode.opencode other_route=apt_url:opencode mapped=flatpak:ai.opencode.opencode v1key=absent"
expect_decision decide-redhat-v2 "route=dnf_url:opencode other_route=flatpak:ai.opencode.opencode mapped=dnf_url:opencode"
expect_decision decide-redhat-v1 "route=flatpak:ai.opencode.opencode other_route=dnf_url:opencode mapped=flatpak:ai.opencode.opencode"
expect_decision decide-arch-v2 "route=aur:opencode-desktop-bin other_route=flatpak:ai.opencode.opencode mapped=aur:opencode-desktop-bin"
expect_decision decide-arch-v1 "route=flatpak:ai.opencode.opencode other_route=aur:opencode-desktop-bin mapped=flatpak:ai.opencode.opencode"
expect_decision decide-darwin-v2 "route=brew_cask:opencode-desktop other_route=macos_app:/Applications/OpenCode.app mapped=brew_cask:opencode-desktop"
expect_decision decide-darwin-v1 "route=macos_app:/Applications/OpenCode.app other_route=brew_cask:opencode-desktop mapped=none v1key=absent"

expect_passes() {
    local name="$1" first="$2"
    assert_eq "${name}: the first pass removes and moves what it should" "${first}" "$(passed "${name}" 1)"
    assert_eq "${name}: the second pass removes and moves nothing" "False moves=0" "$(passed "${name}" 2)"
}
data_of() { cat "${work}/cases/$1/data/$2/marker" 2>/dev/null || echo "absent"; }
backups_of() { (cd "${work}/cases/$1/data" && ls -1d "opencode.$2-backup-"* 2>/dev/null | wc -l | tr -d ' '); }
installed_of() { tr '\n' ' ' < "${work}/cases/$1/state/installed" | sed 's/ $//'; }

expect_passes debian-to-v2 "True moves=2"
assert_eq "debian-to-v2: the version 1 Flathub app and opencode-ai are gone and @opencode/cli is installed" "npm:@opencode/cli" "$(installed_of debian-to-v2)"
assert_eq "debian-to-v2: the first pass removes opencode-ai and installs @opencode/cli" "removed=True installed=True" "$(cli_passed debian-to-v2 1)"
assert_eq "debian-to-v2: the second pass leaves the command line tool alone" "removed=False installed=False" "$(cli_passed debian-to-v2 2)"
assert_eq "debian-to-v2: the version 2 backup is back in the folder" "v2 backup" "$(data_of debian-to-v2 opencode)"
assert_eq "debian-to-v2: the version 1 data is in one version 1 backup" "1 v1 data" "$(backups_of debian-to-v2 v1) $(cat "${work}"/cases/debian-to-v2/data/opencode.v1-backup-*/marker)"
assert_eq "debian-to-v2: no version 2 backup is left over" "0" "$(backups_of debian-to-v2 v2)"

expect_passes debian-to-v1 "True moves=1"
assert_eq "debian-to-v1: the version 2 .deb and @opencode/cli are gone and opencode-ai is installed" "npm:opencode-ai" "$(installed_of debian-to-v1)"
assert_eq "debian-to-v1: the first pass removes @opencode/cli and installs opencode-ai" "removed=True installed=True" "$(cli_passed debian-to-v1 1)"
assert_eq "debian-to-v1: the second pass leaves the command line tool alone" "removed=False installed=False" "$(cli_passed debian-to-v1 2)"
assert_eq "debian-to-v1: the folder is free for version 1" "absent" "$(data_of debian-to-v1 opencode)"
assert_eq "debian-to-v1: the version 2 data is in one version 2 backup" "1 v2 data" "$(backups_of debian-to-v1 v2) $(cat "${work}"/cases/debian-to-v1/data/opencode.v2-backup-*/marker)"

expect_passes arch-to-v1 "True moves=1"
assert_eq "arch-to-v1: the version 2 AUR package is gone" "" "$(installed_of arch-to-v1)"
assert_eq "arch-to-v1: the folder is free, so version 1 starts clean" "absent" "$(data_of arch-to-v1 opencode)"
assert_eq "arch-to-v1: the version 2 data is in one version 2 backup" "1 v2 data" "$(backups_of arch-to-v1 v2) $(cat "${work}"/cases/arch-to-v1/data/opencode.v2-backup-*/marker)"
assert_eq "arch-to-v1: the older version 1 backup is untouched" "older v1 backup" "$(data_of arch-to-v1 opencode.v1-backup-20260101-000000)"
assert_eq "arch-to-v1: the newer version 1 backup is untouched" "newer v1 backup" "$(data_of arch-to-v1 opencode.v1-backup-20260202-000000)"

expect_passes v1-leaves-v1-backup "False moves=0"
assert_eq "v1-leaves-v1-backup: no folder is made from the version 1 backup" "absent" "$(data_of v1-leaves-v1-backup opencode)"
assert_eq "v1-leaves-v1-backup: the version 1 backup stays where it was" "v1 backup" "$(data_of v1-leaves-v1-backup opencode.v1-backup-20260101-000000)"

expect_passes fedora-to-v1 "True moves=0"
assert_eq "fedora-to-v1: the version 2 .rpm is gone" "" "$(installed_of fedora-to-v1)"

expect_passes fedora-to-v2-keeps-v1-data "True moves=0"
assert_eq "fedora-to-v2-keeps-v1-data: version 1 data stays for version 2 to migrate" "v1 data" "$(data_of fedora-to-v2-keeps-v1-data opencode)"

expect_passes migrated-stays-v2 "False moves=0"
assert_eq "migrated-stays-v2: data version 2 migrated from version 1 counts as version 2 and stays" "migrated data" "$(data_of migrated-stays-v2 opencode)"
assert_eq "migrated-stays-v2: the older version 2 backup is untouched" "older v2 backup" "$(data_of migrated-stays-v2 opencode.v2-backup-20260101-000000)"

expect_passes already-v2 "False moves=0"
assert_eq "already-v2: the selected version 2 .deb is left alone" "dpkg:opencode" "$(installed_of already-v2)"
assert_eq "already-v2: the version 2 data stays" "v2 data" "$(data_of already-v2 opencode)"

# The removal says what it removed, in the words the owner asked for, and every move says where it went.
if grep -q '\[INFO\] removed OpenCode v1 desktop because v2 is selected' <<<"${play_out}" \
    && grep -q '\[INFO\] removed OpenCode v2 desktop because v1 is selected' <<<"${play_out}"; then
    pass "a removal is logged as [INFO] removed OpenCode <version> desktop because <version> is selected"
else
    fail "a desktop removal is not logged with the [INFO] line" "$(grep -o '\[INFO\] removed[^"]*' <<<"${play_out}" | head -2 | tr '\n' ' ')"
fi
if grep -q '"msg": "\[INFO\] removed OpenCode v2 command line tool, @opencode/cli, because v1 is selected"' <<<"${play_out}" \
    && grep -q '"msg": "\[INFO\] removed OpenCode v1 command line tool, opencode-ai, because v2 is selected"' <<<"${play_out}"; then
    pass "a command line tool removal is logged as [INFO] removed OpenCode <version> command line tool, <package>, because <version> is selected"
else
    fail "a command line tool removal is not logged with the [INFO] line" "$(grep -o '\[INFO\] removed OpenCode v[12] command[^"]*' <<<"${play_out}" | head -2 | tr '\n' ' ')"
fi
moves_logged="$(grep -oE '"msg": "\[INFO\] moved [^"]*' <<<"${play_out}" | grep -c . || true)"
assert_eq "every data folder move is named by its own [INFO] line, four moves across the cases" "4" "${moves_logged}"

finish "OpenCode version switch"
