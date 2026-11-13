#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Installation Helper — dual-logger callback plugin

Writes four log files in the invoking user's home directory:
    installation_full.log      everything (verbose post-mortem)
    installation_errors.log    only FAILED / fatal / unreachable
    installation_warnings.log  only WARNING-level entries
    installation_skipped.log   only skipped items (per-item disposition)

Console output shows only what installs, changes or fails: a changed,
failed or unreachable result, a retried attempt, a debug message opening
with a level marker, the task header and phase banner above them, and the
end-of-run summary. ok and skipped results go to the log files alone. Long
stdout/stderr blocks (license dumps, multi-page installer chatter) are
truncated to STDOUT_TRUNCATE_LINES before being written anywhere, keeping
their head, their tail and the error lines between them.

The end-of-run summary is appended to installation_full.log so that
operators can `tail` one file and see grouped Installed / Already-present /
Skipped / Failed sections.
"""

import datetime
import os
import pwd
import re
import shutil
import sys
import threading
import time
from typing import Optional, List, Dict, Any
import yaml
from ansible.plugins.callback import CallbackBase


# Long-running tasks write to known log paths; the heartbeat tails the last
# line so the user sees what apt/flatpak/etc. is actually doing. Longest-prefix
# match wins (see _heartbeat_lookup_log) so order doesn't matter, but more
# specific prefixes still need to be unique enough to not collide.
HEARTBEAT_LOG_FILES = {
    "Full system upgrade and autoremove (Debian, via raw)": "/var/log/installation-apt-upgrade.log",
    # Every apt, dnf, pacman, flatpak and snap install in the playbook, the software set and every role
    # alike, one package per call through setup/ansible/tasks/install_role_packages.yaml: its first
    # attempt and its retries
    "Install a package set one package at a time": "/var/log/installation-packages.log",
    "Retry each package that failed": "/var/log/installation-packages.log",
}


def _invoking_user_home() -> str:
    """Resolve the home directory of the user who invoked ansible-playbook,
    even when running under sudo. SUDO_USER survives across `sudo -E`."""
    sudo_user = os.environ.get("SUDO_USER")
    if sudo_user and sudo_user != "root":
        try:
            return pwd.getpwnam(sudo_user).pw_dir
        except (KeyError, AttributeError):
            pass
    return os.path.expanduser("~")


DOCUMENTATION = """
    callback: dual_logger
    type: stdout
    short_description: Condensed console output + verbose log files
    description:
        - Writes installation_full.log, installation_errors.log,
          installation_warnings.log, installation_skipped.log to the invoking
          user's home directory (SUDO_USER aware).
        - Shows on the terminal only what installs, changes or fails.
        - Truncates very long stdout/stderr blocks per task, keeping their error lines.
        - Adds per-task duration ([+X.Xs]) and role-boundary phase separators.
        - Appends a grouped end-of-run summary to installation_full.log.
    options:
        allow_callback_failure:
            description: Continue running if log files cannot be opened
            ini:
                - section: defaults
                  key: allow_callback_failure
            env:
                - name: ALLOW_CALLBACK_FAILURE
            default: false
