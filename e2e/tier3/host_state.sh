#!/usr/bin/env bash
#
# Tier 3: what a scenario container can see of the host kernel, read from inside the container.
#
# Usage:
#   host_state.sh record <dir> <label> <unit>...
#
# container.sh copies this file into every scenario container and runs it as root right after boot,
# after each pass of setup.sh and when it collects the run. Each call writes two files into <dir>:
#
#   host-state-<label>.txt  one line per loaded kernel module, swap area, and kernel, vm and fs
#                           sysctl. None of these belong to the container: a privileged container
#                           reads and writes the host kernel's own copy, so container.sh compares
#                           every later file against the boot one and fails the run on a difference.
#   host-guard-<label>.txt  one line per isolation breach, and nothing when there is none.
#
# Exits 0 when the guard found nothing, 1 when it found a breach, which it also prints, and 2 on
# misuse. The snapshot is written either way, so a breach never hides the rest of the evidence.
#
# This runs inside a scenario container, never in the gate, so it sources nothing from e2e/lib.

set -euo pipefail
IFS=$'\n\t'
export LC_ALL=C

# Sysctls the kernel changes by itself, so a difference in them says nothing about the run. Measured
# on 2026-10-18 by reading every key under kernel, vm and fs six times twenty seconds apart in a
# throwaway container, where exactly these changed with nothing running: the dentry, file and inode
# counters, the three fs.quota statistics, kernel.ns_last_pid and kernel.random.uuid. kernel.pty.nr
# counts open terminals and every docker exec opens or closes one.
SELF_CHANGING_SYSCTLS='^(fs\.dentry-state|fs\.file-nr|fs\.inode-[a-z]+|fs\.quota\..+|kernel\.random\..+|kernel\.ns_last_pid|kernel\.pty\.nr)$'

usage() {
    sed -n '5,6p' "$0" | sed 's/^# //' >&2
    exit 2
}

write_snapshot() {
    local sysctl_file key value

    cut -d' ' -f1 /proc/modules | sort | sed 's/^/module /'
    awk 'NR > 1 { print "swap", $1, $2, $3, $5 }' /proc/swaps | sort

    while IFS= read -r sysctl_file; do
        key="${sysctl_file#/proc/sys/}"
        key="${key//\//.}"
        [[ "${key}" =~ ${SELF_CHANGING_SYSCTLS} ]] && continue
        value="$( { tr '\t\n' '  ' <"${sysctl_file}"; } 2>/dev/null)" || continue
        printf 'sysctl %s = %s\n' "${key}" "${value% }"
    done < <(find /proc/sys/kernel /proc/sys/vm /proc/sys/fs \
                 -path /proc/sys/fs/binfmt_misc -prune -o -type f -print 2>/dev/null | sort)
}

# One line per breach on stdout. A masked unit is matched as a pattern, so a template such as
# systemd-zram-setup@.service also catches every instance of it.
write_breaches() {
    local detected unit listed
    local -a patterns=()

    if grep -q ' /proc/sys/fs/binfmt_misc ' /proc/self/mounts; then
        echo "binfmt_misc is mounted at /proc/sys/fs/binfmt_misc, which is the host kernel's one binary format table"
    fi

    detected="$(systemd-detect-virt --container 2>/dev/null || true)"
    if [[ "${detected}" != docker ]]; then
        echo "systemd-detect-virt --container printed '${detected:-nothing}' rather than docker, so systemd does not know it runs in a container"
    fi

    for unit in "$@"; do
        patterns+=("${unit/@./@*.}")
    done
    if ! listed="$(systemctl list-units --plain --no-legend --state=active,activating,reloading,deactivating "${patterns[@]}" 2>&1)"; then
        echo "systemctl list-units failed, so nothing proves the masked units stayed down: ${listed//$'\n'/ }"
        return 0
    fi
    [[ -z "${listed}" ]] || awk '{ print $1 " is " $3 " although container.sh masked it" }' <<<"${listed}"
}

main() {
    [[ "${1:-}" == record && $# -ge 3 ]] || usage
    local dir="$2"
    local label="$3"
    shift 3

    mkdir -p "${dir}"
    write_snapshot >"${dir}/host-state-${label}.txt"
    write_breaches "$@" >"${dir}/host-guard-${label}.txt"

    if [[ -s "${dir}/host-guard-${label}.txt" ]]; then
        cat "${dir}/host-guard-${label}.txt"
        return 1
    fi
}

main "$@"
