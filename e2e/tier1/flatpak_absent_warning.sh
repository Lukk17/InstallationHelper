#!/usr/bin/env bash
#
# Tier 1: the Flatpak warning that an install "reported success" names only applications whose install
# did report success.
#
# Until 2026-10-20 roles/software_installer/tasks/dynamic_install.yaml built flatpak_absent_after_install
# from every requested application flatpak does not list, without leaving out the ones the shared install
# file had already named as failed. So in sweep run 39260381281 the [WARN] "Flatpak reported success and
# does not list these applications" named applications whose install had visibly failed four times a few
# lines earlier, which sends the reader to check a mapping that is not wrong.
#
# The three shipped tasks are lifted out of dynamic_install.yaml by name, unchanged, and run against a
# fixture: three requested applications, one installed, one the install reported failed, one the install
# reported done and flatpak does not list. The warning must name the third alone, and every kind of
# Flatpak failure, which decides any_role_failed, must still hold the second and the third.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_cmd ansible-playbook
require_python "the Flatpak success warning names only silent losses" "flatpak absent warning"

DISPATCH="${ANSIBLE_DIR}/roles/software_installer/tasks/dynamic_install.yaml"

info "Tier 1: the Flatpak success warning names only silent losses"

work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT

lift_status=0
lifted="$("${PYTHON}" - "${DISPATCH}" "${work}/lifted.yaml" <<'PYEOF'
import pathlib
import sys

import yaml

WANTED = ['Collect Flatpak applications that are absent after the install',
          'Combine every kind of Flatpak failure',
          'Surface Flatpak applications that reported success and are absent']


def tasks(node):
    if isinstance(node, dict):
        if any(k in node for k in ('block', 'rescue', 'always')):
            for k in ('block', 'rescue', 'always'):
                yield from tasks(node.get(k))
            return
        yield node
    elif isinstance(node, list):
        for item in node:
            yield from tasks(item)


found = {t['name']: t for t in tasks(yaml.safe_load(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8')))
         if isinstance(t, dict) and t.get('name') in WANTED}
missing = [name for name in WANTED if name not in found]
if missing:
    print('MISSING %s' % '; '.join(missing))
    raise SystemExit(0)
pathlib.Path(sys.argv[2]).write_text(yaml.safe_dump([found[name] for name in WANTED], sort_keys=False),
                                     encoding='utf-8')
print('LIFTED')
PYEOF
)" || lift_status=$?
assert_python_ran "${lift_status}" "flatpak absent warning"

if [[ "${lifted}" != LIFTED ]]; then
    fail "the Flatpak tasks this check drives are not in dynamic_install.yaml" "${lifted#MISSING }"
    finish "flatpak absent warning"
fi

cat > "${work}/play.yaml" <<'PLAY'
- hosts: localhost
  connection: local
  gather_facts: true
  gather_subset: [min]
  vars:
    software_installer_batches:
      flatpak: [org.example.Installed, org.example.FailedLoudly, org.example.Silent]
    flatpak_reported_failures: [org.example.FailedLoudly]
    flatpak_installed_query:
      stdout_lines: [org.example.Installed, org.example.Unrelated]
  tasks:
    - name: The software installer's own Flatpak tasks
      ansible.builtin.include_tasks: "{{ work }}/lifted.yaml"
    - name: Report what they decided
      ansible.builtin.debug:
        msg: "IH_FLATPAK absent={{ flatpak_absent_after_install | sort | join(',') }} failed={{ failed_flatpak_applications | sort | join(',') }}"
PLAY

output="$(ANSIBLE_STDOUT_CALLBACK=default ANSIBLE_FORCE_COLOR=0 \
    ansible-playbook -i localhost, "${work}/play.yaml" -e "work=${work}" </dev/null 2>&1 || true)"

problems=()
if ! grep -q 'IH_FLATPAK absent=' <<<"${output}"; then
    problems+=("the play did not finish: $(grep -m3 -E 'ERROR|fatal' <<<"${output}" | tr '\n' ' ')")
else
    grep -q 'IH_FLATPAK absent=org.example.Silent failed=org.example.FailedLoudly,org.example.Silent"' <<<"${output}" \
        || problems+=("it decided [$(grep -o 'IH_FLATPAK [^"]*' <<<"${output}" | sed -n 1p)], expected absent=org.example.Silent alone and failed=org.example.FailedLoudly,org.example.Silent")
    warn="$(grep '"msg": "\[WARN\] Flatpak reported success' <<<"${output}" || true)"
    [[ -n "${warn}" ]] || problems+=("no [WARN] names org.example.Silent, whose install reported success and which flatpak does not list")
    grep -q 'org.example.FailedLoudly' <<<"${warn}" \
        && problems+=("the [WARN] says Flatpak reported success for org.example.FailedLoudly, whose install reported a failure: ${warn}")
fi

if [[ ${#problems[@]} -eq 0 ]]; then
    pass "the [WARN] names only the application whose install reported success and is absent, and both losses still count as failed"
else
    fail "the Flatpak success warning names applications it should not" "$(printf '%s; ' "${problems[@]}")"
fi

finish "flatpak absent warning"
