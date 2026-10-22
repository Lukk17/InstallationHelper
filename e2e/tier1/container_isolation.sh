#!/usr/bin/env bash
#
# Tier 1: a tier 3 scenario container cannot change the host's kernel through the routes it already
# has once.
#
# Every scenario container is privileged with systemd as PID 1, and until 2026-10-18 it also shared
# the host's cgroup namespace and had the host's /sys/fs/cgroup bound in writable. Privileged means no
# user namespace, so the binfmt_misc table, udev, kernel modules, swap and every sysctl no namespace
# holds are the host's own, and systemd did not know it was in a container. Measured on the owner's
# machine: AppImageLauncher's packages registered themselves in the host's binfmt_misc table, and an
# Arch defaults run reloaded and triggered udev for every device in the container's /dev, which is
# every host device.
#
# This reads container.sh and requires what closes those routes: --cgroupns=private and never the
# host's, no bind of /sys/fs/cgroup, container=docker in the container's environment, a read-only
# /dev/null over each unit that acts on the host kernel but none over a unit a package's maintainer
# script restarts, no read-only /proc/sys, the guard and host state record at boot, after each pass
# and at collection, and the refusal of a scenario that would rewrite the boot. Then it drives
# host_isolation_findings and host_isolation_information, lifted out of container.sh, over records
# written here, so the comparison that fails a run is itself proven to fail, and a changed kernel
# setting or module is proven to be reported without failing it.
#
# Proven on 2026-10-18 by pointing E2E_REPO_ROOT at a copy of the tree at commit c4f06c2, which had
# none of this and failed 7 of 7, and at a copy of the finished tree with one mask, container=docker,
# one boot setting and the diff target in host_isolation_findings each broken, which failed exactly
# those 4 of 10. Since 2026-10-19 it also requires systemd-binfmt.service unmasked, the read-only
# /proc/sys entry and the mountinfo guard in host_state.sh, proven by running the gate on a copy of the
# finished tree with container.sh and host_state.sh taken back to commit 80a8529, which failed exactly
# those 3 of 12. Owner decision 86 took the read-only /proc/sys out again on 2026-10-22, because it
# failed every Flatpak that applies extra data, and made a changed kernel setting or module information
# only, because tier 3 runs only on a throwaway GitHub-hosted runner. Since then it requires the
# read-only sequence and its mountinfo guard to be absent and a changed sysctl or module to be reported
# under host_isolation without failing the run. Proven on 2026-10-22 by running the gate on a copy of
# the tree at commit 674e8b0 carrying only this file, which failed 2 of 10, the read-only /proc/sys and
# the two missing functions, and on a copy of the finished tree with the mountinfo guard put back and
# host_isolation_findings failing on every difference again, which failed exactly those 2 of 15.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

CONTAINER_SH="${REPO_ROOT}/e2e/tier3/container.sh"
HOST_STATE_SH="${REPO_ROOT}/e2e/tier3/host_state.sh"
CONTAINER_LIMITS="${REPO_ROOT}/e2e/tier3/container_limits.yaml"

REQUIRED_MASKS=(
    proc-sys-fs-binfmt_misc.automount
    proc-sys-fs-binfmt_misc.mount
    systemd-udevd.service
    systemd-udevd-control.socket
    systemd-udevd-kernel.socket
    systemd-udev-trigger.service
    systemd-udev-settle.service
    systemd-sysctl.service
    procps.service
    systemd-modules-load.service
    systemd-timesyncd.service
    systemd-pstore.service
    systemd-zram-setup@.service
)
# Units a package's own maintainer script restarts, so masking one fails that package instead of
# protecting anything. AppImageLauncher's deb postinst and rpm %post end in `systemctl restart
# systemd-binfmt`, and GitHub sweep run 39231000107 failed every Fedora job and half configured dpkg on
# Debian, Ubuntu and Pop!_OS on the mask. The two binfmt_misc units above stay masked, which is what
# keeps systemd-binfmt.service skipped by its own ConditionPathIsMountPoint=/proc/sys/fs/binfmt_misc.
FORBIDDEN_MASKS=(systemd-binfmt.service)
REQUIRED_BOOT_SETTINGS=(setup_systemd_boot setup_grub remove_distro_grub remove_distro_systemd_boot setup_hibernate)

