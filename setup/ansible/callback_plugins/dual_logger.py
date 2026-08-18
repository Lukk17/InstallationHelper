#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Installation Helper — dual-logger callback plugin

Writes four log files in the invoking user's home directory:
    installation_full.log      everything (verbose post-mortem)
    installation_errors.log    only FAILED / fatal / unreachable
    installation_warnings.log  only WARNING-level entries
    installation_skipped.log   only skipped items (per-item disposition)

Console output is condensed: one fixed-width status line per task with a
duration suffix. Long stdout/stderr blocks (license dumps, multi-page
installer chatter) are truncated to STDOUT_TRUNCATE_LINES before being
written anywhere.

The end-of-run summary is appended to installation_full.log so that
operators can `tail` one file and see grouped Installed / Already-present /
Skipped / Failed sections.
"""

import datetime
import os
import pwd
import re
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
    "Install APT packages (batched":          "/var/log/installation-apt-batch.log",
    "Install Flatpak packages (Debian":       "/var/log/installation-flatpak-batch.log",
    "Full system upgrade and autoremove (Debian, via raw)": "/var/log/installation-apt-upgrade.log",
    # virtualization_config Debian apt installs (QEMU/KVM, virt-manager, spice-vdagent)
    "Install QEMU/KVM and virt-manager packages (Debian)": "/var/log/installation-virt-apt.log",
    "Install spice-vdagent (Debian guest)":   "/var/log/installation-virt-apt.log",
    # Docker CE on Debian
    "Install Docker CE (Debian)":             "/var/log/installation-docker-apt.log",
    # Claude Desktop .deb (Debian)
    "Install Claude Desktop .deb (Linux Debian)": "/var/log/installation-claude-desktop-apt.log",
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
        - Truncates very long stdout/stderr blocks per task.
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
    # role adds it to ~/.bashrc / ~/.zshrc so interactive shells are fine.
    "Pub installs executables into $HOME/.pub-cache/bin, which is not on your path",
    # pacman -Sc cleans cached download tempfiles that may already be gone.
    # The error is harmless — the actual cache cleanup succeeded.
    "could not open file /var/cache/pacman/pkg/download-",
    # The two interactive prompts pacman -Sc shows despite --noconfirm in
    # recent versions. Pacman proceeds with the default (Y) anyway.
    "Do you want to remove all other packages from cache?",
    "Do you want to remove unused repositories?",
]
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
    'sdk_manager':         ['install_dart', 'install_flutter', 'install_android_sdk',
                            'install_nodejs', 'install_python', 'install_java',
                            'install_maven', 'install_gradle'],
    'ai_tools':            ['install_claude_code', 'install_claude_desktop',
                            'install_lm_studio', 'install_stable_diffusion',
                            'install_opencode', 'install_openspec',
                            'install_bruno_cli'],
    'software_installer':  [],   # mapped per-software via the toggle key itself
    'virtualization_config': ['install_virt_manager', 'install_docker'],
    'linux_security':      ['install_lynis', 'install_chkrootkit', 'install_clamav'],
    'waydroid':            ['install_waydroid'],
    'jetbrains_toolbox':   ['install_jetbrains_toolbox'],
}

_TOGGLE_REGEX = re.compile(r'((?:install|configure|setup|enabl|set|use|allow)_[\w_]+)')


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
        """Return True if a captured stdout line is noise that should be dropped."""
        if not line:
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
        if len(lines) <= limit:
            return lines
        return lines[: limit - 1] + [f"... [truncated, {len(lines) - limit + 1} more lines]"]

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

    def _extract_skipped_toggles(self, result) -> List[str]:
        """Best-effort extraction of which `install_*` / `setup_*` toggle caused a skip.

        Only returns toggles when we can prove the skip was due to that toggle.
        Reads the actual `false_condition` Ansible records, plus the
        `skipped_reason` text. Never falls back to ROLE_TOGGLE_MAPPING — that
        was a heuristic that mis-attributed every OS-conditional skip in a role
        to the role's "owning" toggle (e.g. labelling a `Download Nerd Fonts
        (macOS)` skip on Debian as `setup_zsh=false`, which is wrong).
        """
        try:
            rd = result._result if hasattr(result, "_result") else {}
        except (AttributeError, TypeError):
            rd = {}
        reason = rd.get("skipped_reason", "") or rd.get("skip_reason", "")
        cond = rd.get("false_condition", "") or ""

        # If the false condition obviously checks os_family / system / distro /
        # architecture, this is an OS-mismatch skip, NOT a toggle skip.
        if cond and re.search(r"os_family|ansible_system|distribution|architecture|virtualization_role", cond):
            return []

        # Prefer toggle names actually mentioned in the false_condition.
        toggles = _TOGGLE_REGEX.findall(cond) if cond else []
        if toggles:
            return toggles
        toggles = _TOGGLE_REGEX.findall(reason) if reason else []
        if toggles:
            return toggles
        return []

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

    def _render_message(self, blob, level: str) -> None:
        """Display and log a debug task's `msg`, whatever shape it arrived in.

        A debug msg is a string, a list of strings, or a mapping, and the playbook uses the first
        two. The level is taken from the text rather than from the task, because a debug task is
        always ok as far as Ansible is concerned while its message is often the only record that
        something was lost. A message opening with [ERROR] therefore reaches installation_errors.log
        and one opening with [WARN], or matching the same keywords stderr is judged by, reaches
        installation_warnings.log.
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
        for ln in self._truncate_lines(lines, STDOUT_TRUNCATE_LINES):
            stripped = ln.strip()
            if stripped.startswith("[ERROR]") or stripped.startswith("[FATAL]"):
                line_lvl = "ERROR"
            elif stripped.startswith("[WARN]") or WARNING_KEYWORDS.search(ln):
                line_lvl = "WARNING"
            else:
                line_lvl = level
            self._display.display(f"  {ln}")
            self._write_log(f"  {ln}", line_lvl)

    def _display_and_log(self, msg: str, level: str = "INFO",
                         include_output: bool = False, result=None) -> None:
        console_msg = f"[{self._ts()}] {msg}"
        self._display.display(console_msg)
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
            task_action = getattr(getattr(result, "_task", None), "action", "") or ""
            if task_action.split(".")[-1] == "debug":
                self._render_message(rd.get("msg"), level)
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
                    self._display.display(f"  {ln}")
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
                self._display.display(f"  [warning] {w_text}")
                self._write_log(f"  [warning] {w_text}", "WARNING")
            for d in rd.get("deprecations") or []:
                d_text = d.get("msg", str(d)) if isinstance(d, dict) else str(d)
                if self._should_skip_line(f"  [deprecation] {d_text}"):
                    continue
                if d_text in self._seen_warnings:
                    continue
                self._seen_warnings.add(d_text)
                self._display.display(f"  [deprecation] {d_text}")
                self._write_log(f"  [deprecation] {d_text}", "WARNING")

    def _emit_phase_separator(self, role: str) -> None:
        bar = "=" * 70
        msg = f"\n{bar}\n  PHASE: {role}\n{bar}"
        self._display.display(msg)
        if self.full_log:
            try: self.full_log.write(f"\n{bar}\n[{self._ts()}]   PHASE: {role}\n{bar}\n\n"); self.full_log.flush()
            except (IOError, OSError): pass

    def _flush_pending(self) -> None:
        """Emit any queued PHASE banner and TASK header. Called from result
        handlers right before they log their own line — so phases / tasks
        that are entirely skipped (e.g. every Fedora task while on Debian)
        never produce visible output."""
        if self._pending_phase is not None:
            self._emit_phase_separator(self._pending_phase)
            self._pending_phase = None
        if self._pending_task is not None:
            self._display_and_log(f"TASK [{self._pending_task}]", "INFO")
            self._pending_task = None

    # ------------------------------------------------------------------
    # Skip categorisation
    # ------------------------------------------------------------------
    def _categorise_skip(self, result, item_key: str) -> str:
        """Return a short human-readable reason for a per-item skip."""
        try:
            task_name = result._task.get_name() if hasattr(result, "_task") else ""
        except (AttributeError, TypeError):
            task_name = ""
        rd = result._result if hasattr(result, "_result") else {}
        skip_reason = rd.get("skipped_reason", "") or rd.get("skip_reason", "")
        false_cond = rd.get("false_condition", "") or ""

        # The build-list task per-item skip means the install_<key> toggle is false.
        if BUILD_LIST_TASK_MARKER in task_name:
            return f"toggle disabled (install_{item_key}=false)"

        # Inspect the recorded false_condition first — it's authoritative.
        if false_cond:
            if re.search(r"os_family|ansible_system|distribution|architecture|virtualization_role", false_cond):
                return "not for this OS"
            toggle_match = _TOGGLE_REGEX.search(false_cond)
            if toggle_match:
                return f"toggle disabled ({toggle_match.group(1)}=false)"

        toggles = self._extract_skipped_toggles(result)
        if toggles:
            return "toggle disabled: " + ", ".join(f"{t}=false" for t in toggles)

        # Last-resort: task-name heuristic for OS-manager tasks.
        if any(k in task_name for k in OS_MANAGER_KEYWORDS):
            return "not for this OS"

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
                self._display.display(line)
            except (IOError, OSError):
                pass

    def _emit_running_header_once(self) -> None:
        if self._heartbeat_header_emitted:
            return
        self._emit_progress(f"  ⏳ running: {self._heartbeat_task_name}")
        self._heartbeat_header_emitted = True
        self._heartbeat_idle_emitted_at = time.monotonic()

    def _heartbeat_loop(self) -> None:
        assert self._heartbeat_stop is not None
        while not self._heartbeat_stop.wait(self._heartbeat_tick):
            now = time.monotonic()
            elapsed = int(now - self._heartbeat_task_started)
            m, s = divmod(elapsed, 60)

            last_line = self._read_last_log_line()
            if last_line and last_line != self._heartbeat_last_line:
                self._emit_running_header_once()
                self._emit_progress(f"  ↳ [{m:02d}m{s:02d}s] {last_line}")
                self._heartbeat_last_line = last_line
                self._heartbeat_idle_emitted_at = now
                continue

            if not self._heartbeat_header_emitted and elapsed >= 2:
                self._emit_running_header_once()
                continue

            if self._heartbeat_header_emitted and (now - self._heartbeat_idle_emitted_at) >= self._heartbeat_idle_ping:
                self._emit_progress(f"  ↳ [{m:02d}m{s:02d}s] still working… (log unchanged)")
                self._heartbeat_idle_emitted_at = now

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

    # ------------------------------------------------------------------
    # Ansible callback hooks
    # ------------------------------------------------------------------
    def v2_playbook_on_start(self, playbook) -> None:
        self._open_logs()
        name = playbook._entries[0].get_name() if playbook._entries else "unknown"
        self._display_and_log(f"PLAY [{name}]", "INFO")

    def v2_playbook_on_play_start(self, play) -> None:
        # Stop any heartbeat from the prior play before the next task starts.
        self._stop_heartbeat()
        self._display_and_log(f"PLAY [{play.get_name()}]", "INFO")

    def v2_playbook_on_task_start(self, task, is_conditional: bool = False) -> None:
        name = task.get_name()
        self._task_start_ts = datetime.datetime.now()
        self._start_heartbeat(name)

        # Buffer phase + task headers; emit lazily on first non-OS-skip result.
        role = self._extract_task_role(name)
        if role and role != self._current_role:
            self._pending_phase = role
            self._current_role = role
        self._pending_task = name

    def v2_playbook_on_handler_task_start(self, task) -> None:
        self._task_start_ts = datetime.datetime.now()
        self._start_heartbeat(task.get_name())
        self._pending_task = f"HANDLER: {task.get_name()}"

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
                              include_output=True, result=result)
        # Batch installers (apt/dnf/pacman/flatpak with name: list) don't fire
        # per-item events. Record the task-level disposition so the summary can
        # show which managers actually changed something.
        task_name = result._task.get_name() if hasattr(result, "_task") else ""
        if any(p in task_name for p in (
            "Install APT packages",
            "Install DNF packages",
            "Install Pacman packages",
            "Install Flatpak packages",
            "Install Homebrew packages",
            "Install Homebrew Cask packages",
            "Install Chocolatey packages",
            "Install Docker CE",
            "Install Docker (Arch)",
            "Install QEMU/KVM",
        )):
            role = self._extract_task_role(task_name) or "batch"
            entry = {"name": task_name.split(' : ', 1)[-1], "manager": role}
            (self.installed if changed else self.unchanged).append(entry)

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
        for detail in self._extract_error_details(result):
            self._display_and_log(detail, level)
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
        reason = self._categorise_skip(result, item_key=task_name)
        # Don't log "not for this OS" task-level skips — drop the buffered
        # TASK header AND the pending PHASE banner if this was the role's
        # first task. Tasks/roles entirely composed of OS-mismatch skips
        # never produce any output.
        if reason == "not for this OS":
            self._pending_task = None
            self._pending_phase = None
            return
        self._flush_pending()
        self._display_and_log(f"skipping: [{host}] {task_name} [{reason}]", "INFO")

    def v2_runner_on_unreachable(self, result) -> None:
        self._stop_heartbeat()
        self._flush_pending()
        host = result._host.get_name()
        task_name = result._task.get_name() if hasattr(result, "_task") else "unknown"
        dur = self._task_duration()
        prefix = f"{dur} " if dur else ""
        self._display_and_log(f"{prefix}unreachable: [{host}] TASK: {task_name}", "ERROR")

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
        tolerated = isinstance(rc, int) and rc != 0

        if tolerated:
            status = "TOLERATED"
            level = "WARNING"
        elif changed:
            status = "INSTALLED"
            level = "INFO"
        else:
            status = "present"
            level = "INFO"

        suffix = ""
        if tolerated:
            suffix = f" -- rc {rc}" + (f", {self._informative_line(result._result)}"
                                       if self._informative_line(result._result) else "")
        self._display_and_log(f"{status:>10}: [{host}] {display}{suffix}", level)
        # End-of-run bucket — exclude enumeration tasks so they don't pollute
        # the "ALREADY PRESENT" count with items that were merely listed.
        task_name = result._task.get_name() if hasattr(result, "_task") else ""
        if any(m in task_name for m in ENUMERATION_TASK_MARKERS):
            return
        if not ("Install" in task_name or "Download" in task_name or "Add " in task_name):
            return
        role = self._extract_task_role(task_name) or ""
        manager = ""
        if isinstance(item, dict):
            manager = (item.get("value", {}) or {}).get("manager", "")
        if not manager and role:
            manager = role
        entry = {"name": item["key"] if isinstance(item, dict) and "key" in item else display,
                 "manager": manager or "other"}
        if tolerated:
            # Its own bucket, so the summary never counts a failed item as one that was already there.
            entry["reason"] = f"rc {rc}"
            self.tolerated.append(entry)
        else:
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
        for detail in self._extract_error_details(result):
            self._display_and_log(detail, level)
        item_key = item.get("key", display) if isinstance(item, dict) else display
        entry = {"task": task_name, "name": item_key, "error": short}
        (self.tolerated if tolerated else self.failed).append(entry)

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
        is_installer_task = any(m in task_name for m in ("Install", "Download", "Add "))
        qualified = f"{role} → {item_key}" if role else item_key

        # Real skip — flush the pending TASK header / PHASE banner.
        self._flush_pending()
        self._display_and_log(f"{'skipped':>10}: [{host}] {qualified} [{reason}]", "INFO")
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
        self._display_and_log(f"included: {included_file._filename}", "INFO")

    def v2_playbook_on_import_for_host(self, result, imported_file: str) -> None:
        host = result._host.get_name()
        self._display_and_log(f"imported: {imported_file} for host {host}", "INFO")

    def v2_playbook_on_not_import_for_host(self, result, missing_file: str) -> None:
        host = result._host.get_name()
        self._display_and_log(f"NOT imported: {missing_file} for host {host}", "WARNING")

    def v2_playbook_on_no_hosts_matched(self) -> None:
        self._display_and_log("no hosts matched", "WARNING")

    def v2_playbook_on_no_hosts_remaining(self) -> None:
        self._display_and_log("NO MORE HOSTS LEFT", "ERROR")

    def v2_playbook_on_notify(self, handler, host) -> None:
        self._display_and_log(f"NOTIFIED HANDLER {handler} for host {host}", "INFO")

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
            by_manager.setdefault(mgr, []).append(it["name"])
        for mgr in sorted(by_manager.keys()):
            names = sorted(set(by_manager[mgr]))
            self._display_and_log(f"  {mgr}: {', '.join(names)}", "INFO")

    def _emit_skipped_summary(self) -> None:
        if not self.skipped_by_reason:
            return
        self._display_and_log("", "INFO")
        total = sum(len(v) for v in self.skipped_by_reason.values())
        self._display_and_log(f"═══ SKIPPED ({total}) ═══", "INFO")
        for reason, names in sorted(self.skipped_by_reason.items()):
            unique = sorted(set(names))
            self._display_and_log(f"  [{reason}] ({len(unique)})", "INFO")
            self._display_and_log(f"    {', '.join(unique)}", "INFO")

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
    def _extract_error_details(self, result) -> List[str]:
        details: List[str] = []
        rd = result._result if hasattr(result, "_result") else {}

        if rd.get("exception"):
            exc_lines = str(rd["exception"]).strip().split("\n")
            keep = exc_lines[-15:] if len(exc_lines) > 15 else exc_lines
            details.append(f"  Exception ({'last 15 lines' if len(exc_lines) > 15 else 'full'}):")
            details.extend(f"    {ln}" for ln in keep if ln.strip())

        if "msg" in rd:
            details.append(f"  Error: {rd['msg']}")
        elif rd.get("stderr"):
            details.append(f"  stderr: {rd['stderr']}")

        for field in ("stdout", "stderr", "stdout_lines", "stderr_lines"):
            data = rd.get(field)
            if not data:
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

        if len(details) <= 2:
            try:
                dump = yaml.dump(rd, default_flow_style=False, sort_keys=False)
                if dump.strip():
                    snippet = dump[:500] + ("..." if len(dump) > 500 else "")
                    details.append(f"  Full result: {snippet}")
            except Exception:
                pass

        return details
