#!/usr/bin/env python3
"""The one reader of pinned_values.toml, and the only place allowed to resolve a {{ ref }}.

Three operations, no options:

    pins()        every pinned value, fully resolved, as a mapping of name to string
    pin(name)     one value, raising when nothing pinned that name
    checksums()   the checksum table, empty when it is absent or empty

Also the command line adapter the shell and PowerShell shims call, so no other runtime needs to
parse TOML or resolve a reference:

    pinned_values.py --json          the whole set as JSON
    pinned_values.py --get <name>    one value, exit 3 when the name is not pinned
    pinned_values.py --sh            PIN_<NAME>='<value>' lines for eval

The file is found beside this module, so no caller carries a copy of its path. Point
INSTALLATION_HELPER_PINS_FILE at another file to override that, which is what the tests do.
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError as exc:  # pragma: no cover - only reachable on Python 3.10 and older
    raise SystemExit(
        "pinned_values needs Python 3.11 or newer, which is where tomllib entered the standard "
        f"library. This interpreter is {sys.version.split()[0]}."
    ) from exc

DEFAULT_FILE = Path(__file__).resolve().parent / "pinned_values.toml"
ENV_OVERRIDE = "INSTALLATION_HELPER_PINS_FILE"

PINS_TABLE = "pins"
CHECKSUMS_TABLE = "checksums"

REFERENCE = re.compile(r"\{\{\s*([A-Za-z0-9_]+)\s*\}\}")

# A name every adapter can carry. It becomes PIN_<NAME> in shell, a key in a PowerShell hashtable and
# a variable name in Ansible, and none of those three survives a hyphen, a space or a dot.
NAME = re.compile(r"^[A-Za-z0-9_]+$")

EXIT_ABSENT = 3
EXIT_USAGE = 2


class PinnedValuesError(Exception):
    """Any refusal to hand out a value: the file, a value's type, a reference, or a cycle."""


# Keyed on the file's modification time in nanoseconds and its size, not on seconds: a file
# rewritten inside one clock tick would otherwise be served from a stale cache.
_cache: dict[Path, tuple[tuple[int, int], dict[str, str], dict[str, str]]] = {}


def pins_file() -> Path:
    """The file this process reads, which is the override when one is set."""
    override = os.environ.get(ENV_OVERRIDE)
    return Path(override) if override else DEFAULT_FILE


def pins() -> dict[str, str]:
    """Every pinned value, resolved. No value contains a reference and no value is a template."""
    return dict(_load()[0])


def pin(name: str) -> str:
    """One pinned value. Absence raises, naming the name and the file it was looked for in.

    There is deliberately no default parameter. A caller that wants to tolerate an absent pin can
    ask for the whole set and check, which makes the tolerance visible at the callsite instead of
    hidden in an argument, and nothing here needed it.
    """
    resolved = _load()[0]
    if name in resolved:
        return resolved[name]
    raise PinnedValuesError(f"nothing pinned '{name}' in {pins_file()}")


def checksums() -> dict[str, str]:
    """The checksum table. Empty means no download verification is enforced, which is legal."""
    return dict(_load()[1])


def _load() -> tuple[dict[str, str], dict[str, str]]:
    path = pins_file()
    try:
        status = path.stat()
    except OSError as exc:
        raise PinnedValuesError(f"cannot read the pinned values file {path}: {exc}") from exc
    stamp = (status.st_mtime_ns, status.st_size)

    cached = _cache.get(path)
    if cached is not None and cached[0] == stamp:
        return cached[1], cached[2]

    try:
        document = tomllib.loads(path.read_text(encoding="utf-8"))
    except tomllib.TOMLDecodeError as exc:
        raise PinnedValuesError(f"{path} is not valid TOML: {exc}") from exc
    except UnicodeDecodeError as exc:
        raise PinnedValuesError(f"{path} is not UTF-8 text: {exc}") from exc
    except OSError as exc:
        raise PinnedValuesError(f"cannot read the pinned values file {path}: {exc}") from exc

    raw = _string_table(document, PINS_TABLE, path, required=True)
    checksum_table = _string_table(document, CHECKSUMS_TABLE, path, required=False)
    resolved = _resolve_all(raw, path)

    _cache[path] = (stamp, resolved, checksum_table)
    return resolved, checksum_table


