"""Render every apt repository line the playbook writes, once per case of derived facts.

Read by e2e/lib/apt_repositories.sh. The repository lines come out of the shipped task files under
setup/ansible, never out of a copy, and the facts come from the shipped derivation through
e2e/tier1/apt_vendor_repositories.yaml, so the only thing this file adds is Jinja.

A repository line is the repo of an apt_repository task, a deb line in the content of a copy task
writing under /etc/apt/sources.list.d, or the URIs and Suites of a deb822_repository task. A key
location is the url of a get_url task in a block that also adds a repository.

Prints one tab-separated line per rendered string:
    fixture  kind  varies  source  rendered
kind is repo or key, varies is 1 when the template reads the release or the lineage, and source is
the task file relative to the repository root, a colon and the task name. Exits 3 when a template
cannot be rendered, naming it, because a line that was not rendered is a line nobody checked.
"""

import json
import pathlib
import re
import sys

import jinja2
import jinja2.meta
import yaml

APT_REPOSITORY = {"apt_repository", "ansible.builtin.apt_repository"}
DEB822_REPOSITORY = {"deb822_repository", "ansible.builtin.deb822_repository"}
COPY = {"copy", "ansible.builtin.copy"}
GET_URL = {"get_url", "ansible.builtin.get_url"}
SOURCES_DIR = "/etc/apt/sources.list.d"
VARYING = re.compile(r"ih_apt_codename|ih_base|distribution_release|lsb")
TASK_LISTS = ("block", "rescue", "always")


class VisibleUndefined(jinja2.Undefined):
    def __str__(self):
        return f"<undefined:{self._undefined_name}>"


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


def templates_of(tasks, inherited_vars, inherited_when, source):
    """Yields (kind, template, vars, when, source) for every repository line and key location in tasks."""
    if not isinstance(tasks, list):
        return
    adds_repository = any(
        isinstance(t, dict) and (module_args(t, APT_REPOSITORY) or module_args(t, DEB822_REPOSITORY))
        for t in tasks
    )
    for task in tasks:
        if not isinstance(task, dict):
            continue
        task_vars = {**inherited_vars, **(task.get("vars") or {})}
        task_when = inherited_when + conditions_of(task)
        where = f"{source}:{task.get('name', 'unnamed task')}"
        for nested in TASK_LISTS:
            yield from templates_of(task.get(nested), task_vars, task_when, source)

        args = module_args(task, APT_REPOSITORY)
        if args and isinstance(args.get("repo"), str):
            yield "repo", args["repo"], task_vars, task_when, where

        args = module_args(task, DEB822_REPOSITORY)
        if args:
            uris = args.get("uris")
            suites = args.get("suites")
            uris = " ".join(uris) if isinstance(uris, list) else uris
            suites = " ".join(suites) if isinstance(suites, list) else suites
            if uris and suites:
                yield "repo", f"deb {uris} {suites}", task_vars, task_when, where

        args = module_args(task, COPY)
        if args and str(args.get("dest", "")).startswith(SOURCES_DIR) and isinstance(args.get("content"), str):
            for line in args["content"].splitlines():
                if line.strip().startswith("deb "):
                    yield "repo", line.strip(), task_vars, task_when, where

        args = module_args(task, GET_URL)
        if adds_repository and args and isinstance(args.get("url"), str):
            yield "key", args["url"], task_vars, task_when, where


def render(environment, template, context, where):
    try:
        return " ".join(environment.from_string(template).render(context).split())
    except jinja2.TemplateError as error:
        sys.stderr.write(f"render_apt_repositories: {where} could not be rendered: {error}\n")
        sys.exit(3)


def applies(conditions, context):
    """False only when a condition reads nothing but the case's own facts and is false for them.

    A condition reading a toggle or anything else this file does not model counts as true, so a line
    is left out only when its task provably does not run on that machine, the way debian_core's
    contrib line runs only where Ansible reports the distribution as Debian.
    """
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


def context_of(case):
    release = case.get("reported_release", "")
    facts = {
        "architecture": "x86_64",
        "distribution": case.get("reported_distribution", ""),
        "distribution_release": release,
    }
    return {
        "ih_family": case.get("ih_family", ""),
        "ih_base": case.get("ih_base", ""),
        "ih_apt_codename": case.get("ih_apt_codename", ""),
        "ansible_facts": facts,
        "ansible_architecture": facts["architecture"],
        "ansible_distribution_release": release,
    }


def main():
    repo_root = pathlib.Path(sys.argv[1])
    cases = [json.loads(line) for line in pathlib.Path(sys.argv[2]).read_text().splitlines() if line.strip()]
    ansible_dir = repo_root / "setup" / "ansible"
    task_files = sorted(ansible_dir.glob("roles/*/tasks/*.yaml")) + sorted(ansible_dir.glob("tasks/*.yaml"))

    templates = []
    for path in task_files:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
        templates.extend(templates_of(data, {}, [], str(path.relative_to(repo_root))))

    environment = jinja2.Environment(undefined=VisibleUndefined)
    for case in cases:
        context = context_of(case)
        for kind, template, task_vars, conditions, where in templates:
            if not applies(conditions, context):
                continue
            local = {**context, **task_vars}
            for _ in range(len(task_vars)):
                for name, value in task_vars.items():
                    if isinstance(value, str):
                        local[name] = render(environment, value, local, where)
            varies = "1" if VARYING.search(template) else "0"
            print("\t".join([case["fixture"], kind, varies, where, render(environment, template, local, where)]))


if __name__ == "__main__":
    main()
