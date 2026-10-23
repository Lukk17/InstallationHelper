#!/usr/bin/env bash
#
# Builds the tools into the gate image. Run by e2e/gate/Dockerfile while the image builds, as root,
# one step per call, never on the machine that starts the harness.
#
# Usage:
#   provision.sh tools                    PowerShell, Pester, ShellCheck and the Python tools
#   provision.sh collections              the Ansible collections setup/ansible/requirements.yaml names
#   provision.sh ansible-range            refuse an ansible-core outside the range setup/setup.sh accepts
#   provision.sh user <uid> <gid>         the unprivileged user every check runs as
#
# Every version and every download comes from setup/pinned_values/pinned_values.toml through its
# shell reader, and every download is refused unless its SHA-256 matches the pin.
#
# Exit codes: 0 done, 1 a step failed, 2 misuse.

set -euo pipefail

PROVISION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../lib/host.sh
source "${PROVISION_DIR}/../lib/host.sh"

GATE_PYTHON_DIR="/opt/gate-python"
GATE_PWSH_DIR="/opt/microsoft/powershell/7"
GATE_MODULES_DIR="/usr/local/share/powershell/Modules"
GATE_COLLECTIONS_DIR="/usr/share/ansible/collections"
GATE_USER="gate"

# The image is the gate from its first tool onwards, so the checks' own helpers in common.sh can be
# reused here instead of written a second time.
enter_gate() {
    printf 'installationhelper e2e gate\n' > "${E2E_GATE_MARKER}"
    export "${E2E_GATE_SWITCH}=1"
    # shellcheck source=../lib/common.sh
    source "${PROVISION_DIR}/../lib/common.sh"
    find_runnable_python >/dev/null
}

# fetch_verified <url> <sha256> <destination>  downloads, and keeps the file only when it matches
fetch_verified() {
    local url="$1" expected="$2" destination="$3" actual
    fetch_url provision "${url}" "${destination}" || return 1
    actual="$(sha256_of "${destination}")"
    if [[ "${actual}" != "${expected}" ]]; then
        rm -f "${destination}"
        printf 'provision: %s does not match its pinned SHA-256\n     expected %s\n     actual   %s\n' \
            "${url}" "${expected}" "${actual}" >&2
        return 1
    fi
}

install_pwsh() {
    local url sha
    case "$(uname -m)" in
        x86_64)
            url="$(pinned_value gate_pwsh_linux_x86_64_url)"
            sha="$(pinned_value gate_pwsh_linux_x86_64_sha256)" ;;
        aarch64|arm64)
            url="$(pinned_value gate_pwsh_linux_aarch64_url)"
            sha="$(pinned_value gate_pwsh_linux_aarch64_sha256)" ;;
        *)
            printf 'provision: no PowerShell release is pinned for %s\n' "$(uname -m)" >&2
            return 1 ;;
    esac

    local archive
    archive="$(mktemp)"
    fetch_verified "${url}" "${sha}" "${archive}"
    mkdir -p "${GATE_PWSH_DIR}"
    tar -xzf "${archive}" -C "${GATE_PWSH_DIR}"
    rm -f "${archive}"
    chmod +x "${GATE_PWSH_DIR}/pwsh"
    ln -sf "${GATE_PWSH_DIR}/pwsh" /usr/local/bin/pwsh

    local reported wanted
    reported="$(pwsh -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.ToString()')"
    wanted="$(pinned_value gate_pwsh_version)"
    [[ "${reported}" == "${wanted}" ]] || {
        printf 'provision: pwsh reports %s where %s is pinned\n' "${reported}" "${wanted}" >&2
        return 1
    }
}