info "Tier 1: a scenario container is isolated from the host kernel"

for required in "${CONTAINER_SH}" "${CONTAINER_LIMITS}"; do
    if [[ ! -f "${required}" ]]; then
        fail "a file this check reads is missing, so none of it proves anything" "${required}"
        finish "container isolation"
    fi
done

# Comments say what used to be there, so only code lines are read.
code="$(grep -vE '^[[:space:]]*#' "${CONTAINER_SH}")"
run_block="$(sed -n '/docker run -d --name "${CONTAINER}"/,/"${IMAGE}"/p' <<<"${code}")"
if [[ -z "${run_block}" ]]; then
    fail "container.sh has no 'docker run -d --name \"\${CONTAINER}\"' block ending at \"\${IMAGE}\"" \
         "the scenario container is started some other way, so nothing below can say how it is isolated"
    finish "container isolation"
fi

# --- namespaces and environment ------------------------------------------------
if grep -qE -- '--cgroupns[= ]+host' <<<"${code}"; then
    fail "container.sh starts a scenario container in the host's cgroup namespace" \
         "$(grep -nE -- '--cgroupns[= ]+host' "${CONTAINER_SH}" | head -3 | tr '\n' ' ')"
elif grep -qE -- '--cgroupns[= ]+private' <<<"${run_block}"; then
    pass "the scenario container gets a private cgroup namespace"
else
    fail "the scenario container does not ask for --cgroupns=private" \
         "the daemon default decides it then, and Docker's default-cgroupns-mode can be host"
fi

if grep -qE '/sys/fs/cgroup' <<<"${code}"; then
    fail "container.sh binds /sys/fs/cgroup into a scenario container" \
         "$(grep -nE '/sys/fs/cgroup' "${CONTAINER_SH}" | grep -vE '^[0-9]+:[[:space:]]*#' | head -3 | tr '\n' ' ')"
else
    pass "nothing binds the host's /sys/fs/cgroup into a scenario container"
fi

if grep -qE -- '(-e|--env)[= ]+container=docker([[:space:]]|$)' <<<"${run_block}"; then
    pass "the scenario container carries container=docker, so systemd knows it runs in a container"
else
    fail "the scenario container does not carry container=docker" \
         "without it systemd may not detect the container and starts units that act on the host kernel"
fi

# --- masked units -----------------------------------------------------------------
masked_array="$(sed -n '/^MASKED_UNITS=(/,/^)/p' <<<"${code}" | sed '1d;$d' | tr -s ' \t' '\n\n' | grep -v '^$' || true)"
array_is_mounted=no
if grep -qF '"${mask_mounts[@]}"' <<<"${run_block}" \
    && grep -qF 'for masked_unit in "${MASKED_UNITS[@]}"; do' <<<"${code}" \
    && grep -qF 'mask_mounts+=(-v "/dev/null:/etc/systemd/system/${masked_unit}:ro")' <<<"${code}"; then
    array_is_mounted=yes
fi

unmasked=()
for unit in "${REQUIRED_MASKS[@]}"; do
    if grep -qF -- "/dev/null:/etc/systemd/system/${unit}:ro" <<<"${run_block}"; then
        continue
    fi
    if [[ "${array_is_mounted}" == yes ]] && grep -qxF -- "${unit}" <<<"${masked_array}"; then
        continue
    fi
    unmasked+=("${unit}")
