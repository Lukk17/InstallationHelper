#!/usr/bin/env bash
#
# Tier 2: every pinned download location must still exist.
#
# This is the gap that let Antigravity sit pinned at 1.13.3 while the package had moved to 2.8.1, with
# no tier noticing. Names are resolved against package indexes by the check beside this one, and the
# vendor URLs were resolved by nothing at all: a version pinned in group_vars/versions.yaml can rot
# quietly, and the first sign is an install failing on a real machine months later. Three of those are
# already in docs/regression_ledger.md, including a 404 that read as a network problem.
#
# Nothing is downloaded. Each location gets a HEAD request, and the ones that refuse HEAD get a ranged
# GET of the first byte, which is what a redirecting content host tends to answer. So this costs a few
# seconds and a few kilobytes for the whole set, rather than the several gigabytes the artifacts weigh.
#
# The URLs are resolved through Ansible rather than by pasting a regular expression here, because a
# third of them are built from other pins with Jinja and only Ansible can render that. Reimplementing
# the templating in bash is exactly the second-parser mistake this repository keeps paying for.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_cmd curl

ALLOWED_FILE="$(dirname "${BASH_SOURCE[0]}")/pinned_urls_allowed.txt"

info "Tier 2: pinned download locations"

# Ask Ansible to render every pin whose value looks like a location, one per line as <key> <url>. The
# rendering is what makes templated pins resolvable, and it needs the same interpreter the playbook
# uses, so on a shell without ansible-playbook this delegates to WSL the way the tier 1 checks do.
render_urls() {
    local play out gv
    play="$(mktemp)"
    out="$(mktemp)"
    gv="${ANSIBLE_DIR}/group_vars"

    # Three things here are load-bearing and each was established by watching it fail.
    #
    # Absolute paths, because a playbook in a temporary directory resolves a relative vars_files entry
    # against its own directory rather than the working directory, and the load simply fails.
    #
    # The same file loaded twice: as vars_files, which puts the pins in the top level scope where a pin
    # that references another pin can resolve at all, and under a name, which gives the key list to
    # iterate. Reading each value through lookup('vars', key) then renders it in the scope where its
    # references exist.
    #
    # all.yaml and the Linux toggles loaded too, with facts gathered, because at least one pin resolves
    # through a variable that comes from a run-time fact rather than from this file. Rendering the set
    # without them fails on that one pin and takes the whole render with it.
    #
    # The result goes to a file rather than being scraped from the console, because this repository
    # installs its own stdout callback and the shape of a printed line is that plugin's business.
    cat > "${play}" <<'PLAY'
- hosts: localhost
  connection: local
  gather_facts: true
  vars_files:
    - "{{ versions_file }}"
    - "{{ all_file }}"
    - "{{ os_file }}"
  tasks:
    - name: Read the pin names
      ansible.builtin.include_vars:
        file: "{{ versions_file }}"
        name: pin_names

    - name: Write every pinned value that resolves to a location
      ansible.builtin.copy:
        dest: "{{ out_file }}"
        mode: '0600'
        content: |
          {% for key in pin_names.keys() | sort %}
          {% set rendered = lookup('vars', key, default='') %}
          {% if rendered is string and '://' in rendered %}
          {{ key }} {{ rendered }}
          {% endif %}
          {% endfor %}
PLAY

    ( cd "${ANSIBLE_DIR}" && ansible-playbook -i localhost, -c local \
        -e "versions_file=${gv}/versions.yaml" \
        -e "all_file=${gv}/all.yaml" \
        -e "os_file=${gv}/linux.yaml" \
        -e "out_file=${out}" "${play}" >/dev/null 2>&1 )
    grep -E '^[a-z0-9_]+ https?://' "${out}" || true
    rm -f "${play}" "${out}"
}

if ! command -v ansible-playbook &>/dev/null; then
    source "$(dirname "${BASH_SOURCE[0]}")/../tier1/wsl_delegate.sh"
    delegate_to_wsl_or_fail "e2e/tier2/resolve_pinned_urls.sh"
fi

mapfile -t entries < <(render_urls)

# A renderer that returns nothing would pass every assertion below without checking a single URL,
# which is the vacuous pass this repository has been caught by twice. There are dozens of these pins.
if [[ ${#entries[@]} -lt 10 ]]; then
    fail "only ${#entries[@]} pinned locations were rendered, so this check cannot mean anything" \
         "expected dozens from ${ANSIBLE_DIR}/group_vars/versions.yaml, the render step has probably stopped working"
    finish "pinned download locations"
fi

# HEAD first. A vendor that refuses HEAD gets a one-byte ranged GET, which is enough to prove the
# object is served without pulling a 230 MB artifact. 401 and 403 count as reachable on purpose: they
# prove the location exists and the download needs a session, which is a different problem from rot.
url_alive() {
    local url="$1" code
    code="$(curl -s -o /dev/null -w '%{http_code}' -I -L --max-time 25 "$url" || true)"
    case "${code}" in
        200|401|403) return 0 ;;
    esac
    code="$(curl -s -o /dev/null -w '%{http_code}' -r 0-0 -L --max-time 25 "$url" || true)"
    case "${code}" in
        200|206|401|403) return 0 ;;
    esac
    printf '%s' "${code}"
    return 1
}

# A key naming a base or a repository is not a downloadable object. An apt or yum repository answers
# on the files beneath it, Release and the package pool, and returns 404 on the base itself, and a
# content-delivery base is the same. Probing those reports rot that is not there, which is how a check
# earns the right to be ignored. They are skipped by rule rather than by an allowlist entry each,
# because the rule is a property of what the value is, and the count is reported so the skipping is
# never silent.
dead=()
skipped=()
checked=0
for entry in "${entries[@]}"; do
    key="${entry%% *}"
    url="${entry#* }"
    grep -qE "^${key}([[:space:]]|$)" "${ALLOWED_FILE}" 2>/dev/null && continue
    if [[ "${key}" =~ (_base|_repo)$ ]]; then
        skipped+=("${key}")
        continue
    fi
    checked=$((checked + 1))
    if ! code="$(url_alive "${url}")"; then
        dead+=("${key} -> HTTP ${code:-no answer} ${url}")
    fi
done

if [[ ${#skipped[@]} -gt 0 ]]; then
    info "not probed, a base or repository path is not an object: ${skipped[*]}"
fi

if [[ ${#dead[@]} -eq 0 ]]; then
    pass "all ${checked} pinned download locations answer"
else
    fail "${#dead[@]} of ${checked} pinned download locations do not answer" "$(printf '%s; ' "${dead[@]}")"
fi

# An allowlist entry that has stopped matching a real pin forgives nothing and hides a rename.
stale=()
while read -r key _; do
    [[ -z "${key}" || "${key}" == \#* ]] && continue
    printf '%s\n' "${entries[@]}" | grep -qE "^${key} " || stale+=("${key}")
done < <(grep -vE '^\s*(#|$)' "${ALLOWED_FILE}" 2>/dev/null || true)

if [[ ${#stale[@]} -eq 0 ]]; then
    pass "pinned_urls_allowed.txt has no stale entries"
else
    fail "pinned_urls_allowed.txt names pins that no longer exist" "${stale[*]}"
fi

finish "pinned download locations"
