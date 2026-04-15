#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import datetime
import os
import sys
from ansible import constants as C
from ansible.plugins.callback import CallbackBase

DOCUMENTATION = """
    callback: dual_logger
    type: stdout
    short_description: Dual logging to full and issues log files with console output
    description:
        - Logs all output to ~/installation_full.log
        - Logs only warnings and errors to ~/installation_issues.log
        - Both files are overwritten on each run
        - Also displays output to console using _display.display()
        - Fails playbook if cannot write to logs (unless allow_callback_failure is set)
    options:
        allow_callback_failure:
            description: Allow playbook to continue if log file creation fails
            ini:
                - section: defaults
                  key: allow_callback_failure
            env:
                - name: ALLOW_CALLBACK_FAILURE
            default: false
"""


class CallbackModule(CallbackBase):
    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = "stdout"
    CALLBACK_NAME = "dual_logger"

    def __init__(self):
        super(CallbackModule, self).__init__()
        self.full_log_path = os.path.expanduser("~/installation_full.log")
        self.issues_log_path = os.path.expanduser("~/installation_issues.log")
        self.full_log = None
        self.issues_log = None
        self.allow_failure = False
        self._log_initialized = False

    def set_options(self, task_keys=None, var_options=None, direct=None):
        super(CallbackModule, self).set_options(
            task_keys=task_keys, var_options=var_options, direct=direct
        )

        # Check for allow_callback_failure toggle
        env_val = os.environ.get("ALLOW_CALLBACK_FAILURE", "").lower()
        if env_val in ("true", "1", "yes"):
            self.allow_failure = True
        elif var_options and "allow_callback_failure" in var_options:
            self.allow_failure = bool(var_options["allow_callback_failure"])
        else:
            self.allow_failure = self.get_option("allow_callback_failure") or False

    def _open_logs(self):
        """Open log files for writing. Fail playbook if cannot open (unless allowed)."""
        if self._log_initialized:
            return

        try:
            home_dir = os.path.expanduser("~")
            self.full_log_path = os.path.join(home_dir, "installation_full.log")
            self.issues_log_path = os.path.join(home_dir, "installation_issues.log")

            self.full_log = open(self.full_log_path, "w", encoding="utf-8")
            self.issues_log = open(self.issues_log_path, "w", encoding="utf-8")
            self._log_initialized = True

            self.full_log.write("# Ansible Playbook Log - Started\n")
            self.full_log.write(f"# Full Log: {self.full_log_path}\n")
            self.full_log.write(f"# Issues Log: {self.issues_log_path}\n")
            self.full_log.flush()

        except (IOError, OSError, PermissionError) as e:
            error_msg = f"""
FATAL: Cannot write to log files {self.full_log_path} or {self.issues_log_path}
Reason: {str(e)}

To run without file logging, set allow_callback_failure: true in group_vars/all.yaml
or use --extra-vars "allow_callback_failure=true"
"""
            if self.allow_failure:
                sys.stderr.write(f"WARNING: {error_msg}\n")
                sys.stderr.write(
                    "Continuing without file logging (allow_callback_failure=true)\n"
                )
                self.full_log = None
                self.issues_log = None
                self._log_initialized = True
            else:
                sys.stderr.write(error_msg)
                sys.exit(1)

    def _get_timestamp(self):
        """Return current timestamp in HH:MM:SS format."""
        return datetime.datetime.now().strftime("%H:%M:%S")

    def _write_log(self, msg, level="INFO"):
        """Write message to full log, and to issues log if warning/error."""
        if not self._log_initialized:
            self._open_logs()

        timestamp = self._get_timestamp()
        log_msg = f"[{timestamp}] {msg}"

        if self.full_log:
            try:
                self.full_log.write(log_msg + "\n")
                self.full_log.flush()
            except (IOError, OSError) as e:
                pass

        if self.issues_log and level in ("WARNING", "ERROR", "CRITICAL", "FATAL"):
            try:
                self.issues_log.write(log_msg + "\n")
                self.issues_log.flush()
            except (IOError, OSError) as e:
                pass

    def _display_and_log(self, msg, level="INFO", include_output=False, result=None):
        """Display to console and log to file."""
        timestamp = self._get_timestamp()
        # Include timestamp in console output
        console_msg = f"[{timestamp}] {msg}"
        self._display.display(console_msg)
        # Also log to file
        self._write_log(msg, level)

        # Show full output for tasks that produced stdout/stderr
        if include_output and result is not None:
            result_dict = result._result if hasattr(result, "_result") else {}
            # Show stdout if present
            if "stdout" in result_dict and result_dict["stdout"]:
                stdout = result_dict["stdout"]
                if isinstance(stdout, str) and stdout.strip():
                    for line in stdout.strip().split("\n"):
                        if line.strip():
                            self._display.display(f"  {line}")
                            self._write_log(f"  {line}", level)
            # Show stderr if present (usually contains warnings)
            if "stderr" in result_dict and result_dict["stderr"]:
                stderr = result_dict["stderr"]
                if isinstance(stderr, str) and stderr.strip():
                    for line in stderr.strip().split("\n"):
                        if line.strip():
                            self._display.display(f"  {line}")
                            self._write_log(f"  {line}", "WARNING")

    def _extract_item_display(self, item):
        """Extract a clean display string from loop item.
        
        Handles various item formats used in Ansible loops:
        - dict with 'name' key: {'name': 'applications-local'} -> 'applications-local'
        - dict with 'key' key: {'key': '/org/gnome/...'} -> '/org/gnome/...'
        - dict with 'path' key: {'path': '/home/.../applications'} -> 'applications'
        - dict with 'app' + 'mime': {'app': 'default', 'mime': 'app/msword'} -> 'default -> app/msword'
        - simple string: 'file' -> 'file'
        - dict with 'value' key (complex): fallback to full repr
        """
        import os
        import re
        
        if item is None:
            return "unknown"
        
        # Handle simple string or number
        if isinstance(item, str):
            # Trim whitespace (common in toggle-based loops)
            return item.strip()
        if isinstance(item, (int, float)):
            return str(item)
        
        # Handle dict
        if isinstance(item, dict):
            # Priority: name > key > path > app+mime
            if "name" in item and item["name"]:
                return str(item["name"])
            if "key" in item and item["key"]:
                return str(item["key"])
            if "path" in item and item["path"]:
                # Get basename of path
                path = item["path"]
                return os.path.basename(path)
            if "app" in item and "mime" in item:
                return f"{item['app']} -> {item['mime']}"
            if "url" in item and "name" in item:
                return str(item["name"])
            if "option" in item and "value" in item:
                return f"{item['option']}: {item['value']}"
            
            # Fallback: try to get something useful or return repr
            return repr(item)
        
        # Fallback for other types
        return repr(item)

    # Mapping of role names to related toggle names
    ROLE_TOGGLE_MAPPING = {
        # Desktop Environments
        'gnome_setup': ['install_gnome', 'configure_gnome'],
        'kde_plasma_setup': ['install_kde_plasma', 'configure_kde_plasma'],
        
        # Shell & Environment
        'shell_zsh': ['setup_zsh'],
        'env_variables': ['set_custom_env', 'configure_env'],
        
        # System Core
        'system_core': ['install_system_core'],
        'systemd_boot': ['setup_systemd_boot', 'remove_distro_grub'],
        'snapper': ['install_snapper'],
        
        # SDK Managers
        'sdk_manager': [
            'install_dart', 'install_flutter', 'install_android_sdk',
            'install_nodejs', 'install_python', 'install_java', 'install_maven', 'install_gradle'
        ],
        
        # AI Tools
        'ai_tools': [
            'install_claude_code', 'install_claude_desktop', 'install_claude_cowork',
            'install_lm_studio', 'install_stable_diffusion',
            'install_opencode', 'install_openspec'
        ],
        
        # Software Installer
        'software_installer': [],  # Mapped dynamically based on software toggles
        
        # Virtualization
        'virtualization_config': ['install_virt_manager', 'install_docker'],
        
        # Security
        'linux_security': ['install_lynis', 'install_chkrootkit', 'install_clamav'],
        
        # Waydroid
        'waydroid': ['install_waydroid'],
        
        # JetBrains
        'jetbrains_toolbox': ['install_jetbrains_toolbox'],
    }

    def _extract_task_role(self, task_name):
        """Extract role name prefix from task name.
        
        Examples:
        - 'gnome_setup : Create Templates directory' -> 'gnome_setup'
        - 'kde_plasma_setup : Install Konsave via pipx' -> 'kde_plasma_setup'
        - 'shell_zsh : Copy ZSH configuration files' -> 'shell_zsh'
        - 'install_intellij' -> None (no role prefix, just software toggle)
        """
        if not task_name or not isinstance(task_name, str):
            return None
        
        # Pattern: "role_name : task description" or just task description
        if ' : ' in task_name:
            # Extract the part before the colon
            role_part = task_name.split(' : ')[0].strip()
            return role_part
        
        return None

    def _extract_skipped_toggles(self, result):
        """Extract toggle names from skipped result using skipped_reason.
        
        First tries to get toggle names from result._result['skipped_reason'],
        then falls back to task name analysis if not available.
        Returns list of toggles that caused the skip.
        """
        toggles = []
        
        try:
            result_dict = result._result if hasattr(result, "_result") else {}
        except (AttributeError, TypeError):
            result_dict = {}
        
        skipped_reason = result_dict.get("skipped_reason", "")
        
        if skipped_reason:
            import re
            toggle_pattern = re.compile(r'((?:install|configure|setup|enabl|set|use|allow)_[\w_]+)')
            found = toggle_pattern.findall(skipped_reason)
            if found:
                toggles = found
        
        if not toggles:
            try:
                task = result._task
                task_name = task.get_name() if hasattr(task, 'get_name') else str(task)
            except (AttributeError, TypeError):
                task_name = ""
            
            if task_name:
                role_name = self._extract_task_role(task_name)
                
                if role_name and role_name in self.ROLE_TOGGLE_MAPPING:
                    toggles = self.ROLE_TOGGLE_MAPPING[role_name].copy()
                
                if not toggles:
                    import re
                    toggle_match = re.compile(r'((?:install|configure|setup|enabl|set|use|allow)_[\w_]+)')
                    match = toggle_match.search(task_name)
                    if match:
                        toggles = [match.group(1)]
        
        return toggles

    def v2_runner_on_task_start(self, host, task, is_conditional):
        """Log when a task starts - shows user what's being executed."""
        task_name = task.get_name()
        self._display_and_log(f"Starting: [{host}] {task_name}", "INFO")

    def v2_runner_on_ok(self, result):
        host = result._host.get_name()
        self._display_and_log(f"ok: [{host}]", "INFO", include_output=True, result=result)

    def _extract_error_details(self, result):
        """Extract detailed error information from result."""
        error_details = []
        result_dict = result._result if hasattr(result, "_result") else {}

        # Get the main error message
        if "msg" in result_dict:
            error_details.append(f"  Error: {result_dict['msg']}")
        elif "stderr" in result_dict and result_dict["stderr"]:
            error_details.append(f"  stderr: {result_dict['stderr']}")

        # Get stdout if present - show full output if it's short, last lines if long
        if "stdout" in result_dict and result_dict["stdout"]:
            stdout = result_dict["stdout"]
            if isinstance(stdout, str):
                lines = stdout.strip().split("\n")
                if lines:
                    if len(lines) > 10:
                        error_details.append(f"  stdout (last 10 lines):")
                        for line in lines[-10:]:
                            if line.strip():
                                error_details.append(f"    {line}")
                    else:
                        error_details.append(f"  stdout:")
                        for line in lines:
                            if line.strip():
                                error_details.append(f"    {line}")

        # Get stderr_lines for more detail
        if "stderr_lines" in result_dict and result_dict["stderr_lines"]:
            stderr_lines = result_dict["stderr_lines"]
            if stderr_lines:
                if len(stderr_lines) > 10:
                    error_details.append(f"  stderr (last 10 lines):")
                    for line in stderr_lines[-10:]:
                        if line.strip():
                            error_details.append(f"    {line}")
                else:
                    error_details.append(f"  stderr:")
                    for line in stderr_lines:
                        if line.strip():
                            error_details.append(f"    {line}")

        # Get stdout_lines for more detail
        if "stdout_lines" in result_dict and result_dict["stdout_lines"]:
            stdout_lines = result_dict["stdout_lines"]
            if stdout_lines:
                if len(stdout_lines) > 10:
                    error_details.append(f"  stdout_lines (last 10 lines):")
                    for line in stdout_lines[-10:]:
                        if line.strip():
                            error_details.append(f"    {line}")
                else:
                    error_details.append(f"  stdout_lines:")
                    for line in stdout_lines:
                        if line.strip():
                            error_details.append(f"    {line}")

        # Get invocation details
        if "invocation" in result_dict:
            inv = result_dict["invocation"]
            if "module_args" in inv:
                args = inv["module_args"]
                if isinstance(args, dict) and args:
                    cmd_parts = []
                    for k, v in args.items():
                        if k != "_ansible_check_mode" and v is not None:
                            cmd_parts.append(f"{k}={v}")
                    if cmd_parts:
                        error_details.append(f"  Args: {' '.join(cmd_parts[:3])}")

        return error_details

    def v2_runner_on_failed(self, result, ignore_errors=False):
        host = result._host.get_name()
        task_name = result._task.get_name() if hasattr(result, "_task") else "unknown"
        msg = f"fatal: [{host}]: FAILED! => TASK: {task_name}"
        self._display_and_log(msg, "ERROR")

        # Extract and display detailed error information
        error_details = self._extract_error_details(result)
        for detail in error_details:
            self._display_and_log(detail, "ERROR")

    def v2_runner_on_skipped(self, result):
        host = result._host.get_name()
        task_name = result._task.get_name() if hasattr(result, "_task") else ""

        # OS-specific task names to suppress (Arch Linux, Debian, Fedora, macOS, Windows variants)
        os_keywords = ["Arch", "Debian", "Fedora", "macOS", "Darwin", "Windows", "(Debian)", "(Arch)", "(Fedora)", "(Mac)"]

        # Check if this is an OS-specific task being skipped due to different OS
        is_os_skip = any(keyword in task_name for keyword in os_keywords)

        if is_os_skip:
            # Suppress OS-difference skips - don't print
            pass
        else:
            # Show toggle-based skips with clearer format
            result_dict = result._result if hasattr(result, "_result") else {}
            skip_reason = ""

            # If there's a 'skipped_reason' in result, use it
            if "skipped_reason" in result_dict:
                skip_reason = f" - {result_dict['skipped_reason']}"

            # Extract toggles that caused the skip
            toggles = self._extract_skipped_toggles(result)

            # Only show [due: X] if toggles is non-empty, otherwise just skip
            if toggles:
                toggle_msg = f" [due: {','.join(toggles)}]"
                self._display_and_log(f"skipping: [{host}] {task_name}{toggle_msg}{skip_reason}", "INFO")
            else:
                self._display_and_log(f"skipping: [{host}] {task_name}{skip_reason}", "INFO")

    def v2_runner_on_unreachable(self, result):
        host = result._host.get_name()
        task_name = result._task.get_name() if hasattr(result, "_task") else "unknown"
        self._display_and_log(f"unreachable: [{host}] TASK: {task_name}", "ERROR")

    def v2_playbook_on_start(self, playbook):
        self._open_logs()
        if playbook._entries:
            self._display_and_log(f"PLAY [{playbook._entries[0].get_name()}]", "INFO")
        else:
            self._display_and_log("PLAY [unknown]", "INFO")

    def v2_playbook_on_task_start(self, task, is_conditional=False):
        self._display_and_log(f"TASK [{task.get_name()}]", "INFO")

    def v2_playbook_on_handler_task_start(self, task):
        self._display_and_log(f"RUNNING HANDLER [{task.get_name()}]", "INFO")

    def v2_playbook_on_play_start(self, play):
        self._display_and_log(f"PLAY [{play.get_name()}]", "INFO")

    def v2_playbook_on_stats(self, stats):
        hosts = sorted(stats.processed.keys())
        for host in hosts:
            host_stats = stats.summarize(host)
            msg = f"{host}: ok={host_stats['ok']} changed={host_stats['changed']} unreachable={host_stats['unreachable']} failed={host_stats['failures']} skipped={host_stats['skipped']} rescued={host_stats['rescued']} ignored={host_stats['ignored']}"
            self._display_and_log(msg, "INFO")

        if self.full_log:
            self.full_log.close()
        if self.issues_log:
            self.issues_log.close()

    def v2_on_file_diff(self, result):
        if result._result.get("diff"):
            self._display_and_log(f"diff: {result._result['diff']}", "INFO")

    def v2_runner_item_on_ok(self, result):
        host = result._host.get_name()
        item = result._result.get("item", "unknown")
        item_display = self._extract_item_display(item)
        self._display_and_log(f"ok: [{host}] => {item_display}", "INFO")

    def v2_runner_item_on_failed(self, result):
        host = result._host.get_name()
        item = result._result.get("item", "unknown")
        item_display = self._extract_item_display(item)
        task_name = result._task.get_name() if hasattr(result, "_task") else "unknown"
        msg = f"failed: [{host}] => {item_display} TASK: {task_name}"
        self._display_and_log(msg, "ERROR")

        # Extract and display detailed error information
        error_details = self._extract_error_details(result)
        for detail in error_details:
            self._display_and_log(detail, "ERROR")

    def v2_runner_item_on_skipped(self, result):
        host = result._host.get_name()
        item = result._result.get("item", "unknown")
        item_display = self._extract_item_display(item)

        # Extract toggles that caused the skip
        toggles = self._extract_skipped_toggles(result)

        # Only show [due: X] if toggles is non-empty, otherwise just skip
        if toggles:
            toggle_msg = f" [due: {','.join(toggles)}]"
            self._display_and_log(f"skipping: [{host}] => {item_display}{toggle_msg}", "INFO")
        else:
            self._display_and_log(f"skipping: [{host}] => {item_display}", "INFO")

    def v2_playbook_on_include(self, included_file):
        self._display_and_log(f"included: {included_file._filename}", "INFO")

    def v2_playbook_on_import_for_host(self, result, imported_file):
        host = result._host.get_name()
        self._display_and_log(f"imported: {imported_file} for host {host}", "INFO")

    def v2_playbook_on_not_import_for_host(self, result, missing_file):
        host = result._host.get_name()
        self._display_and_log(
            f"NOT imported: {missing_file} for host {host}", "WARNING"
        )

    def v2_playbook_on_no_hosts_matched(self):
        self._display_and_log("no hosts matched", "WARNING")

    def v2_playbook_on_no_hosts_remaining(self):
        self._display_and_log("NO MORE HOSTS LEFT", "ERROR")

    def v2_playbook_on_notify(self, handler, host):
        self._display_and_log(f"NOTIFIED HANDLER {handler} for host {host}", "INFO")