install_pester() {
    local version package target
    version="$(pinned_value gate_pester_version)"
    package="$(mktemp)"
    fetch_verified "$(pinned_value gate_pester_url)" "$(pinned_value gate_pester_sha256)" "${package}"
    target="${GATE_MODULES_DIR}/Pester/${version}"
    mkdir -p "${target}"
    unzip -q -o "${package}" -d "${target}"
    rm -rf "${package}" "${target}/_rels" "${target}/package" "${target}/[Content_Types].xml" "${target}/Pester.nuspec"

    local reported
    reported="$(pwsh -NoProfile -NonInteractive -Command \
        '(Get-Module -ListAvailable Pester | Sort-Object Version -Descending | Select-Object -First 1).Version.ToString()')"
    [[ "${reported}" == "${version}" ]] || {
        printf 'provision: PowerShell finds Pester %s where %s is pinned\n' "${reported:-nothing}" "${version}" >&2
        return 1
    }
}

install_shellcheck() {
    local binary
    binary="$(pinned_shellcheck)"
    install -m 0755 "${binary}" /usr/local/bin/shellcheck
    rm -rf "${REPO_ROOT}/e2e/.cache"
}

install_python_tools() {
    python3 -m venv "${GATE_PYTHON_DIR}"
    "${GATE_PYTHON_DIR}/bin/pip" install --no-cache-dir --disable-pip-version-check \
        "ansible-core==$(pinned_value gate_ansible_core_version)" \
        "yamllint==$(pinned_value gate_yamllint_version)" \
        "ansible-lint==$(pinned_value gate_ansible_lint_version)"
}

step_tools() {
    enter_gate
    install_pwsh
    install_pester
    install_shellcheck
    install_python_tools
}

step_collections() {
    ansible-galaxy collection install --no-cache -p "${GATE_COLLECTIONS_DIR}" \
        -r "${PROVISION_DIR}/../../setup/ansible/requirements.yaml"
}

step_ansible_range() {
    local setup_sh="${PROVISION_DIR}/../../setup/setup.sh" low high core
    low="$(sed -n 's/^ANSIBLE_CORE_MIN_VERSION="\([0-9.]*\)"$/\1/p' "${setup_sh}")"
    high="$(sed -n 's/^ANSIBLE_CORE_MAX_VERSION_EXCLUSIVE="\([0-9.]*\)"$/\1/p' "${setup_sh}")"
    core="$(ansible-playbook --version | sed -n '1s/.*core \([0-9.]*\)\].*/\1/p')"
    if [[ -z "${low}" || -z "${high}" || -z "${core}" ]]; then
        printf 'provision: could not read the range [%s, %s) out of %s or the version [%s] of ansible-playbook\n' \
            "${low}" "${high}" "${setup_sh}" "${core}" >&2
        return 1
    fi
    if [[ "$(printf '%s\n%s\n' "${low}" "${core}" | sort -V | head -1)" != "${low}" \
          || "${core}" == "${high}" \
          || "$(printf '%s\n%s\n' "${core}" "${high}" | sort -V | head -1)" != "${core}" ]]; then
        printf 'provision: ansible-core %s is outside the range %s <= version < %s that setup/setup.sh accepts\n' \
            "${core}" "${low}" "${high}" >&2
        return 1
    fi
    printf 'provision: ansible-core %s, inside %s <= version < %s\n' "${core}" "${low}" "${high}"
}

step_user() {
    local uid="$1" gid="$2"
    getent group "${gid}" >/dev/null || groupadd --gid "${gid}" "${GATE_USER}"
    useradd --no-log-init --create-home --uid "${uid}" --gid "${gid}" --shell /bin/bash "${GATE_USER}"
    printf '%s ALL=(ALL) NOPASSWD: ALL\n' "${GATE_USER}" > "/etc/sudoers.d/${GATE_USER}"
    chmod 0440 "/etc/sudoers.d/${GATE_USER}"
    install -d -o "${uid}" -g "${gid}" "${E2E_GATE_REPO}" "${E2E_GATE_REPO}/e2e" "${E2E_GATE_REPO}/e2e/runs"
}

case "${1:-}" in
    tools)         step_tools ;;
    collections)   step_collections ;;
    ansible-range) step_ansible_range ;;
    user)          step_user "${2:?provision.sh user needs a uid}" "${3:?provision.sh user needs a gid}" ;;
    *)             sed -n '6,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac
