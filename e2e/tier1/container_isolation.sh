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
# script restarts, /proc/sys made read-only before systemd starts, the guard and host state record at boot,
# after each pass and at collection, and the refusal of a scenario that would rewrite the boot.
# Then it drives host_isolation_findings, lifted out of container.sh, over records written here, so
# the comparison that fails a run is itself proven to fail.
#
# Proven on 2026-10-18 by pointing E2E_REPO_ROOT at a copy of the tree at commit c4f06c2, which had
# none of this and failed 7 of 7, and at a copy of the finished tree with one mask, container=docker,
# one boot setting and the diff target in host_isolation_findings each broken, which failed exactly
# those 4 of 10. Since 2026-10-19 it also requires systemd-binfmt.service unmasked, the read-only
# /proc/sys entry and the mountinfo guard in host_state.sh, proven by running the gate on a copy of the
# finished tree with container.sh and host_state.sh taken back to commit 80a8529, which failed exactly
# those 3 of 12.

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
# What makes /proc/sys read-only, apart from the network namespace's own part, before systemd starts.
PROC_SYS_READ_ONLY_ENTRY_EXPECTED='mount --bind /proc/sys /proc/sys && mount -o remount,bind,ro,nosuid,nodev,noexec /proc/sys && mount --bind /proc/sys/net /proc/sys/net && mount -o remount,bind,rw,nosuid,nodev,noexec /proc/sys/net && exec "$0"'
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

# --- /proc/sys read-only before systemd starts ----------------------------------------------
proc_sys_gaps=()
grep -qxF -- "PROC_SYS_READ_ONLY_ENTRY='${PROC_SYS_READ_ONLY_ENTRY_EXPECTED}'" <<<"${code}" \
    || proc_sys_gaps+=("PROC_SYS_READ_ONLY_ENTRY is not the read-only mount sequence ending in exec \"\$0\"")
grep -qE -- '--entrypoint[= ]+/bin/sh([[:space:]]|$)' <<<"${run_block}" \
    || proc_sys_gaps+=("the container does not start under --entrypoint /bin/sh")
grep -qF -- '"${IMAGE}" -c "${PROC_SYS_READ_ONLY_ENTRY}" "${image_init}"' <<<"${run_block}" \
    || proc_sys_gaps+=("the image is not handed -c \"\${PROC_SYS_READ_ONLY_ENTRY}\" with its own CMD as \$0")
grep -qF -- "docker image inspect --format '{{index .Config.Cmd 0}}' \"\${IMAGE}\"" <<<"${code}" \
    || proc_sys_gaps+=("image_init is not read from the image's own CMD")
if [[ ${#proc_sys_gaps[@]} -eq 0 ]]; then
    pass "the scenario container makes /proc/sys read-only, apart from /proc/sys/net, before it hands PID 1 to systemd"
else
    proc_sys_gap_text="$(printf '%s, ' "${proc_sys_gaps[@]}")"
    fail "a package's sysctl.d file can still reach the host kernel through /proc/sys" "${proc_sys_gap_text%, }"
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
    if ! grep -qF '$5 == "/proc/sys"' "${HOST_STATE_SH}" || ! grep -qF '/proc/self/mountinfo' "${HOST_STATE_SH}" \
        || ! grep -qF '*,ro,*' "${HOST_STATE_SH}"; then
        guard_gaps+=("/proc/sys read-only in /proc/self/mountinfo")
    fi
    grep -qF '/proc/modules' "${HOST_STATE_SH}" || guard_gaps+=("/proc/modules")
    grep -qF '/proc/swaps' "${HOST_STATE_SH}" || guard_gaps+=("/proc/swaps")
    grep -qF '/proc/sys/kernel /proc/sys/vm /proc/sys/fs' "${HOST_STATE_SH}" || guard_gaps+=("kernel, vm and fs sysctls")
    if [[ ${#guard_gaps[@]} -eq 0 ]]; then
        pass "host_state.sh guards binfmt_misc, a read-only /proc/sys and container detection, and records modules, swap and sysctls"
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

# --- the comparison that fails a run ------------------------------------------------------
function_text="$(sed -n '/^host_isolation_findings()/,/^}/p' "${CONTAINER_SH}")"
if [[ -z "${function_text}" ]]; then
    fail "container.sh defines no host_isolation_findings, so nothing compares the host state records" \
         "expected a top-level function of that name in ${CONTAINER_SH}"
    finish "container isolation"
fi
eval "${function_text}"

records="$(mktemp -d)"
trap 'rm -rf -- "${records}"' EXIT
printf '%s\n' 'module overlay' 'swap /dev/zram0 partition 32770044 100' 'sysctl vm.swappiness = 60' >"${records}/host-state-boot.txt"
: >"${records}/host-guard-boot.txt"
cp "${records}/host-state-boot.txt" "${records}/host-state-after-pass1.txt"
: >"${records}/host-guard-after-pass1.txt"

findings="$(host_isolation_findings "${records}" after-pass1)"
assert_eq "host_isolation_findings: identical records give no finding" "" "${findings}"

printf '%s\n' 'module br_netfilter' 'module overlay' 'swap /dev/zram0 partition 32770044 100' 'sysctl vm.swappiness = 10' >"${records}/host-state-after-pass1.txt"
echo 'systemd-udevd.service is active although container.sh masked it' >"${records}/host-guard-after-pass1.txt"
findings="$(host_isolation_findings "${records}" after-pass1)"
finding_gaps=()
grep -qxF 'after-pass1: systemd-udevd.service is active although container.sh masked it' <<<"${findings}" || finding_gaps+=("the guard's breach")
grep -qxF 'after-pass1: new since boot: module br_netfilter' <<<"${findings}" || finding_gaps+=("the loaded module")
grep -qxF 'after-pass1: gone since boot: sysctl vm.swappiness = 60' <<<"${findings}" || finding_gaps+=("the old sysctl value")
grep -qxF 'after-pass1: new since boot: sysctl vm.swappiness = 10' <<<"${findings}" || finding_gaps+=("the new sysctl value")
if [[ ${#finding_gaps[@]} -eq 0 && "$(grep -c . <<<"${findings}")" -eq 4 ]]; then
    pass "host_isolation_findings names a breach, a loaded module and a changed sysctl, and nothing else"
else
    fail "host_isolation_findings does not name every change between two records" \
         "missing: ${finding_gaps[*]:-none}, it printed: $(tr '\n' '|' <<<"${findings}")"
fi

findings="$(host_isolation_findings "${records}" after-pass1 at-collect)"
if grep -qE '^at-collect: no host state record' <<<"${findings}"; then
    pass "host_isolation_findings reports a missing record as a finding rather than as a clean pass"
else
    fail "host_isolation_findings passes over a record that was never written" "it printed: $(tr '\n' '|' <<<"${findings}")"
fi

finish "container isolation"