done
if [[ ${#unmasked[@]} -eq 0 ]]; then
    pass "all ${#REQUIRED_MASKS[@]} units that act on the host kernel are bound read-only to /dev/null"
else
    fail "${#unmasked[@]} unit(s) that act on the host kernel are not masked in the scenario container" \
         "${unmasked[*]}"
fi

wrongly_masked=()
for unit in "${FORBIDDEN_MASKS[@]}"; do
    if grep -qF -- "/dev/null:/etc/systemd/system/${unit}" <<<"${run_block}" || grep -qxF -- "${unit}" <<<"${masked_array}"; then
        wrongly_masked+=("${unit}")
    fi
done
if [[ ${#wrongly_masked[@]} -eq 0 ]]; then
    pass "no unit a package's maintainer script restarts is masked, so AppImageLauncher's postinst and %post can finish"
else
    fail "${#wrongly_masked[@]} unit(s) a package's maintainer script restarts are masked, which fails that package" \
         "${wrongly_masked[*]}"
fi

# --- no read-only /proc/sys, owner decision 86 --------------------------------------------------
# bubblewrap writes /proc/sys/user/max_user_namespaces inside its own user namespace when flatpak passes
# it --disable-userns, so a read-only /proc/sys failed every Flatpak that applies extra data in GitHub
# sweep run 39260381281. The container starts under the image's own CMD with /proc/sys as Docker
# mounts it for a privileged container.
proc_sys_gaps=()
grep -qE -- '--entrypoint' <<<"${run_block}" \
    && proc_sys_gaps+=("the container starts under --entrypoint instead of the image's own CMD")
grep -qF -- 'PROC_SYS_READ_ONLY_ENTRY' <<<"${code}" \
    && proc_sys_gaps+=("container.sh still carries PROC_SYS_READ_ONLY_ENTRY")
grep -qE -- 'remount[^ ]*,ro[, ].*/proc/sys|/proc/sys.*remount[^ ]*,ro[, ]' <<<"${code}" \
    && proc_sys_gaps+=("container.sh still remounts /proc/sys read-only")
grep -qE -- '"\$\{IMAGE\}" >/dev/null$' <<<"${run_block}" \
    || proc_sys_gaps+=("the run block does not end in \"\${IMAGE}\" with nothing handed to the image")
if [[ -f "${HOST_STATE_SH}" ]] && grep -vE '^[[:space:]]*#' "${HOST_STATE_SH}" | grep -qE '/proc/self/mountinfo|\$5 == "/proc/sys"'; then
    proc_sys_gaps+=("host_state.sh still guards /proc/sys as read-only in /proc/self/mountinfo")
fi
if [[ ${#proc_sys_gaps[@]} -eq 0 ]]; then
    pass "the scenario container leaves /proc/sys as Docker mounts it, so bubblewrap can apply a Flatpak's extra data"
else
    proc_sys_gap_text="$(printf '%s, ' "${proc_sys_gaps[@]}")"
    fail "the read-only /proc/sys that failed every extra-data Flatpak is still there" "${proc_sys_gap_text%, }"
fi

# --- the guard and the host state records -------------------------------------------
missing_records=()
for label in boot after-pass1 after-pass2 at-collect; do
    grep -qE "record[^|]*[[:space:]]${label}([[:space:]]|$)" <<<"${code}" || missing_records+=("${label}")
done
if [[ ! -f "${HOST_STATE_SH}" ]]; then
    fail "e2e/tier3/host_state.sh is missing, so no scenario records what it can see of the host kernel" "${HOST_STATE_SH}"
elif [[ ${#missing_records[@]} -gt 0 ]]; then
    fail "container.sh does not record the host state at every point a run can change it" \
         "no record labelled: ${missing_records[*]}"
else
    pass "the host state is recorded at boot, after each pass and at collection"
fi

if [[ -f "${HOST_STATE_SH}" ]]; then
    guard_gaps=()
    grep -qF 'systemd-detect-virt --container' "${HOST_STATE_SH}" || guard_gaps+=("systemd-detect-virt")
    grep -qF '/proc/sys/fs/binfmt_misc' "${HOST_STATE_SH}" || guard_gaps+=("binfmt_misc mount")
    grep -qF '/proc/modules' "${HOST_STATE_SH}" || guard_gaps+=("/proc/modules")
    grep -qF '/proc/swaps' "${HOST_STATE_SH}" || guard_gaps+=("/proc/swaps")
    grep -qF '/proc/sys/kernel /proc/sys/vm /proc/sys/fs' "${HOST_STATE_SH}" || guard_gaps+=("kernel, vm and fs sysctls")
    if [[ ${#guard_gaps[@]} -eq 0 ]]; then
        pass "host_state.sh guards binfmt_misc and container detection, and records modules, swap and sysctls"
    else
        fail "host_state.sh no longer looks at everything the isolation depends on" "missing: ${guard_gaps[*]}"
    fi
fi

# --- settings that rewrite the host's boot ----------------------------------------------
boot_array="$(sed -n '/^HOST_BOOT_SETTINGS=(/p' <<<"${code}")"
boot_gaps=()
for setting in "${REQUIRED_BOOT_SETTINGS[@]}"; do
    grep -qE "[( ]${setting}[ )]" <<<"${boot_array}" || boot_gaps+=("${setting} is not refused")
    grep -qxE "${setting}:[[:space:]]*false" "${CONTAINER_LIMITS}" || boot_gaps+=("${setting} is not false in container_limits.yaml")
done
grep -qF 'for boot_setting in "${HOST_BOOT_SETTINGS[@]}"; do' <<<"${code}" || boot_gaps+=("nothing reads HOST_BOOT_SETTINGS")
if [[ ${#boot_gaps[@]} -eq 0 ]]; then
    pass "a scenario that would rewrite the boot loader, the kernel command line or the resume device is refused"
else
    boot_gap_text="$(printf '%s, ' "${boot_gaps[@]}")"
    fail "a scenario could still rewrite the boot of the machine the container runs on" "${boot_gap_text%, }"
fi

# --- the comparison that fails a run, and the one that only reports ---------------------------
missing_functions=()
for function_name in host_state_differences host_isolation_findings host_isolation_information; do
    function_text="$(sed -n "/^${function_name}()/,/^}/p" "${CONTAINER_SH}")"
    if [[ -z "${function_text}" ]]; then
        missing_functions+=("${function_name}")
        continue
    fi
    eval "${function_text}"
done
if [[ ${#missing_functions[@]} -gt 0 ]]; then
    fail "container.sh does not define every function that compares the host state records" \
         "missing top-level function(s) in ${CONTAINER_SH}: ${missing_functions[*]}"
    finish "container isolation"
fi

wiring_gaps=()
grep -qF 'mapfile -t isolation_information < <(host_isolation_information "${isolation_records}" "${isolation_labels[@]}")' <<<"${code}" \
    || wiring_gaps+=("collect_and_verify does not call host_isolation_information")
grep -qE 'echo "host_isolation: \$\{#isolation_information\[@\]\} .*information only, they do not fail the run"' <<<"${code}" \
    || wiring_gaps+=("result.txt has no host_isolation line for the information")
grep -qF 'if [[ ${#isolation_findings[@]} -eq 0 ]]; then' <<<"${code}" \
    || wiring_gaps+=("the pass or fail of the isolation does not read isolation_findings")
grep -qF "printf '  %s\\n' \"\${isolation_information[@]:0:60}\"" <<<"${code}" \
    || wiring_gaps+=("result.txt does not list the differences under that line")
if [[ ${#wiring_gaps[@]} -eq 0 ]]; then
    pass "result.txt reports a changed kernel setting or module under host_isolation, and only the findings decide the run"
else
    wiring_gap_text="$(printf '%s, ' "${wiring_gaps[@]}")"
    fail "the kernel setting and module differences are not reported the way owner decision 86 asks" "${wiring_gap_text%, }"
fi

records="$(mktemp -d)"
trap 'rm -rf -- "${records}"' EXIT
printf '%s\n' 'module overlay' 'swap /dev/zram0 partition 32770044 100' 'sysctl vm.swappiness = 60' >"${records}/host-state-boot.txt"
: >"${records}/host-guard-boot.txt"
cp "${records}/host-state-boot.txt" "${records}/host-state-after-pass1.txt"
: >"${records}/host-guard-after-pass1.txt"

findings="$(host_isolation_findings "${records}" after-pass1)"
information="$(host_isolation_information "${records}" after-pass1)"
assert_eq "host_isolation_findings: identical records give no finding" "" "${findings}"
assert_eq "host_isolation_information: identical records give no information" "" "${information}"

printf '%s\n' 'module br_netfilter' 'module overlay' 'swap /dev/zram1 partition 8388604 100' 'sysctl vm.swappiness = 10' >"${records}/host-state-after-pass1.txt"
printf '%s\n' 'systemd-udevd.service is active although container.sh masked it' \
    "binfmt_misc is mounted at /proc/sys/fs/binfmt_misc, which is the host kernel's one binary format table" >"${records}/host-guard-after-pass1.txt"
findings="$(host_isolation_findings "${records}" after-pass1)"
information="$(host_isolation_information "${records}" after-pass1)"

finding_gaps=()
grep -qxF 'after-pass1: systemd-udevd.service is active although container.sh masked it' <<<"${findings}" || finding_gaps+=("the masked unit breach")
grep -qxF "after-pass1: binfmt_misc is mounted at /proc/sys/fs/binfmt_misc, which is the host kernel's one binary format table" <<<"${findings}" || finding_gaps+=("the binfmt_misc breach")
grep -qxF 'after-pass1: gone since boot: swap /dev/zram0 partition 32770044 100' <<<"${findings}" || finding_gaps+=("the swap area gone")
grep -qxF 'after-pass1: new since boot: swap /dev/zram1 partition 8388604 100' <<<"${findings}" || finding_gaps+=("the swap area added")
if [[ ${#finding_gaps[@]} -eq 0 && "$(grep -c . <<<"${findings}")" -eq 4 ]]; then
    pass "host_isolation_findings fails the run on a guard breach, binfmt_misc included, and a changed swap area, and on nothing else"
else
    fail "host_isolation_findings does not fail the run on exactly the breaches and the swap areas" \
         "missing: ${finding_gaps[*]:-none}, it printed: $(tr '\n' '|' <<<"${findings}")"
fi

information_gaps=()
grep -qxF 'after-pass1: new since boot: module br_netfilter' <<<"${information}" || information_gaps+=("the loaded module")
grep -qxF 'after-pass1: gone since boot: sysctl vm.swappiness = 60' <<<"${information}" || information_gaps+=("the old sysctl value")
grep -qxF 'after-pass1: new since boot: sysctl vm.swappiness = 10' <<<"${information}" || information_gaps+=("the new sysctl value")
if [[ ${#information_gaps[@]} -eq 0 && "$(grep -c . <<<"${information}")" -eq 3 ]]; then
    pass "host_isolation_information reports a loaded module and a changed sysctl, and nothing else"
else
    fail "host_isolation_information does not report exactly the changed modules and sysctls" \
         "missing: ${information_gaps[*]:-none}, it printed: $(tr '\n' '|' <<<"${information}")"
fi

findings="$(host_isolation_findings "${records}" after-pass1 at-collect)"
if grep -qE '^at-collect: no host state record' <<<"${findings}"; then
    pass "host_isolation_findings reports a missing record as a finding rather than as a clean pass"
else
    fail "host_isolation_findings passes over a record that was never written" "it printed: $(tr '\n' '|' <<<"${findings}")"
fi

finish "container isolation"