def _string_table(document: dict[str, object], table: str, path: Path, *, required: bool) -> dict[str, str]:
    """One table's worth of string values, refusing anything the adapters could not carry.

    Four refusals, each closing a way a caller could be handed the wrong answer instead of an error.
    A value that is not a string is an unquoted version. A name outside [A-Za-z0-9_] cannot be a
    shell variable, so `--sh` would render a line that eval treats as a command and the pin would
    then read as absent. Two names differing only in case collapse into one PIN_<NAME> and into one
    PowerShell hashtable key, so one of the pair would answer with the other's value. A value
    containing a newline cannot round-trip through `--get`, and the PowerShell adapter rejoins output
    lines with the platform separator, so the same pin would read differently per runtime.
    """
    section = document.get(table)
    if section is None:
        if required:
            raise PinnedValuesError(f"{path} has no [{table}] table")
        return {}
    if not isinstance(section, dict):
        raise PinnedValuesError(f"{path}: [{table}] is not a table")
    if required and not section:
        raise PinnedValuesError(
            f"{path}: [{table}] is empty. An empty set would make every caller report every value "
            "as absent, which reads as a machine with nothing pinned rather than as a broken file."
        )

    values: dict[str, str] = {}
    folded: dict[str, str] = {}
    for name, value in section.items():
        if not NAME.match(name):
            raise PinnedValuesError(
                f"{path}: [{table}] '{name}' is not a name every adapter can carry. Use letters, "
                "digits and underscores, because the name becomes PIN_<NAME> in shell and a variable "
                "name in Ansible."
            )
        if name.lower() in folded:
            raise PinnedValuesError(
                f"{path}: [{table}] {name} and {folded[name.lower()]} differ only in case, and "
                "neither PIN_<NAME> in shell nor a PowerShell hashtable can tell them apart."
            )
        folded[name.lower()] = name
        if not isinstance(value, str):
            raise PinnedValuesError(
                f"{path}: [{table}] {name} is {type(value).__name__}, not a string. "
                "Quote it, because a version is text that happens to contain digits."
            )
        if "\n" in value or "\r" in value:
            raise PinnedValuesError(
                f"{path}: [{table}] {name} contains a line break, which no adapter can carry back "
                "to its caller unchanged."
            )
        values[name] = value
    return values


def _resolve_all(raw: dict[str, str], path: Path) -> dict[str, str]:
    resolved: dict[str, str] = {}
    for name in raw:
        _resolve(name, raw, resolved, [], path)
    return resolved


def _resolve(name: str, raw: dict[str, str], resolved: dict[str, str], chain: list[str], path: Path) -> str:
    if name in resolved:
        return resolved[name]
    if name in chain:
        cycle = " -> ".join([*chain[chain.index(name) :], name])
        raise PinnedValuesError(f"{path}: pinned values reference each other in a cycle: {cycle}")

    value = raw[name]
    chain.append(name)

    def substitute(match: re.Match[str]) -> str:
        referenced = match.group(1)
        if referenced not in raw:
            raise PinnedValuesError(
                f"{path}: {name} references {{{{ {referenced} }}}}, and nothing pins {referenced}"
            )
        return _resolve(referenced, raw, resolved, chain, path)

    value = REFERENCE.sub(substitute, value)
    chain.pop()

    if "{" in value or "}" in value:
        raise PinnedValuesError(
            f"{path}: {name} resolves to a value containing a brace, which nothing pinned here ever "
            f"needs and which a second templating pass could act on: {value}"
        )

    resolved[name] = value
    return value


def _usage() -> str:
    return (
        f"usage: {Path(sys.argv[0]).name} --json | --get <name> | --sh | --checksum <name>\n"
        "  --json            every pinned value as a JSON object\n"
        "  --get <name>      one value, exit 3 when nothing pins that name\n"
        "  --sh              PIN_<NAME>='<value>' lines for eval\n"
        "  --checksum <name> one checksum, exit 3 when nothing pins that name\n"
    )


def main(argv: list[str]) -> int:
    if not argv:
        sys.stderr.write(_usage())
        return EXIT_USAGE

    mode, rest = argv[0], argv[1:]
    try:
        if mode == "--json" and not rest:
            sys.stdout.write(json.dumps(pins(), indent=2, sort_keys=True) + "\n")
            return 0
        if mode == "--get" and len(rest) == 1:
            # Loaded first, deliberately. Reading the whole set here means a missing file, invalid
            # TOML, a cycle or a bad value leaves through the load failure below at exit 1, and exit
            # 3 keeps its one meaning: this name is not pinned. A caller that branches on 3 would
            # otherwise read a corrupt file as an absent key and carry on with a default.
            values = pins()
            if rest[0] not in values:
                sys.stderr.write(f"nothing pinned '{rest[0]}' in {pins_file()}\n")
                return EXIT_ABSENT
            sys.stdout.write(values[rest[0]] + "\n")
            return 0
        if mode == "--sh" and not rest:
            for name, value in sorted(pins().items()):
                escaped = value.replace("'", "'\\''")
                sys.stdout.write(f"PIN_{name.upper()}='{escaped}'\n")
            return 0
    except PinnedValuesError as exc:
        sys.stderr.write(f"{exc}\n")
        return 1

    sys.stderr.write(_usage())
    return EXIT_USAGE


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