"""


# --- Configuration ---------------------------------------------------------

STDOUT_TRUNCATE_LINES = 30  # max lines of captured stdout/stderr per task
RETRY_STDERR_TAIL_LINES = 5  # stderr lines kept from each failed attempt of a retried task
# Lines a truncation keeps from the part it drops, because a failed build says why in them: a
# compiler's "error:", Gradle's "BUILD FAILED" and "FAILURE:", git's "fatal:", apt's "E: ".
ERROR_LINE_REGEX = re.compile(r"(?i:\berror:|\bfatal:)|\bERROR\b|BUILD FAILED|FAILURE:|^\s*E: ")
MAX_KEPT_ERROR_LINES = 10  # the earliest ones, where a cascade of errors starts
PHASE_BAR = "=" * 70
# What ansible-core 2.19 and later put in a failed result's `exception` when tracebacks are off.
TRACEBACK_PLACEHOLDER = "(traceback unavailable)"
# Return to the start of the line and erase it, which is how the live status line is replaced.
ERASE_LINE = "\r\x1b[K"

# Patterns that filter noise from BOTH console and log files.
IGNORE_PATTERNS = [
    "already installed",
    "subvolume already covered",
    # pyenv installer prints this hint every run; the shell-config role wires
    # pyenv up properly, so the hint is noise.
    "seems you still have not added 'pyenv' to the load path",
    # node ExperimentalWarning follow-up — the warning itself is informative
    # but the "Use --trace-warnings" hint that follows is just noise.
    "Use `llmster --trace-warnings",
    "Use `node --trace-warnings",
    "(Use `node --trace-warnings",
    # Ansible 2.20+ deprecation that fires on EVERY task using top-level fact
    # vars (ansible_os_family etc.). Informational, not user-actionable here,
    # and our playbook already uses the new ansible_facts['...'] form where it
    # matters. The deprecation will be flipped to default-off in a future
    # Ansible release; until then, drop the spam.
    "INJECT_FACTS_AS_VARS default to `True` is deprecated",
    # makepkg notice when reusing a previous build tree — fine, not actionable.
    "==> WARNING: Using existing $srcdir",
    # glibc warning emitted by Go's cgo build when statically linking yay/paru
    # and other Go-based AUR packages. Not a real defect — these tools work.
    "in statically linked applications requires at runtime the shared libraries",
    # autoconf warning during AUR builds (e.g. clamav, hardinfo2) — upstream
    # autotools deprecation, not actionable from our side.
    "configure.ac:",
    "AC_PROG_CC_C99' is obsolete",
    # pub during dart/flutter install: it warns because PATH inside the
    # playbook subshell doesn't include ~/.pub-cache/bin yet. env_variables
    # puts it on PATH in ~/.config/environment.d/990-dev.conf, which every
    # shell and the desktop session read, so later shells are fine.
    "Pub installs executables into $HOME/.pub-cache/bin, which is not on your path",
    # pacman -Sc cleans cached download tempfiles that may already be gone.
    # The error is harmless — the actual cache cleanup succeeded.
    "could not open file /var/cache/pacman/pkg/download-",
    # The two interactive prompts pacman -Sc shows despite --noconfirm in
    # recent versions. Pacman proceeds with the default (Y) anyway.
    "Do you want to remove all other packages from cache?",
    "Do you want to remove unused repositories?",
]
# Level markers this playbook writes at the start of a deliberate message. A line opening with one
# is never filtered by the patterns above.
LEVEL_MARKERS = ("[ERROR]", "[FATAL]", "[WARN]")
# Progress bars come in many shapes: pure-hash rows, curl/wget headers, and
# the "######### NN.N%" pattern that NVM/curl emit.
PROGRESS_REGEX = re.compile(
    r'^\s*('
    r'[#\sO=>%\-]+'                                # bar-only rows
    r'|%\s*Total.*Received.*Xferd.*Speed'          # curl header line 1
    r'|\s*Dload\s+Upload\s+Total\s+Spent.*Speed'   # curl header line 2
    r'|\d+(\s+\d+){3,}.*--:--:--'                  # curl progress data row
    r'|[#]+\s+\d+\.\d+%.*'                         # "#### NN.N%" lines
    r')\s*$'
)

# Lines whose level should escalate to WARNING (otherwise stderr stays at INFO).
WARNING_KEYWORDS = re.compile(
    r'\b(warn|warning|deprecat|notice|caution)\b',
    re.IGNORECASE,
)

# Common license-text markers we never want in the log.
LICENSE_PATTERNS = re.compile(
    r"WITHOUT\s+LIMITING\s+THE\s+FOREGOING|"
    r"LIMITATION\s+OF\s+LIABILITY|"
    r"YOUR\s+USE\s+OF\s+THE\s+PREVIEW|"
    r"Terms\s+(?:and|of)\s+(?:Use|Conditions|Service)",
    re.IGNORECASE,
)

# Task names whose per-item skips we want to relabel rather than show raw.
BUILD_LIST_TASK_MARKER = "Build list of packages to dynamically install"

# Tasks whose per-item iteration is *enumeration*, not real install work.
# Per-item events from these tasks are shown in the live log but NOT counted
# in the end-of-run "INSTALLED / ALREADY PRESENT" buckets.
# Matched with a plain substring test against the full task name, role prefix
# included, so an entry here only has to be unique, not complete.
ENUMERATION_TASK_MARKERS = [
    "Build list of packages to dynamically install",
    "Detect installed package-manager helpers",
    "Probe for docker.service unit",
    # A stat over the staged vendor .deb files. It answers whether a download
    # arrived and installs nothing, so it must never land in the installed or
    # already-present buckets. Its current name happens to be excluded by the
    # Install/Download/Add filter below as well; it is named here so that stays
    # true on purpose rather than by accident of wording.
    "Check which vendor .deb files actually arrived",
]

# Task name words that mark a looped task as real install work, whose per-item results land in the
# end-of-run buckets. "Retry" covers a retry that lives in its own task, because Ansible cannot change a
# task's arguments between its own attempts (setup/ansible/tasks/install_role_packages.yaml).
INSTALLER_TASK_KEYWORDS = ("Install", "Download", "Add ", "Retry")

# Task name keywords that mean "this is an OS-specific manager task".
# A skipped item here usually means "we're not on that OS" — we now SHOW
# those entries with a clear label (was: suppress).
OS_MANAGER_KEYWORDS = [
    "APT ", "DNF ", "Pacman", "Snap ", "Flatpak", "Homebrew",
    "brew_cask", "AUR", "Chocolatey", "Winget", "Windows_",
]

# Map role name → list of toggle names we associate with it. Used to attribute
# skipped roles to specific user-facing toggles in the summary.
ROLE_TOGGLE_MAPPING: Dict[str, List[str]] = {
    'gnome_setup':         ['install_gnome', 'configure_gnome'],
    'kde_plasma_setup':    ['install_kde_plasma', 'configure_kde_plasma'],
    'shell_zsh':           ['setup_zsh'],
    'env_variables':       ['set_custom_env', 'configure_env'],
    'system_core':         ['install_system_core'],
    'systemd_boot':        ['setup_systemd_boot', 'setup_grub',
                            'remove_distro_grub', 'remove_distro_systemd_boot'],
    'snapper':             ['install_snapper'],
    'sdk_manager':         ['install_flutter', 'install_android_sdk',
                            'install_nodejs', 'install_python', 'install_java',
                            'install_maven', 'install_gradle'],
    'ai_tools':            ['install_claude_code', 'install_claude_desktop',
                            'install_lm_studio', 'install_stable_diffusion',
                            'install_opencode', 'install_openspec',
                            'install_codex', 'install_grok', 'install_kilo_code',
                            'install_bruno_cli'],
    'software_installer':  [],   # mapped per-software via the toggle key itself
    'virtualization_config': ['install_virt_manager', 'install_docker'],
    'linux_security':      ['install_lynis', 'install_chkrootkit', 'install_clamav'],
    'waydroid':            ['install_waydroid'],
    'jetbrains_toolbox':   ['install_jetbrains_toolbox'],
}

# The group_vars beside this plugin. Whatever they declare as a boolean is a toggle, the same rule
# e2e/tier1/toggle_coverage.sh reads them by.
GROUP_VARS_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "group_vars")
OS_CONDITION_REGEX = re.compile(r"os_family|ansible_system|distribution|architecture|virtualization_role")
_QUOTED_TEXT = re.compile(r"'[^']*'|\"[^\"]*\"")
_FILTER_CALL = re.compile(r"\|\s*\w+(?:\([^()]*\))?")
_IDENTIFIER = re.compile(r"(?<![\w.])[A-Za-z_]\w*")


def _declared_toggles(group_vars_dir: str) -> frozenset:
    names = set()
    try:
        entries = sorted(os.listdir(group_vars_dir))
    except FileNotFoundError:
        return frozenset()
    for entry in entries:
        if not entry.endswith((".yaml", ".yml")):
            continue
        with open(os.path.join(group_vars_dir, entry), encoding="utf-8") as handle:
            data = yaml.safe_load(handle)
        if isinstance(data, dict):
            names.update(key for key, value in data.items() if isinstance(value, bool))
    return frozenset(names)


def _sole_toggle(condition: str, toggles: frozenset) -> Optional[str]:
    """Name the toggle a condition reads when it reads that toggle and nothing else.

    Only then is the toggle being false the one way the condition can be false. A condition that
    also reads a registered result or a fact, negates the toggle, or names a variable that is no
    toggle at all, such as install_failures, says nothing about which part was false.
    """
    bare = _FILTER_CALL.sub(" ", _QUOTED_TEXT.sub(" ", condition))
    names = set(_IDENTIFIER.findall(bare))
    if len(names) != 1:
        return None
    name = names.pop()
    return name if name in toggles else None


def _gap_marker(omitted: int, omitted_errors: int) -> str:
    beyond = (f", {omitted_errors} of them error lines beyond the first {MAX_KEPT_ERROR_LINES} kept"
              if omitted_errors else "")
    return f"... [truncated, {omitted} lines omitted{beyond}]"


def _keep_ends_and_errors(lines: List[str], head: int, tail: int) -> List[str]:
    """Keep the first `head` and last `tail` lines, the earliest MAX_KEPT_ERROR_LINES error lines
    between them, and one marker for each run of dropped lines saying how many went."""
    middle_end = len(lines) - tail
    if middle_end <= head:
        return lines
    errors = [i for i in range(head, middle_end) if ERROR_LINE_REGEX.search(lines[i])]
    kept = set(errors[:MAX_KEPT_ERROR_LINES])
    beyond_cap = set(errors[MAX_KEPT_ERROR_LINES:])
    out = lines[:head]
    gap = gap_errors = 0
    for i in range(head, middle_end):
        if i in kept:
            if gap:
                out.append(_gap_marker(gap, gap_errors))
                gap = gap_errors = 0
            out.append(lines[i])
            continue
        gap += 1
        gap_errors += i in beyond_cap
    if gap:
        out.append(_gap_marker(gap, gap_errors))
    return out + lines[middle_end:]


# --- Plugin ----------------------------------------------------------------

class CallbackModule(CallbackBase):
    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = "stdout"
    CALLBACK_NAME = "dual_logger"

    # ------------------------------------------------------------------
    # Lifecycle
    # ------------------------------------------------------------------
    def __init__(self):
        super().__init__()
        home_dir = _invoking_user_home()
        self.full_log_path     = os.path.join(home_dir, "installation_full.log")
        self.errors_log_path   = os.path.join(home_dir, "installation_errors.log")
        self.warnings_log_path = os.path.join(home_dir, "installation_warnings.log")
        self.skipped_log_path  = os.path.join(home_dir, "installation_skipped.log")
        self.full_log = None
        self.errors_log = None
        self.warnings_log = None
        self.skipped_log = None
        self.allow_failure = False
        self._log_initialized = False

        # Per-task timing and role tracking
        self._task_start_ts: Optional[datetime.datetime] = None
        self._current_role: Optional[str] = None
        self._playbook_start_ts = datetime.datetime.now()
        # Buffered headers — only emitted when a real (non-OS-skip) result
        # arrives. Tasks/roles that consist entirely of OS-mismatch skips
        # never have their TASK header or PHASE banner flushed.
        self._pending_phase: Optional[str] = None
        self._pending_task: Optional[str] = None
        # The same two headers for the terminal, emitted only above a line the terminal shows, so a
        # task or a role whose results were all ok or skipped leaves no header there.
        self._console_phase: Optional[str] = None
        self._console_task: Optional[str] = None
        self._toggles = _declared_toggles(GROUP_VARS_DIR)
        # De-dup state for Ansible warnings/deprecations.
        self._seen_warnings: set = set()

        # End-of-run summary buckets
        self.installed: List[Dict[str, str]] = []   # {name, manager}
        self.unchanged: List[Dict[str, str]] = []   # already-present
        self.skipped_by_reason: Dict[str, List[str]] = {}   # reason → [names]
        self.failed: List[Dict[str, str]] = []      # {name, error, task}
        # Failures the playbook deliberately tolerated (ignore_errors). Kept apart from
        # self.failed so the summary cannot claim a run failed while the run exits zero.
        self.tolerated: List[Dict[str, str]] = []   # {name, error, task}
        # Failed attempts per package of an install task that have not yet ended in success, so a
        # package that installs on a retry is summarised once, as installed after that many retries.
        self._failed_attempts: Dict[str, int] = {}

        # Progress reporter: emits the task START line, one line per new
        # progress entry tailed from the task's log file, and an occasional
        # idle ping when the log hasn't moved. Without this, raw/long tasks
        # (flatpak install, apt upgrade, makepkg) appear hung for 15-60 min.
        self._heartbeat_stop: Optional[threading.Event] = None
        self._heartbeat_thread: Optional[threading.Thread] = None
        self._heartbeat_task_name: str = ""
        self._heartbeat_task_started: float = 0.0
        self._heartbeat_log_path: Optional[str] = None
        self._heartbeat_last_line: str = ""
        self._heartbeat_header_emitted: bool = False
        self._heartbeat_idle_emitted_at: float = 0.0
        # Serialises writes to self.full_log + self._display from the main
        # thread (callback hooks) and the heartbeat daemon thread.
        self._emit_lock = threading.Lock()
        # The heartbeat's live status line. Only a terminal can erase it again, so anything else,
        # a pipe or a file, gets no status line at all and finds the heartbeat in the full log.
        self._status_stream = sys.stdout
        self._live_terminal = self._status_stream.isatty() and os.environ.get("TERM") != "dumb"
        self._status_shown = False
        try:
            self._heartbeat_tick = int(os.environ.get("DUAL_LOGGER_HEARTBEAT_SEC", "5"))
        except ValueError:
            self._heartbeat_tick = 5
        try:
            self._heartbeat_idle_ping = int(os.environ.get("DUAL_LOGGER_IDLE_PING_SEC", "300"))
        except ValueError:
            self._heartbeat_idle_ping = 300

    def set_options(self, task_keys=None, var_options=None, direct=None) -> None:
        super().set_options(task_keys=task_keys, var_options=var_options, direct=direct)
        env_val = os.environ.get("ALLOW_CALLBACK_FAILURE", "").lower()
        if env_val in ("true", "1", "yes"):
            self.allow_failure = True
        elif var_options and "allow_callback_failure" in var_options:
            self.allow_failure = bool(var_options["allow_callback_failure"])
        else:
            self.allow_failure = self.get_option("allow_callback_failure") or False

    def _open_logs(self):
        if self._log_initialized:
            return
        try:
            self.full_log     = open(self.full_log_path,     "w", encoding="utf-8")
            self.errors_log   = open(self.errors_log_path,   "w", encoding="utf-8")
            self.warnings_log = open(self.warnings_log_path, "w", encoding="utf-8")
            self.skipped_log  = open(self.skipped_log_path,  "w", encoding="utf-8")
            self._log_initialized = True
            self.full_log.write(
                f"# Installation Helper — full log\n"
                f"# Started: {self._playbook_start_ts:%Y-%m-%d %H:%M:%S}\n"
                f"# Errors:    {self.errors_log_path}\n"
                f"# Warnings:  {self.warnings_log_path}\n"
                f"# Skipped:   {self.skipped_log_path}\n\n"
            )
            self.full_log.flush()
            self.errors_log.write(f"# Installation Helper — errors only ({self._playbook_start_ts:%Y-%m-%d %H:%M:%S})\n\n")
            self.errors_log.flush()
            self.warnings_log.write(f"# Installation Helper — warnings only ({self._playbook_start_ts:%Y-%m-%d %H:%M:%S})\n\n")
            self.warnings_log.flush()
            self.skipped_log.write(f"# Installation Helper — skipped items ({self._playbook_start_ts:%Y-%m-%d %H:%M:%S})\n\n")
            self.skipped_log.flush()
        except (IOError, OSError, PermissionError) as e:
            msg = f"FATAL: Cannot open log files in {os.path.dirname(self.full_log_path)}: {e}"
            if self.allow_failure:
                sys.stderr.write(f"WARNING: {msg}\nContinuing without file logging.\n")
                self._log_initialized = True
            else:
                sys.stderr.write(msg + "\n")
                sys.exit(1)

    # ------------------------------------------------------------------
    # Small helpers
    # ------------------------------------------------------------------
    def _ts(self) -> str:
        return datetime.datetime.now().strftime("%H:%M:%S")

    def _task_duration(self) -> str:
        """Return '[+X.Xs]' or '[+Hh MMm SSs]' since the most recent task start,
        or '' if unknown. The caller is responsible for spacing — we always
        render right after the timestamp, before the rest of the line."""
        if self._task_start_ts is None:
            return ""
        delta = (datetime.datetime.now() - self._task_start_ts).total_seconds()
        if delta < 0.1:
            return ""
        if delta < 60:
            return f"[+{delta:.1f}s]"
        total = int(delta)
        h, rem = divmod(total, 3600)
        m, s = divmod(rem, 60)
        return f"[+{h}h {m:02d}m {s:02d}s]" if h else f"[+{m}m {s:02d}s]"

    def _should_skip_line(self, line: str) -> bool:
        """Return True if a captured stdout line is noise that should be dropped.

        A line that opens with a level marker was written by this playbook on purpose and is never
        noise, whatever words it holds. The exemption lives here rather than in one caller because
        a repository rescue's [ERROR] line said "the copy already installed", and exempting it only
        in _render_message kept it on the console while _write_log, which asks this method again,
        still dropped it from installation_full.log and installation_errors.log.
        """
        if not line:
            return False
        if line.strip().startswith(LEVEL_MARKERS):
            return False
        if PROGRESS_REGEX.match(line):
            return True
        for pattern in IGNORE_PATTERNS:
            if pattern in line:
                return True
        if LICENSE_PATTERNS.search(line):
            return True
        return False

    @staticmethod
    def _truncate_lines(lines: List[str], limit: int) -> List[str]:
        """Keep the head and the tail of a long block, never the head alone.

        A command that fails says why last. apt lists every dependency it is about to install and
        then prints "E: Failed to fetch" at the very end, so keeping the first 29 lines of 1098 kept
        the dependency list and threw away the only line that explained anything. That is not
        hypothetical: the Debian kde-configure-only cell of 2026-08-21 failed inside the batched apt
        install and the reason was unrecoverable from every log the run produced, because this
        function had already dropped it before anything was written.

        A third of the budget goes to the head, which is where a command names what it is doing, and
        the rest to the tail, which is where it fails. The marker in between says how many lines are
        gone so nobody reads the two halves as contiguous.

        Every error line between them is kept as well, up to MAX_KEPT_ERROR_LINES, because a build
        does not always fail last: the error-details budget of 10 kept 3 head and 6 tail lines of a
        failed build and dropped the "error:" and "BUILD FAILED" lines that sat between them.
        """
        if len(lines) <= limit:
            return lines
        head = max(1, limit // 3)
        tail = max(1, limit - head - 1)
        return _keep_ends_and_errors(lines, head, tail)

    def _extract_task_role(self, task_name: str) -> Optional[str]:
        if not task_name or not isinstance(task_name, str):
            return None
        if ' : ' not in task_name:
            return None
        role = task_name.split(' : ', 1)[0].strip()
        # Filter out Ansible internals so include_role's pseudo-task doesn't
        # produce a spurious phase separator.
        if role.startswith('ansible.builtin.') or role.startswith('ansible.legacy.'):
            return None
        return role

    def _extract_item_display(self, item) -> str:
        if item is None:
            return "unknown"
        if isinstance(item, (str, int, float)):
            return str(item).strip() if isinstance(item, str) else str(item)
        if isinstance(item, dict):
            for key in ("name", "key", "path"):
                if key in item and item[key]:
                    v = item[key]
                    return os.path.basename(v) if key == "path" else str(v)
            if "app" in item and "mime" in item:
                return f"{item['app']} -> {item['mime']}"
            if "option" in item and "value" in item:
                return f"{item['option']}: {item['value']}"
            return repr(item)
        return repr(item)

    # ------------------------------------------------------------------
    # Output routing
    # ------------------------------------------------------------------
    def _write_log(self, msg: str, level: str = "INFO") -> None:
        """Write `msg` to the appropriate log files based on `level`."""
        if not self._log_initialized:
            self._open_logs()
        if self._should_skip_line(msg):
            return
        line = f"[{self._ts()}] {msg}\n"
        # Full log gets everything.
        if self.full_log:
            try: self.full_log.write(line); self.full_log.flush()
            except (IOError, OSError): pass
        # Errors log: ERROR/CRITICAL/FATAL only.
        if self.errors_log and level in ("ERROR", "CRITICAL", "FATAL"):
            try: self.errors_log.write(line); self.errors_log.flush()
            except (IOError, OSError): pass
        # Warnings log: WARNING only.
        if self.warnings_log and level == "WARNING":
            try: self.warnings_log.write(line); self.warnings_log.flush()
            except (IOError, OSError): pass

    def _render_message(self, blob, level: str, show: bool = True) -> None:
        """Display and log a debug task's `msg`, whatever shape it arrived in.

        A debug msg is a string, a list of strings, or a mapping, and the playbook uses the first
        two. The level is taken from the text rather than from the task, because a debug task is
        always ok as far as Ansible is concerned while its message is often the only record that
        something was lost. A message opening with [ERROR] therefore reaches installation_errors.log
        and one opening with [WARN], or matching the same keywords stderr is judged by, reaches
        installation_warnings.log.

        A message the terminal would not show, because its task was ok, is shown all the same when
        any of its lines opens with a level marker, since that marker is the playbook saying out
        loud that something was lost or went wrong.
        """
        if isinstance(blob, str):
            lines = blob.strip().split("\n")
        elif isinstance(blob, (list, tuple)):
            lines = [str(entry) for entry in blob]
        elif isinstance(blob, dict):
            lines = [f"{key}: {value}" for key, value in blob.items()]
        else:
            return

        lines = [ln for ln in lines if ln.strip() and not self._should_skip_line(ln)]
        visible = show or any(ln.strip().startswith(LEVEL_MARKERS) for ln in lines)
        for ln in self._truncate_lines(lines, STDOUT_TRUNCATE_LINES):
            stripped = ln.strip()
            if stripped.startswith("[ERROR]") or stripped.startswith("[FATAL]"):
                line_lvl = "ERROR"
            elif stripped.startswith("[WARN]") or WARNING_KEYWORDS.search(ln):
                line_lvl = "WARNING"
            else:
                line_lvl = level
            if visible:
                self._show(f"  {ln}")
            self._write_log(f"  {ln}", line_lvl)

    def _show(self, text: str) -> None:
        """Print a line on the terminal, after the phase banner and task header it belongs under
        when they have not been printed yet, erasing the heartbeat's status line first."""
        self._clear_status()
        if self._console_phase is not None:
            self._display.display(f"\n{PHASE_BAR}\n  PHASE: {self._console_phase}\n{PHASE_BAR}")
            self._console_phase = None
        if self._console_task is not None:
            self._display.display(f"[{self._ts()}] TASK [{self._console_task}]")
            self._console_task = None
        self._display.display(text)

    def _display_and_log(self, msg: str, level: str = "INFO",
                         include_output: bool = False, result=None, show: bool = True) -> None:
        """Log `msg`, and print it on the terminal too when `show` is true."""
        if show:
            self._show(f"[{self._ts()}] {msg}")
        self._write_log(msg, level)
        if include_output and result is not None:
            rd = result._result if hasattr(result, "_result") else {}
            # A debug task's text lives in `msg`, and `msg` was not rendered here at all, so every
            # ansible.builtin.debug task in this repository printed nothing: not on the console, not
            # in installation_full.log, not in installation_warnings.log. That is over thirty
            # callsites, including all twelve rescue explanations in site.yaml, the installer rescue
            # that names the failing step and says everything after it was skipped, and every warning
            # about software that could not be installed. Proven with a probe playbook run through
            # this callback: a marker sent through `command` stdout appeared on the console and in the
            # full log, and the same marker sent through `debug` appeared in neither. One earlier
            # defect was worked around by rewriting a single debug task as a shell command, which
            # fixed one message and left the rest invisible.
            #
            # Restricted to the debug action on purpose. Many modules return an incidental `msg` on
            # success, get_url and apt among them, and rendering those for every ok task would bury
            # the deliberate messages this exists to surface.
            if self._is_debug_task(result):
                self._render_message(rd.get("msg"), level, show)
            # stdout stays at the task's level. stderr defaults to INFO and is
            # only promoted to WARNING for lines that actually look like warnings
            # (keeps curl/wget progress and git output out of the warnings log).
            for key, default_lvl in (("stdout", level), ("stderr", "INFO")):
                blob = rd.get(key)
                if not isinstance(blob, str) or not blob.strip():
                    continue
                lines = [ln for ln in blob.strip().split("\n")
                         if ln.strip() and not self._should_skip_line(ln)]
                lines = self._truncate_lines(lines, STDOUT_TRUNCATE_LINES)
                for ln in lines:
                    line_lvl = default_lvl
                    if key == "stderr" and WARNING_KEYWORDS.search(ln):
                        line_lvl = "WARNING"
                    if show:
                        self._show(f"  {ln}")
                    self._write_log(f"  {ln}", line_lvl)
            # Ansible's own warnings array (from module `warn:` outputs).
            # De-duplicate against entries we've already logged this run so
            # the same Ansible-level deprecation doesn't appear 60+ times.
            for w in rd.get("warnings") or []:
                w_text = str(w)
                if self._should_skip_line(f"  [warning] {w_text}"):
                    continue
                if w_text in self._seen_warnings:
                    continue
                self._seen_warnings.add(w_text)
                if show:
                    self._show(f"  [warning] {w_text}")
                self._write_log(f"  [warning] {w_text}", "WARNING")
            for d in rd.get("deprecations") or []:
                d_text = d.get("msg", str(d)) if isinstance(d, dict) else str(d)
                if self._should_skip_line(f"  [deprecation] {d_text}"):
                    continue
                if d_text in self._seen_warnings:
                    continue
                self._seen_warnings.add(d_text)
                if show:
                    self._show(f"  [deprecation] {d_text}")
                self._write_log(f"  [deprecation] {d_text}", "WARNING")

    def _log_phase_separator(self, role: str) -> None:
        if self.full_log:
            try: self.full_log.write(f"\n{PHASE_BAR}\n[{self._ts()}]   PHASE: {role}\n{PHASE_BAR}\n\n"); self.full_log.flush()
            except (IOError, OSError): pass

    def _flush_pending(self) -> None:
        """Write any queued PHASE banner and TASK header to the log. Called from result
        handlers right before they log their own line — so phases / tasks
        that are entirely skipped (e.g. every Fedora task while on Debian)
        never produce output. The terminal's copies are printed by _show."""
        if self._pending_phase is not None:
            self._log_phase_separator(self._pending_phase)
            self._pending_phase = None
        if self._pending_task is not None:
            self._write_log(f"TASK [{self._pending_task}]", "INFO")
            self._pending_task = None

    # ------------------------------------------------------------------
    # Skip categorisation
    # ------------------------------------------------------------------
    def _categorise_skip(self, result, item_key: Optional[str]) -> str:
        """Return a short human-readable reason for the skip of one item, or of the whole task when
        item_key is None.

        A skip is called a disabled toggle only when the toggle is provably the reason: the
        build-list task's own per-item condition, or a false condition that reads one declared toggle
        and nothing else. The build-list shortcut was once applied to the task-level skip as well,
        with the task name standing in for the item, which printed "toggle disabled
        (install_software_installer : Build list of packages to dynamically install=false)". Any
        other condition is named as it is, because the callback cannot tell which part of it was
        false.
        """
        try:
            task_name = result._task.get_name() if hasattr(result, "_task") else ""
        except (AttributeError, TypeError):
            task_name = ""
        rd = result._result if hasattr(result, "_result") else {}
        skip_reason = rd.get("skipped_reason", "") or rd.get("skip_reason", "")
        false_cond = rd.get("false_condition", "") or ""

        # The build-list task per-item skip means the install_<key> toggle is false.
        if item_key is not None and BUILD_LIST_TASK_MARKER in task_name:
            return f"toggle disabled (install_{item_key}=false)"

        # Inspect the recorded false_condition first — it's authoritative.
        if false_cond:
            if OS_CONDITION_REGEX.search(false_cond):
                return "not for this OS"
            toggle = _sole_toggle(false_cond, self._toggles)
            if toggle:
                return f"toggle disabled ({toggle}=false)"

        # Last-resort: task-name heuristic for OS-manager tasks.
        if any(k in task_name for k in OS_MANAGER_KEYWORDS):
            return "not for this OS"

        if false_cond:
            return "condition not met: " + " ".join(false_cond.split())

        # A looped task whose every item was skipped. Each item carries its own reason.
        if isinstance(rd.get("results"), list) and rd["results"]:
            return "every item skipped"

        if "Conditional result was False" in str(skip_reason):
            return "condition not met"

        return skip_reason or "condition not met"

    # ------------------------------------------------------------------
    # Progress reporter for long-blocking tasks
    # ------------------------------------------------------------------
    def _heartbeat_lookup_log(self, task_name: str) -> Optional[str]:
        best_prefix = ""
        best_path: Optional[str] = None
        for prefix, path in HEARTBEAT_LOG_FILES.items():
            if prefix in task_name and len(prefix) > len(best_prefix):
                best_prefix = prefix
                best_path = path
        return best_path

    def _read_last_log_line(self) -> str:
        path = self._heartbeat_log_path
        if not path or not os.path.exists(path):
            return ""
        try:
            with open(path, "rb") as fh:
                fh.seek(0, os.SEEK_END)
                size = fh.tell()
                fh.seek(max(0, size - 4096))
                tail = fh.read().decode("utf-8", errors="replace")
        except (IOError, OSError):
            return ""
        for ln in reversed(tail.splitlines()):
            ln = ln.strip()
            if ln:
                return ln[:160] + "…" if len(ln) > 160 else ln
        return ""

    def _emit_progress(self, line: str) -> None:
        with self._emit_lock:
            try:
                if self.full_log:
                    self.full_log.write(f"[{self._ts()}] {line}\n")
                    self.full_log.flush()
            except (IOError, OSError):
                pass

    def _show_status(self, text: str, stop: threading.Event) -> None:
        """Replace the live status line on the terminal with `text`, cut to the terminal's width
        because a line that wraps can no longer be erased."""
        width = max(20, shutil.get_terminal_size((80, 24)).columns - 1)
        with self._emit_lock:
            if stop.is_set():
                return
            try:
                self._status_stream.write(ERASE_LINE + text[:width])
                self._status_stream.flush()
                self._status_shown = True
            except (IOError, OSError):
                pass

    def _clear_status(self) -> None:
        with self._emit_lock:
            if not self._status_shown:
                return
            try:
                self._status_stream.write(ERASE_LINE)
                self._status_stream.flush()
            except (IOError, OSError):
                pass
            self._status_shown = False

    def _emit_running_header_once(self) -> None:
        if self._heartbeat_header_emitted:
            return
        self._emit_progress(f"  ⏳ running: {self._heartbeat_task_name}")
        self._heartbeat_header_emitted = True
        self._heartbeat_idle_emitted_at = time.monotonic()

    def _heartbeat_loop(self) -> None:
        """Write the heartbeat to the full log, and keep one live status line on a terminal.

        The heartbeat used to print its lines on the terminal as permanent lines, so every task
        over two seconds left a "running:" line behind even when it then ended ok and nothing else
        about it was shown. The status line is erased before any other terminal line and when the
        task ends, so it says the run is alive without leaving anything behind.
        """
        stop = self._heartbeat_stop
        assert stop is not None
        while not stop.wait(self._heartbeat_tick):
            now = time.monotonic()
            elapsed = int(now - self._heartbeat_task_started)
            m, s = divmod(elapsed, 60)

            last_line = self._read_last_log_line()
            if last_line and last_line != self._heartbeat_last_line:
                self._emit_running_header_once()
                self._emit_progress(f"  ↳ [{m:02d}m{s:02d}s] {last_line}")
                self._heartbeat_last_line = last_line
                self._heartbeat_idle_emitted_at = now
            elif not self._heartbeat_header_emitted and elapsed >= 2:
                self._emit_running_header_once()
            elif self._heartbeat_header_emitted and (now - self._heartbeat_idle_emitted_at) >= self._heartbeat_idle_ping:
                self._emit_progress(f"  ↳ [{m:02d}m{s:02d}s] still working… (log unchanged)")
                self._heartbeat_idle_emitted_at = now

            if self._live_terminal and self._heartbeat_header_emitted:
                progress = f"  ↳ {self._heartbeat_last_line}" if self._heartbeat_last_line else ""
                self._show_status(f"⏳ [{m:02d}m{s:02d}s] {self._heartbeat_task_name}{progress}", stop)

    def _start_heartbeat(self, task_name: str) -> None:
        self._stop_heartbeat()
        self._heartbeat_task_name = task_name
        self._heartbeat_task_started = time.monotonic()
        self._heartbeat_log_path = self._heartbeat_lookup_log(task_name)
        self._heartbeat_last_line = ""
        self._heartbeat_header_emitted = False
        self._heartbeat_idle_emitted_at = 0.0
        self._heartbeat_stop = threading.Event()
        self._heartbeat_thread = threading.Thread(target=self._heartbeat_loop, daemon=True)
        self._heartbeat_thread.start()

    def _stop_heartbeat(self) -> None:
        if self._heartbeat_stop is not None:
            self._heartbeat_stop.set()
        if self._heartbeat_thread is not None and self._heartbeat_thread.is_alive():
            self._heartbeat_thread.join(timeout=0.5)
        self._heartbeat_thread = None
        self._heartbeat_stop = None
        self._heartbeat_log_path = None
        self._clear_status()

    # ------------------------------------------------------------------
    # Ansible callback hooks
    # ------------------------------------------------------------------
    def v2_playbook_on_start(self, playbook) -> None:
        self._open_logs()

    def v2_playbook_on_play_start(self, play) -> None:
        # Stop any heartbeat from the prior play before the next task starts.
        self._stop_heartbeat()
        self._console_task = None
        self._display_and_log(f"PLAY [{play.get_name()}]", "INFO")

    def v2_playbook_on_task_start(self, task, is_conditional: bool = False) -> None:
        name = task.get_name()
        self._task_start_ts = datetime.datetime.now()
        self._start_heartbeat(name)

        # Buffer phase + task headers; emit lazily on first non-OS-skip result.
        role = self._extract_task_role(name)
        if role and role != self._current_role:
            self._pending_phase = role
            self._console_phase = role
            self._current_role = role
        self._pending_task = name
        self._console_task = name

    def v2_playbook_on_handler_task_start(self, task) -> None:
        self._task_start_ts = datetime.datetime.now()
        self._start_heartbeat(task.get_name())
        self._pending_task = f"HANDLER: {task.get_name()}"
        self._console_task = self._pending_task

    # --- task-level results ---
    def v2_runner_on_ok(self, result) -> None:
        self._stop_heartbeat()
        self._flush_pending()
        host = result._host.get_name()
        changed = bool(result._result.get("changed", False)) if hasattr(result, "_result") else False
        status = "CHANGED" if changed else "ok"
        dur = self._task_duration()
        prefix = f"{dur} " if dur else ""
        self._display_and_log(f"{prefix}{status}: [{host}]", "INFO",
                              include_output=True, result=result, show=changed)

    def v2_runner_on_failed(self, result, ignore_errors: bool = False) -> None:
        """A task failed. `ignore_errors` says whether the playbook asked for that failure to be
        tolerated, and this hook used to discard the argument entirely: an ignored failure was
        rendered under the same FAILED heading, written to installation_errors.log, and counted in
        the end-of-run FAILED section, while the run went on to exit zero. So the summary said
        FAILED (3) three lines above a recap reading `failed=0 ignored=3`, which is the exact
        inversion an operator cannot resolve from the output. A tolerated failure is now labelled
        as tolerated, logged as a warning rather than an error, and summarised in its own section.
        The run's verdict is decided by any_role_failed in site.yaml, never by this bucket."""
        self._stop_heartbeat()
        self._flush_pending()
        host = result._host.get_name()
        task_name = result._task.get_name() if hasattr(result, "_task") else "unknown"
        dur = self._task_duration()
        prefix = f"{dur} " if dur else ""
        level = "WARNING" if ignore_errors else "ERROR"
        label = "TOLERATED FAILURE" if ignore_errors else "FAILED"
        self._display_and_log(f"{prefix}{label}: [{host}] => TASK: {task_name}", level)
        self._report_error_details(result, level)
        # End-of-run bucket
        rd = result._result if hasattr(result, "_result") else {}
        short = rd.get("msg", rd.get("stderr", "unknown error"))
        if isinstance(short, str) and len(short) > 200:
            short = short[:200] + "..."
        entry = {"task": task_name, "name": task_name, "error": short}
        (self.tolerated if ignore_errors else self.failed).append(entry)

    def v2_runner_on_skipped(self, result) -> None:
        self._stop_heartbeat()
        host = result._host.get_name()
        task_name = result._task.get_name() if hasattr(result, "_task") else ""
        reason = self._categorise_skip(result, item_key=None)
        # Don't log "not for this OS" task-level skips — drop the buffered
        # TASK header. The PHASE banner stays queued for the role's first
        # real result: dropping it here, as this once did, lost the banner of
        # every role whose first task was for another OS. A role entirely
        # composed of OS-mismatch skips still produces no output, because the
        # next role's banner replaces its queued one.
        if reason == "not for this OS":
            self._pending_task = None
            self._console_task = None
            return
        self._flush_pending()
        self._display_and_log(f"skipping: [{host}] {task_name} [{reason}]", "INFO", show=False)

    def v2_runner_on_unreachable(self, result) -> None:
        self._stop_heartbeat()
        self._flush_pending()
        host = result._host.get_name()
        task_name = result._task.get_name() if hasattr(result, "_task") else "unknown"
        dur = self._task_duration()
        prefix = f"{dur} " if dur else ""
        self._display_and_log(f"{prefix}unreachable: [{host}] TASK: {task_name}", "ERROR")
        self._report_error_details(result, "ERROR")

    def v2_runner_retry(self, result) -> None:
        """An attempt of a task with `until` failed and Ansible is about to run it again.

        Without this hook a retry left nothing in any log, so a first attempt that failed and was then
        skipped by its own `creates` guard read as one clean ok. That is how sweep 38107292439 hid the
        SDKMAN installer dying halfway: the only trace was a ten second gap before the ok line. A
        retry is a failure the run tolerated, so it is logged as a warning.
        """
        self._flush_pending()
        host = result._host.get_name()
        task_name = result._task.get_name() if hasattr(result, "_task") else "unknown"
        rd = result._result if hasattr(result, "_result") else {}
        item = f" ({self._extract_item_display(rd['item'])})" if "item" in rd else ""
        if "item" in rd and self._is_installer_task(task_name):
            self._count_failed_attempt(self._item_key(rd["item"]))
        dur = self._task_duration()
        prefix = f"{dur} " if dur else ""
        self._display_and_log(
            f"{prefix}RETRYING: [{host}] => TASK: {task_name}{item}, attempt "
            f"{rd.get('attempts', '?')} of {rd.get('retries', '?')} failed", "WARNING")
        for detail in self._retry_details(rd):
            self._display_and_log(detail, "WARNING")

    @staticmethod
    def _retry_details(rd: dict) -> List[str]:
        details = []
        if rd.get("msg"):
            details.append(f"  msg: {rd['msg']}")
        if "rc" in rd:
            details.append(f"  rc: {rd['rc']}")
        stderr = rd.get("stderr")
        if isinstance(stderr, str) and stderr.strip():
            lines = [ln for ln in stderr.strip().splitlines() if ln.strip()]
            details.append(f"  stderr, last {min(len(lines), RETRY_STDERR_TAIL_LINES)} lines and the error lines before them:")
            details.extend(f"    {ln}" for ln in _keep_ends_and_errors(lines, 0, RETRY_STDERR_TAIL_LINES))
        return details

    # --- per-item (looped) results ---
    @staticmethod
    def _informative_line(rd: dict) -> str:
        """Pick the line from a failed result that says what went wrong.

        Two wrong answers were tried before this one, both measured rather than reasoned about.

        Taking the first line of stderr looked obvious: makepkg pipes curl's progress meter there, so a
        failed AUR build reported itself as "% Total % Received % Xferd Average Speed", the least
        informative text in the whole result, while the real cause was never printed anywhere.

        Preferring the module's own `msg` was the second: for a failed command that is the string
        "non-zero return code", which says only what the reader already knows from the return code
        printed beside it.

        So every candidate field is searched for a line that looks like a diagnosis, stderr first
        because it is the most specific, and each field is read from the end because the useful line of
        a build log is near its finish. The generic message is the last resort rather than the first.
        """
        fields = [rd.get(k) for k in ("stderr", "module_stderr", "stdout", "msg")]
        blobs = [f for f in fields if isinstance(f, str) and f.strip()]
        if not blobs:
            return ""

        keywords = ("error", "failed", "failure", "not found", "cannot", "unable",
                    "denied", "no such", "timed out", "aborting", "refused")
        for blob in blobs:
            lines = [ln.strip() for ln in blob.strip().splitlines() if ln.strip()]
            for line in reversed(lines):
                if any(word in line.lower() for word in keywords):
                    return line[:200]

        lines = [ln.strip() for ln in blobs[0].strip().splitlines() if ln.strip()]
        return lines[-1][:200] if lines else ""

    def v2_runner_item_on_ok(self, result) -> None:
        self._flush_pending()
        host = result._host.get_name()
        item = result._result.get("item", "unknown")
        display = self._extract_item_display(item)
        changed = bool(result._result.get("changed", False))

        # A task carrying failed_when: false sends its per-item failures here, to the ok hook, with
        # changed false and a non-zero rc, and reading only `changed` rendered every one of them as
        # "present". That is how an AUR build that exited non-zero appeared in a real Arch run as
        # `present: lens` and landed in the ALREADY PRESENT bucket, three lines above the warning
        # saying pacman did not have it. Read as a whole, the log contradicted itself.
        #
        # rc, not the result's `failed` key: failed_when has already rewritten that key, and
        # e2e/tier1/failed_key_reads.sh forbids reading it for exactly this reason.
        rc = result._result.get("rc")
        task_name_early = result._task.get_name() if hasattr(result, "_task") else ""
        enumerating = any(m in task_name_early for m in ENUMERATION_TASK_MARKERS)

        # An enumeration task asks whether something is there, so a non-zero code is its way of saying
        # no and not a failure to report. Without this the helper probe rendered as
        # `TOLERATED: brew -- rc 1, which: no brew in ...` on every Linux run, which is a correct answer
        # dressed as a problem. Reporting a non-failure as a failure erodes the same trust as the
        # reverse, and this callback had just been changed to fix the reverse.
        tolerated = isinstance(rc, int) and rc != 0 and not enumerating

        if tolerated:
            status = "TOLERATED"
            level = "WARNING"
        elif changed:
            status = "INSTALLED"
            level = "INFO"
        elif enumerating and isinstance(rc, int) and rc != 0:
            status = "absent"
            level = "INFO"
        else:
            status = "present"
            level = "INFO"

        suffix = ""
        if tolerated:
            suffix = f" -- rc {rc}" + (f", {self._informative_line(result._result)}"
                                       if self._informative_line(result._result) else "")
        self._display_and_log(f"{status:>10}: [{host}] {display}{suffix}", level, show=tolerated or changed)
        # A looped debug task carries its message on each item, and nothing rendered it.
        if self._is_debug_task(result):
            self._render_message(result._result.get("msg"), level, show=False)
        # End-of-run bucket — exclude enumeration tasks so they don't pollute
        # the "ALREADY PRESENT" count with items that were merely listed.
        task_name = result._task.get_name() if hasattr(result, "_task") else ""
        if any(m in task_name for m in ENUMERATION_TASK_MARKERS):
            return
        if not self._is_installer_task(task_name):
            return
        role = self._extract_task_role(task_name) or ""
        manager = ""
        if isinstance(item, dict):
            manager = (item.get("value", {}) or {}).get("manager", "")
        if not manager and role:
            manager = role
        entry = {"name": self._item_key(item), "manager": manager or "other"}
        if tolerated:
            # Its own bucket, so the summary never counts a failed item as one that was already there.
            entry["reason"] = f"rc {rc}"
            self._count_failed_attempt(entry["name"])
            self._record_tolerated_item(entry)
        else:
            self._record_succeeded_item(entry, changed)

    @staticmethod
    def _is_debug_task(result) -> bool:
        task_action = getattr(getattr(result, "_task", None), "action", "") or ""
        return task_action.split(".")[-1] == "debug"

    @staticmethod
    def _is_installer_task(task_name: str) -> bool:
        return any(word in task_name for word in INSTALLER_TASK_KEYWORDS)

    def _item_key(self, item) -> str:
        return item["key"] if isinstance(item, dict) and "key" in item else self._extract_item_display(item)

    def _count_failed_attempt(self, name: str) -> None:
        self._failed_attempts[name] = self._failed_attempts.get(name, 0) + 1

    def _record_tolerated_item(self, entry: Dict[str, str]) -> None:
        """A package that failed its first attempt and its retry is one failure, reported with the
        last reason rather than once per attempt."""
        self.tolerated = [e for e in self.tolerated if e.get("name") != entry["name"]] + [entry]

    def _record_succeeded_item(self, entry: Dict[str, str], changed: bool) -> None:
        """A success after failed attempts takes the package out of the tolerated failures, so the
        summary lists it once, as installed after its retries, instead of under both headings."""
        retries = self._failed_attempts.pop(entry["name"], 0)
        if retries:
            entry["retries"] = retries
            self.tolerated = [e for e in self.tolerated if e.get("name") != entry["name"]]
        (self.installed if changed else self.unchanged).append(entry)

    def v2_runner_item_on_failed(self, result) -> None:
        """Ansible passes no ignore_errors argument to the per-item hook, so the flag is read off
        the task itself. Without this a tolerated per-item failure was still rendered as FAILED and
        pushed into the failed bucket, which is how one vendor .deb download whose failure the
        playbook deliberately absorbs still produced a FAILED section on a run that exited zero."""
        self._flush_pending()
        host = result._host.get_name()
        item = result._result.get("item", "unknown")
        display = self._extract_item_display(item)
        task_name = result._task.get_name() if hasattr(result, "_task") else "unknown"
        rd = result._result if hasattr(result, "_result") else {}
        short = rd.get("msg", rd.get("stderr", "unknown error"))
        if isinstance(short, str) and len(short) > 200:
            short = short[:200] + "..."
        tolerated = self._task_tolerates_failure(result)
        level = "WARNING" if tolerated else "ERROR"
        label = "TOLERATED" if tolerated else "FAILED"
        self._display_and_log(f"{label:>10}: [{host}] {display} -- {short}", level)
        self._report_error_details(result, level)
        entry = {"task": task_name, "name": self._item_key(item), "error": short}
        if not tolerated:
            self.failed.append(entry)
            return
        if self._is_installer_task(task_name):
            self._count_failed_attempt(entry["name"])
        self._record_tolerated_item(entry)

    @staticmethod
    def _task_tolerates_failure(result) -> bool:
        raw = getattr(getattr(result, "_task", None), "ignore_errors", False)
        if isinstance(raw, str):
            return raw.strip().lower() in ("true", "yes", "1")
        return bool(raw)

    def v2_runner_item_on_skipped(self, result) -> None:
        host = result._host.get_name()
        item = result._result.get("item", "unknown")
        display = self._extract_item_display(item)
        item_key = item.get("key", display) if isinstance(item, dict) else display

        reason = self._categorise_skip(result, item_key)

        # Drop OS-mismatch noise entirely. When running on Debian we don't
        # need to see every macOS / Arch / Fedora task's per-item skips.
        if reason == "not for this OS":
            return

        task_name = result._task.get_name() if hasattr(result, "_task") else ""
        role = self._extract_task_role(task_name) or ""

        # Only summarise per-item skips that look like real installer iterations
        # (Install/Download/Add tasks looping over package lists). Config-style
        # loops (ini_file, lineinfile, copy of dotfiles) emit per-item events
        # like `option: Command, value: /usr/bin/zsh` that are useless as
        # user-facing skip entries — let the task-level v2_runner_on_skipped
        # console line cover them instead.
        is_installer_task = self._is_installer_task(task_name)
        qualified = f"{role} → {item_key}" if role else item_key

        # Real skip — flush the pending TASK header / PHASE banner.
        self._flush_pending()
        self._display_and_log(f"{'skipped':>10}: [{host}] {qualified} [{reason}]", "INFO", show=False)
        if not is_installer_task:
            return
        self.skipped_by_reason.setdefault(reason, []).append(qualified)
        if self.skipped_log:
            try:
                self.skipped_log.write(f"[{self._ts()}] {qualified} [{reason}]\n")
                self.skipped_log.flush()
            except (IOError, OSError):
                pass

    # --- play notifications ---
    def v2_on_file_diff(self, result) -> None:
        if result._result.get("diff"):
            self._display_and_log(f"diff: {result._result['diff']}", "INFO")

    def v2_playbook_on_include(self, included_file) -> None:
        self._display_and_log(f"included: {included_file._filename}", "INFO", show=False)

    def v2_playbook_on_import_for_host(self, result, imported_file: str) -> None:
        host = result._host.get_name()
        self._display_and_log(f"imported: {imported_file} for host {host}", "INFO", show=False)

    def v2_playbook_on_not_import_for_host(self, result, missing_file: str) -> None:
        host = result._host.get_name()
        self._display_and_log(f"NOT imported: {missing_file} for host {host}", "WARNING")

    def v2_playbook_on_no_hosts_matched(self) -> None:
        self._display_and_log("no hosts matched", "WARNING")

    def v2_playbook_on_no_hosts_remaining(self) -> None:
        self._display_and_log("NO MORE HOSTS LEFT", "ERROR")

    def v2_playbook_on_notify(self, handler, host) -> None:
        self._display_and_log(f"NOTIFIED HANDLER {handler} for host {host}", "INFO", show=False)

    # ------------------------------------------------------------------
    # End-of-run recap + grouped summary
    # ------------------------------------------------------------------
    @staticmethod
    def _format_duration(seconds: float) -> str:
        total = max(0, int(seconds))
        h, rem = divmod(total, 3600)
        m, s = divmod(rem, 60)
        if h:
            return f"{h}h {m:02d}m {s:02d}s ({total}s)"
        if m:
            return f"{m}m {s:02d}s ({total}s)"
        return f"{s}s"

    def v2_playbook_on_stats(self, stats) -> None:
        self._stop_heartbeat()
        self._console_phase = None
        self._console_task = None
        bar = "═" * 70
        elapsed = datetime.datetime.now() - self._playbook_start_ts
        self._display_and_log("", "INFO")
        self._display_and_log(bar, "INFO")
        self._display_and_log(f"  PLAY RECAP — wall time {self._format_duration(elapsed.total_seconds())}", "INFO")
        self._display_and_log(bar, "INFO")

        total_rescued = 0
        for host in sorted(stats.processed.keys()):
            hs = stats.summarize(host)
            total_rescued += hs['rescued']
            recap = (f"{host}: ok={hs['ok']} changed={hs['changed']} "
                     f"unreachable={hs['unreachable']} failed={hs['failures']} "
                     f"skipped={hs['skipped']} rescued={hs['rescued']} ignored={hs['ignored']}")
            self._display_and_log(recap, "INFO")
            if hs['failures'] > 0 or hs['unreachable'] > 0:
                if self.errors_log:
                    try:
                        self.errors_log.write(f"[{self._ts()}] RECAP: {recap}\n")
                        self.errors_log.flush()
                    except (IOError, OSError):
                        pass

        self._emit_summary_section("INSTALLED (newly added)", self.installed, "  ✓ ")
        self._emit_summary_section("ALREADY PRESENT (unchanged)", self.unchanged, "  · ")
        self._emit_skipped_summary()
        self._emit_tolerated_summary()
        self._emit_failed_summary(rescued_count=total_rescued)

        finish = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        self._display_and_log(f"Playbook finished at {finish}", "INFO")

        for fh in (self.full_log, self.errors_log, self.warnings_log, self.skipped_log):
            if fh:
                try: fh.close()
                except (IOError, OSError): pass

    def _emit_summary_section(self, title: str, items: List[Dict[str, str]], bullet: str) -> None:
        if not items:
            return
        self._display_and_log("", "INFO")
        self._display_and_log(f"═══ {title} ({len(items)}) ═══", "INFO")
        # Group by manager when present
        by_manager: Dict[str, List[str]] = {}
        for it in items:
            mgr = it.get("manager") or "other"
            by_manager.setdefault(mgr, []).append(it["name"] + self._retries_suffix(it.get("retries", 0)))
        for mgr in sorted(by_manager.keys()):
            names = sorted(set(by_manager[mgr]))
            self._display_and_log(f"  {mgr}: {', '.join(names)}", "INFO")

    @staticmethod
    def _retries_suffix(retries: int) -> str:
        if not retries:
            return ""
        return f" (after {retries} {'retry' if retries == 1 else 'retries'})"

    def _emit_skipped_summary(self) -> None:
        """List the skipped items in installation_full.log, and on the terminal only say how many
        there were and where they are, so the terminal summary names only what the run was asked to
        install and never the applications whose toggle is off."""
        if not self.skipped_by_reason:
            return
        self._display_and_log("", "INFO", show=False)
        total = sum(len(v) for v in self.skipped_by_reason.values())
        self._display_and_log(f"═══ SKIPPED ({total}) ═══", "INFO", show=False)
        for reason, names in sorted(self.skipped_by_reason.items()):
            unique = sorted(set(names))
            self._display_and_log(f"  [{reason}] ({len(unique)})", "INFO", show=False)
            self._display_and_log(f"    {', '.join(unique)}", "INFO", show=False)
        self._show(f"[{self._ts()}] ")
        self._show(f"[{self._ts()}] ═══ SKIPPED ({total}), each with its reason in {self.skipped_log_path} ═══")

    def _emit_tolerated_summary(self) -> None:
        """Failures the playbook asked to absorb. Reported at WARNING, never at ERROR, because the
        run's verdict does not depend on them: whatever mattered about them is recorded separately
        by the task that sets any_role_failed."""
        if not self.tolerated:
            return
        self._display_and_log("", "INFO")
        self._display_and_log(
            f"═══ TOLERATED FAILURES ({len(self.tolerated)}, the run continued past each) ═══",
            "WARNING")
        for entry in self.tolerated:
            self._display_and_log(f"  ! {entry['name']}", "WARNING")
            if entry.get("error"):
                self._display_and_log(f"      reason: {entry['error']}", "WARNING")

    def _emit_failed_summary(self, rescued_count: int = 0) -> None:
        if not self.failed:
            return
        self._display_and_log("", "INFO")
        n = len(self.failed)
        # If Ansible's stats show every failure was caught by `rescue:`, label
        # it so the FAILED (3) header doesn't look like it contradicts
        # the recap line where `failed=0`.
        if rescued_count >= n:
            header = f"FAILED ({n}, caught by rescue — playbook continued)"
        elif rescued_count > 0:
            header = f"FAILED ({n}; {rescued_count} caught by rescue)"
        else:
            header = f"FAILED ({n})"
        self._display_and_log(f"═══ {header} ═══", "ERROR")
        for entry in self.failed:
            self._display_and_log(f"  • {entry['name']}", "ERROR")
            if entry.get("error"):
                self._display_and_log(f"      reason: {entry['error']}", "ERROR")

    # ------------------------------------------------------------------
    # Error detail extraction (preserved from the previous version)
    # ------------------------------------------------------------------
    def _report_error_details(self, result, level: str) -> None:
        """Show and log what a failed or unreachable result says went wrong, and write its traceback
        to installation_full.log alone, because a traceback is for whoever debugs the callback or a
        module, and ansible-core 2.19 and later send the placeholder "(traceback unavailable)" in its
        place unless tracebacks are switched on, which printed "Exception (full):" over that
        placeholder under every failure on the terminal."""
        for detail in self._extract_error_details(result):
            self._display_and_log(detail, level)
        rd = result._result if hasattr(result, "_result") else {}
        for line in self._traceback_lines(rd):
            self._write_log(line, "INFO")

    @staticmethod
    def _traceback_lines(rd: dict) -> List[str]:
        exception = rd.get("exception")
        if not isinstance(exception, str) or exception.strip() in ("", TRACEBACK_PLACEHOLDER):
            return []
        exc_lines = [ln for ln in exception.strip().split("\n") if ln.strip()]
        keep = exc_lines[-15:]
        header = f"  Exception ({'last 15 lines' if len(exc_lines) > 15 else 'full'}):"
        return [header] + [f"    {ln}" for ln in keep]

    def _extract_error_details(self, result) -> List[str]:
        details: List[str] = []
        rd = result._result if hasattr(result, "_result") else {}

        if "msg" in rd:
            details.append(f"  Error: {rd['msg']}")
        elif rd.get("stderr"):
            details.append(f"  stderr: {rd['stderr']}")

        for field in ("stdout", "stderr", "stdout_lines", "stderr_lines"):
            data = rd.get(field)
            if not data:
                continue
            # ansible-core sends a command's output twice, as text and as its list of lines, and
            # both used to be printed, so every failed command showed its output twice.
            if field.endswith("_lines") and rd.get(field[:-len("_lines")]):
                continue
            if isinstance(data, str):
                lines = [ln for ln in data.strip().split("\n") if ln.strip()]
            elif isinstance(data, list):
                lines = [str(ln) for ln in data if str(ln).strip()]
            else:
                continue
            if not lines:
                continue
            keep = self._truncate_lines(lines, 10)
            details.append(f"  {field}:")
            details.extend(f"    {ln}" for ln in keep)

        if "invocation" in rd:
            args = rd["invocation"].get("module_args", {})
            if isinstance(args, dict) and args:
                bits = [f"{k}={v}" for k, v in args.items()
                        if k != "_ansible_check_mode" and v is not None][:6]
                if bits:
                    details.append(f"  Args: {' '.join(bits)}")

        # Not when the result carries `exception`, placeholder included: ansible-core 2.19 and later
        # always send one for a failed task, and its lines used to count here, so the dump never
        # printed for a failure and now would for every one that has little else to say.
        if len(details) <= 2 and "exception" not in rd:
            try:
                shown_fields = {key: value for key, value in rd.items() if key != "exception"}
                dump = yaml.dump(shown_fields, default_flow_style=False, sort_keys=False)
                if dump.strip():
                    snippet = dump[:500] + ("..." if len(dump) > 500 else "")
                    details.append(f"  Full result: {snippet}")
            except Exception:
                pass

        return details
