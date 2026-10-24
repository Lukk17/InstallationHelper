"""Hold the agent instruction files to a size an agent reads whole.

Read by e2e/tier1/agents_md_size.sh. Adapted from tools/check-agents-md.py in agent-standards,
https://github.com/Lukk17/agent-standards, and not called from there, because this repository runs
nothing out of another one. Four rules, over the files git would commit, which is every tracked file
plus every untracked file that .gitignore does not exclude, so a new AGENTS.md counts before its first
commit and an ignored scratch file never does:

1. No file named CLAUDE.md or CLAUDE.local.md exists anywhere, .claude/CLAUDE.md included. Any of
   them switches off Claude Code's native AGENTS.md loading, so the nested files would never load.
2. The root AGENTS.md has fewer than ROOT_MAX_LINES lines.
3. The root AGENTS.md is under ROOT_MAX_BYTES bytes, the most Codex reads by default before it stops
   adding files without saying so.
4. Every other AGENTS.md has fewer than NESTED_MAX_LINES lines.

Prints one line per finding, then one summary line. Exit codes: 0 every rule holds, 1 a rule is
broken, 2 git could not list the files or a listed file could not be read.

Usage: check_agents_md.py <repository root>
"""

import pathlib
import subprocess
import sys

ROOT_MAX_LINES = 200
ROOT_MAX_BYTES = 32768
NESTED_MAX_LINES = 60

AGENTS_FILE_NAME = "AGENTS.md"
FORBIDDEN_FILE_NAMES = ("claude.md", "claude.local.md")


class Unreadable(Exception):
    """git or the file system could not answer, so nothing below would mean anything."""


def listed_files(root):
    """Every file git would commit under root, in POSIX form."""
    try:
        result = subprocess.run(
            ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
            cwd=root, capture_output=True, text=True, encoding="utf-8", check=False,
        )
    except OSError as error:
        raise Unreadable("could not run git in %s: %s" % (root, error)) from error
    if result.returncode != 0:
        raise Unreadable("git ls-files failed in %s: %s" % (root, result.stderr.strip()))
    return sorted({entry for entry in result.stdout.split("\0") if entry and (root / entry).is_file()})


def read_bytes(path):
    try:
        return path.read_bytes()
    except OSError as error:
        raise Unreadable("could not read %s: %s" % (path, error)) from error


def line_count(content):
    """Lines as an editor numbers them, so a last line with no newline still counts."""
    return len(content.splitlines())


def forbidden_findings(paths):
    return [
        "%s exists. Any CLAUDE.md or CLAUDE.local.md in the project switches off Claude Code's native "
        "AGENTS.md loading. Delete it and keep the instructions in AGENTS.md." % path
        for path in paths
        if pathlib.PurePosixPath(path).name.casefold() in FORBIDDEN_FILE_NAMES
    ]


def root_findings(root):
    content = read_bytes(root / AGENTS_FILE_NAME)
    findings = []
    lines = line_count(content)
    if lines >= ROOT_MAX_LINES:
        findings.append("%s has %d lines, the limit is fewer than %d." % (AGENTS_FILE_NAME, lines, ROOT_MAX_LINES))
    if len(content) >= ROOT_MAX_BYTES:
        findings.append(
            "%s is %d bytes, the limit is under %d bytes, the most Codex reads by default."
            % (AGENTS_FILE_NAME, len(content), ROOT_MAX_BYTES)
        )
    return findings


def nested_findings(root, paths):
    findings = []
    for path in paths:
        lines = line_count(read_bytes(root / path))
        if lines >= NESTED_MAX_LINES:
            findings.append("%s has %d lines, the limit is fewer than %d." % (path, lines, NESTED_MAX_LINES))
    return findings


def main(argv):
    if len(argv) != 2:
        print("usage: check_agents_md.py <repository root>", file=sys.stderr)
        return 2
    root = pathlib.Path(argv[1]).resolve()

    try:
        paths = listed_files(root)
        agents_files = [path for path in paths if pathlib.PurePosixPath(path).name == AGENTS_FILE_NAME]
        nested = [path for path in agents_files if path != AGENTS_FILE_NAME]
        findings = forbidden_findings(paths)
        if AGENTS_FILE_NAME in paths:
            findings += root_findings(root)
        findings += nested_findings(root, nested)
    except Unreadable as error:
        print(error, file=sys.stderr)
        return 2

    for finding in findings:
        print(finding)
    if findings:
        return 1
    print("No CLAUDE.md or CLAUDE.local.md, and all %d AGENTS.md files are within their limits." % len(agents_files))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
