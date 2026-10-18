"""List every vendor rpm and every vendor repository package the default Fedora set installs.

Read by e2e/tier2/rpm_file_conflicts.sh. Everything comes from the shipped files, never from a copy:
the toggles from setup/ansible/group_vars/all.yaml and linux.yaml, the mappings and the companion
packages from setup/ansible/vars/RedHat.yaml, the repositories from the yum_repository tasks and the
get_url tasks writing under /etc/yum.repos.d in the role task files, and the vendor rpm downloads from
the dnf_url mappings and from every get_url task whose dest is an .rpm file. A task is left out only
when its conditions provably do not hold for a Fedora machine with the default toggles, the way
render_apt_repositories.py decides. The pins arrive as the JSON setup/pinned_values/pinned_values.py
--json prints, so this reads no pins file of its own.

Prints one tab-separated line per item:
    repo      <id>   <baseurl>                   a repository yum_repository writes
    repofile  <dest> <location>                  a .repo file get_url fetches
    repoid    <id>                               a vendor repository id, from third_party_repositories
    package   <name>                             a package the default set asks dnf for
    rpm       <label> <location> <excluded>      a vendor rpm, <excluded> the path its route leaves out or -
Exits 3 when a template cannot be rendered or a dnf_url mapping has no location, naming it, because an
item that was not rendered is an item nobody checked.
"""

import json
import pathlib
import sys

import jinja2
import jinja2.meta
import yaml

YUM_REPOSITORY = {"yum_repository", "ansible.builtin.yum_repository"}
GET_URL = {"get_url", "ansible.builtin.get_url"}
REPOS_DIR = "/etc/yum.repos.d/"
TASK_LISTS = ("block", "rescue", "always")


def module_args(task, names):
    for name in names:
        if name in task and isinstance(task[name], dict):
            return task[name]
    return None


def conditions_of(task):
    when = task.get("when")
    if when is None:
        return []
    return [str(condition) for condition in (when if isinstance(when, list) else [when])]


def tasks_of(tasks, inherited_when, source):
    """Yields (task, when, source) for every task in tasks, nested ones included."""
    if not isinstance(tasks, list):
        return
    for task in tasks:
        if not isinstance(task, dict):
            continue
        when = inherited_when + conditions_of(task)
        for nested in TASK_LISTS:
            yield from tasks_of(task.get(nested), when, source)
        yield task, when, f"{source}:{task.get('name', 'unnamed task')}"


def applies(conditions, context):
    """False only when a condition reads nothing but known names and is false for them."""
    strict = jinja2.Environment(undefined=jinja2.StrictUndefined)
    for condition in conditions:
        try:
            names = jinja2.meta.find_undeclared_variables(strict.parse("{{ " + condition + " }}"))
            if not names <= context.keys():
                continue
            if not strict.compile_expression(condition)(**context):
                return False
        except jinja2.TemplateError:
            continue
    return True


def render(environment, template, context, where):
    try:
        return " ".join(environment.from_string(str(template)).render(context).split())
    except jinja2.TemplateError as error:
        sys.stderr.write(f"render_dnf_sources: {where} could not be rendered: {error}\n")
        sys.exit(3)


def load(path):
    return yaml.safe_load(path.read_text(encoding="utf-8")) or {}


def main():
    repo_root = pathlib.Path(sys.argv[1])
    pins = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
    ansible_dir = repo_root / "setup" / "ansible"

    toggles = {**load(ansible_dir / "group_vars" / "all.yaml"), **load(ansible_dir / "group_vars" / "linux.yaml")}
    role_defaults = {}
    for path in sorted(ansible_dir.glob("roles/*/defaults/main.yaml")):
        role_defaults.update(load(path))
    context = {**pins, **role_defaults, **toggles, "ih_family": "RedHat", "ansible_architecture": "x86_64",
               "ansible_facts": {"architecture": "x86_64", "system": "Linux"}}
    environment = jinja2.Environment(undefined=jinja2.StrictUndefined)

    redhat = load(ansible_dir / "vars" / "RedHat.yaml")
    mapping = redhat.get("software_mapping") or {}
    enabled = {key for key in mapping if toggles.get(f"install_{key}") is True}

    for key, entry in sorted((redhat.get("third_party_repositories") or {}).items()):
        for repo_id in entry.get("repo_ids") or []:
            print(f"repoid\t{repo_id}")

    for key in sorted(enabled):
        entry = mapping[key]
        if entry.get("manager") in ("dnf", "dnf_repo"):
            print(f"package\t{entry['package']}")
    for key, names in sorted((redhat.get("companion_packages") or {}).items()):
        wanted = (key in enabled) if key in mapping else toggles.get(f"install_{key}", toggles.get(key)) is True
        if wanted:
            for name in names:
                print(f"package\t{name}")

    for key in sorted(enabled):
        entry = mapping[key]
        if entry.get("manager") != "dnf_url":
            continue
        location = entry.get("url") or pins.get(f"{key}_rpm_url") or pins.get(f"{key}_url") or ""
        location = render(environment, location, context, f"vars/RedHat.yaml:{key}").strip()
        if not location:
            sys.stderr.write(f"render_dnf_sources: the dnf_url mapping {key} has no download location\n")
            sys.exit(3)
        print(f"rpm\t{key}\t{location}\t{entry.get('exclude_path') or '-'}")

    task_files = sorted(ansible_dir.glob("roles/*/tasks/*.yaml")) + sorted(ansible_dir.glob("tasks/*.yaml"))
    for path in task_files:
        source = str(path.relative_to(repo_root))
        for task, when, where in tasks_of(load(path), [], source):
            if not applies(when, context):
                continue
            args = module_args(task, YUM_REPOSITORY)
            if args and args.get("baseurl"):
                print(f"repo\t{render(environment, args['name'], context, where)}\t"
                      f"{render(environment, args['baseurl'], context, where)}")
            args = module_args(task, GET_URL)
            if not args or not isinstance(args.get("url"), str):
                continue
            dest = str(args.get("dest", ""))
            if dest.startswith(REPOS_DIR):
                print(f"repofile\t{dest}\t{render(environment, args['url'], context, where)}")
            elif dest.endswith(".rpm"):
                label = pathlib.PurePosixPath(dest).stem
                print(f"rpm\t{label}\t{render(environment, args['url'], context, where)}\t-")


if __name__ == "__main__":
    main()
