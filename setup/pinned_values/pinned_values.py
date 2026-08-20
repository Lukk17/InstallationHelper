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

EXIT_ABSENT = 3
EXIT_USAGE = 2

_MISSING = object()


class PinnedValuesError(Exception):
    """Any refusal to hand out a value: the file, a value's type, a reference, or a cycle."""


_cache: dict[Path, tuple[float, dict[str, str], dict[str, str]]] = {}


def pins_file() -> Path:
    """The file this process reads, which is the override when one is set."""
    override = os.environ.get(ENV_OVERRIDE)
    return Path(override) if override else DEFAULT_FILE


def pins() -> dict[str, str]:
    """Every pinned value, resolved. No value contains a reference and no value is a template."""
    return dict(_load()[0])


def pin(name: str, default: object = _MISSING) -> str:
    """One pinned value. Absence raises unless a default is passed at the callsite."""
    resolved = _load()[0]
    try:
        return resolved[name]
    except KeyError:
        if default is not _MISSING:
            return default  # type: ignore[return-value]
        raise PinnedValuesError(f"nothing pinned '{name}' in {pins_file()}") from None


def checksums() -> dict[str, str]:
    """The checksum table. Empty means no download verification is enforced, which is legal."""
    return dict(_load()[1])


def _load() -> tuple[dict[str, str], dict[str, str]]:
    path = pins_file()
    try:
        stamp = path.stat().st_mtime
    except OSError as exc:
        raise PinnedValuesError(f"cannot read the pinned values file {path}: {exc}") from exc

    cached = _cache.get(path)
    if cached is not None and cached[0] == stamp:
        return cached[1], cached[2]

    try:
        document = tomllib.loads(path.read_text(encoding="utf-8"))
    except tomllib.TOMLDecodeError as exc:
        raise PinnedValuesError(f"{path} is not valid TOML: {exc}") from exc
    except OSError as exc:
        raise PinnedValuesError(f"cannot read the pinned values file {path}: {exc}") from exc

    raw = _string_table(document, PINS_TABLE, path, required=True)
    checksum_table = _string_table(document, CHECKSUMS_TABLE, path, required=False)
    resolved = _resolve_all(raw, path)

    _cache[path] = (stamp, resolved, checksum_table)
    return resolved, checksum_table


def _string_table(document: dict[str, object], table: str, path: Path, *, required: bool) -> dict[str, str]:
    """One table's worth of string values, refusing any value that is not a string."""
    section = document.get(table)
    if section is None:
        if required:
            raise PinnedValuesError(f"{path} has no [{table}] table")
        return {}
    if not isinstance(section, dict):
        raise PinnedValuesError(f"{path}: [{table}] is not a table")

    values: dict[str, str] = {}
    for name, value in section.items():
        if not isinstance(value, str):
            raise PinnedValuesError(
                f"{path}: [{table}] {name} is {type(value).__name__}, not a string. "
                "Quote it, because a version is text that happens to contain digits."
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

    if "{{" in value or "}}" in value:
        raise PinnedValuesError(f"{path}: {name} still holds a template after resolution: {value}")

    resolved[name] = value
    return value


def _usage() -> str:
    return (
        f"usage: {Path(sys.argv[0]).name} --json | --get <name> | --sh\n"
        "  --json        every pinned value as a JSON object\n"
        "  --get <name>  one value, exit 3 when nothing pins that name\n"
        "  --sh          PIN_<NAME>='<value>' lines for eval\n"
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
            try:
                sys.stdout.write(pin(rest[0]) + "\n")
            except PinnedValuesError as exc:
                sys.stderr.write(f"{exc}\n")
                return EXIT_ABSENT
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
