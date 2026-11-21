#!/usr/bin/env bash
#
# Tier 1: no Jinja string literal handed to a regex filter or test doubles its backslashes.
#
# In every ansible-core setup/setup.sh accepts, 2.19.0 up to 2.23.0, a Jinja string literal keeps
# each backslash as written: measured on 2026-11-21 in the gate image and in throwaway virtual
# environments of 2.19.0 and 2.22.0, `'\1' | length` is 2 and `'\\1' | length` is 3. So `'\\1'` reaches
# regex_search as two backslashes and a 1, which is no group reference and stops the play, and
# reaches regex_replace as a literal backslash and a 1, and `'\\\\EFI\\\\'` asks for two backslashes
# where the text has one. That shape was written four times, docs/regression_ledger.md 10.370 to
# 10.373, defect class 23. What reaches Jinja is the scalar after YAML has read it, so this reads
# every YAML file and template under setup/ansible/ the way YAML does, takes every Jinja expression,
# the text inside {{ }} and {% %} and the whole of a when, changed_when, failed_when, until or that
# condition, and in each expression that names regex_search, regex_replace, regex_findall or the
# search, match or regex test, fails a string literal holding an even run of two or more backslashes
# before a digit or `g<`, which is never a group reference, or a run of four or more backslashes.
#
# Before it reads the repository it runs its reader against a planted file and requires it to name
# exactly the four planted literals. It fails when it reads no file or fewer than twenty literals in
# regex expressions, because a reader that stopped finding them would otherwise pass over nothing.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

require_python "no Jinja string literal handed to a regex filter or test doubles its backslashes" "Jinja regex backslashes"

info "Tier 1: no Jinja string literal handed to a regex filter or test doubles its backslashes"

report_status=0
report="$("${PYTHON}" - "${REPO_ROOT}" <<'PYEOF'
import pathlib
import re
import sys

import yaml

REPO = pathlib.Path(sys.argv[1])
ROOT = REPO / 'setup' / 'ansible'
CONDITIONS = {'when', 'changed_when', 'failed_when', 'until', 'that'}
EXPRESSION = re.compile(r'\{\{(.*?)\}\}|\{%(.*?)%\}', re.S)
REGEX_USE = re.compile(r'regex_(?:search|replace|findall)|[\'"](?:search|match|regex)[\'"]'
                       r'|\bis\s+(?:not\s+)?(?:search|match|regex)\b')
LITERAL = re.compile(r"'((?:[^'\\]|\\.)*)'|\"((?:[^\"\\]|\\.)*)\"", re.S)
RUN = re.compile(r'\\+')


def doubled(text):
    for run in RUN.finditer(text):
        size = len(run.group())
        after = text[run.end():run.end() + 2]
        if size >= 4 or (size % 2 == 0 and (after[:1].isdigit() or after == 'g<')):
            return True
    return False


def expressions(value, condition):
    found = [a or b for a, b in EXPRESSION.findall(value)]
    if condition and not found:
        found = [value]
    return found


def scalars(node, key=None):
    if isinstance(node, yaml.ScalarNode):
        yield node, key
    elif isinstance(node, yaml.SequenceNode):
        for item in node.value:
            yield from scalars(item, key)
    elif isinstance(node, yaml.MappingNode):
        for key_node, value_node in node.value:
            yield from scalars(key_node, None)
            yield from scalars(value_node, key_node.value if isinstance(key_node, yaml.ScalarNode) else None)


def read(name, text, is_yaml):
    """(problems, literals examined) for one file."""
    problems, examined = [], 0
    if is_yaml:
        units = []
        for document in yaml.compose_all(text, Loader=yaml.SafeLoader):
            if document is not None:
                units += [(n.value, n.start_mark.line + 1, k in CONDITIONS) for n, k in scalars(document)
                          if n.tag == 'tag:yaml.org,2002:str']
    else:
        units = [(m.group(), text.count('\n', 0, m.start()) + 1, False) for m in EXPRESSION.finditer(text)]
    for value, line, condition in units:
        for expression in expressions(value, condition):
            if not REGEX_USE.search(expression):
                continue
            for a, b in LITERAL.findall(expression):
                literal = a or b
                examined += 1
                if doubled(literal):
                    problems.append("%s:%d hands '%s' to a regex, and a Jinja literal keeps every backslash it "
                                    "is given" % (name, line, literal))
    return problems, examined


PLANTED = r"""
- name: a group reference written for an older ansible-core
  ansible.builtin.set_fact:
    one: >-
      {{ x | regex_search('^Boot([0-9A-F]{4})', '\\1') }}
    two: >-
      {{ y | select('search', '\\\\EFI\\\\' ~ z) | list }}
    three: "{{ w | map('regex_replace', '^(.+)$', '->\\\\1') | list }}"
    sound_one: >-
      {{ x | regex_search('^Boot([0-9A-F]{4})', '\1') | default('\\EFI\\') }}
    sound_two: "{{ w | regex_replace('a(.)', '\\1') }}"
    sound_three: >-
      {{ 'a\\1' | length }}
  when: v is search('x\\2')
- name: a shell task is not Jinja
  ansible.builtin.shell: sed 's/\(a\)/\\1/' file
"""
planted, _ = read('planted.yaml', PLANTED, True)
wanted = ["'\\\\1'", "'\\\\\\\\EFI\\\\\\\\'", "'->\\\\1'", "'x\\\\2'"]
named = [next((p for p in planted if w in p), None) for w in wanted]
if len(planted) != 4 or None in named:
    print('FAIL the reader, run against a planted file, named %d literals where it must name exactly the four '
          'planted ones: %s' % (len(planted), '; '.join(planted) or 'none'))
    sys.exit(0)

problems, examined, files = [], 0, 0
for path in sorted(ROOT.rglob('*')):
    if not path.is_file() or path.suffix not in ('.yaml', '.yml', '.j2'):
        continue
    files += 1
    try:
        found, count = read(path.relative_to(REPO).as_posix(), path.read_text(encoding='utf-8'),
                            path.suffix != '.j2')
    except yaml.YAMLError as error:
        problems.append('%s does not parse as YAML: %s' % (path.relative_to(REPO).as_posix(), error))
        continue
    problems += found
    examined += count
if files == 0 or examined < 20:
    print('FAIL the reader read %d files and %d string literals in regex expressions under %s, fewer than it was '
          'written against, so nothing is proven' % (files, examined, ROOT.relative_to(REPO).as_posix()))
    sys.exit(0)
for problem in problems:
    print('FAIL %s' % problem)
if not problems:
    print('OK none of the %d string literals in regex expressions of the %d YAML files and templates under %s doubles '
          'its backslashes, and the reader named the four planted ones' % (examined, files, ROOT.relative_to(REPO).as_posix()))
PYEOF
)" || report_status=$?
assert_python_ran "${report_status}" "Jinja regex backslashes"

while IFS= read -r line; do
    case "${line}" in
        OK*)   pass "${line#OK }" ;;
        FAIL*) fail "no Jinja string literal handed to a regex filter or test doubles its backslashes" "${line#FAIL }" ;;
        *)     [[ -n "${line}" ]] && fail "the Jinja regex backslash check printed something unexpected" "${line}" ;;
    esac
done <<<"${report}"

finish "Jinja regex backslashes"
