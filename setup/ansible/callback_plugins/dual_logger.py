#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from ansible.plugins.callback import CallbackBase
from ansible import constants as C
import os
import sys

DOCUMENTATION = '''
    callback: dual_logger
    type: stdout
    short_description: Dual logging to full and issues log files
    description:
        - Logs all output to ~/installation_full.log
        - Logs only warnings and errors to ~/installation_issues.log
        - Both files are overwritten on each run
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
'''

class CallbackModule(CallbackBase):
    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = 'stdout'
    CALLBACK_NAME = 'dual_logger'
    
    def __init__(self):
        super(CallbackModule, self).__init__()
        self.full_log_path = os.path.expanduser('~/installation_full.log')
        self.issues_log_path = os.path.expanduser('~/installation_issues.log')
        self.full_log = None
        self.issues_log = None
        self.allow_failure = False
        
    def set_options(self, task_keys=None, var_options=None, direct=None):
        super(CallbackModule, self).set_options(task_keys=task_keys, var_options=var_options, direct=direct)
        
        # Check for allow_callback_failure toggle
        # Priority: 1. Environment variable, 2. Ansible variable, 3. Default false
        env_val = os.environ.get('ALLOW_CALLBACK_FAILURE', '').lower()
        if env_val in ('true', '1', 'yes'):
            self.allow_failure = True
        elif var_options and 'allow_callback_failure' in var_options:
            self.allow_failure = bool(var_options['allow_callback_failure'])
        else:
            self.allow_failure = self.get_option('allow_callback_failure') or False
    
    def _open_logs(self):
        """Open log files for writing. Fail playbook if cannot open (unless allowed)."""
        try:
            # Open both logs in write mode (truncate/overwrite)
            self.full_log = open(self.full_log_path, 'w', encoding='utf-8')
            self.issues_log = open(self.issues_log_path, 'w', encoding='utf-8')
        except (IOError, OSError, PermissionError) as e:
            error_msg = f"""
FATAL: Cannot write to log files {self.full_log_path} or {self.issues_log_path}
Reason: {str(e)}

To run without file logging, set allow_callback_failure: true in group_vars/all.yaml
or use --extra-vars "allow_callback_failure=true"
"""
            if self.allow_failure:
                # Write to stderr as fallback
                sys.stderr.write(f"WARNING: {error_msg}\n")
                sys.stderr.write("Continuing without file logging (allow_callback_failure=true)\n")
                self.full_log = None
                self.issues_log = None
            else:
                # Fail the playbook
                sys.stderr.write(error_msg)
                sys.exit(1)
    
    def _write_log(self, msg, level='INFO'):
        """Write message to full log, and to issues log if warning/error."""
        if self.full_log is None:
            self._open_logs()
            
        if self.full_log:
            self.full_log.write(msg + '\n')
            self.full_log.flush()
        
        # Write to issues log only for warnings and errors
        if self.issues_log and level in ('WARNING', 'ERROR', 'CRITICAL', 'FATAL'):
            self.issues_log.write(msg + '\n')
            self.issues_log.flush()
    
    def _close_logs(self):
        """Close log files."""
        if self.full_log:
            self.full_log.close()
        if self.issues_log:
            self.issues_log.close()
    
    def v2_runner_on_ok(self, result):
        """Handle successful task."""
        msg = f"ok: [{result._host.get_name()}]"
        if result._result.get('msg'):
            msg += f" => {result._result.get('msg')}"
        self._write_log(msg, 'INFO')
        
    def v2_runner_on_failed(self, result, ignore_errors=False):
        """Handle failed task."""
        msg = f"fatal: [{result._host.get_name()}]: FAILED! => {result._result}"
        self._write_log(msg, 'ERROR')
        
    def v2_runner_on_skipped(self, result):
        """Handle skipped task."""
        msg = f"skipping: [{result._host.get_name()}]"
        self._write_log(msg, 'INFO')
        
    def v2_runner_on_unreachable(self, result):
        """Handle unreachable host."""
        msg = f"unreachable: [{result._host.get_name()}]"
        self._write_log(msg, 'ERROR')
    
    def v2_playbook_on_start(self, playbook):
        """Handle playbook start."""
        self._open_logs()
        msg = f"PLAY [{playbook._entries[0].get_name() if playbook._entries else 'unknown'}]"
        self._write_log(msg, 'INFO')
        
    def v2_playbook_on_task_start(self, task, is_conditional=False):
        """Handle task start."""
        msg = f"TASK [{task.get_name()}]"
        self._write_log(msg, 'INFO')
        
    def v2_playbook_on_handler_task_start(self, task):
        """Handle handler task start."""
        msg = f"RUNNING HANDLER [{task.get_name()}]"
        self._write_log(msg, 'INFO')
    
    def v2_playbook_on_stats(self, stats):
        """Handle playbook stats at end."""
        hosts = sorted(stats.processed.keys())
        for host in hosts:
            host_stats = stats.summarize(host)
            msg = f"{host}: ok={host_stats['ok']} changed={host_stats['changed']} unreachable={host_stats['unreachable']} failed={host_stats['failures']} skipped={host_stats['skipped']} rescued={host_stats['rescued']} ignored={host_stats['ignored']}"
            self._write_log(msg, 'INFO')
        self._close_logs()
    
    def v2_on_file_diff(self, result):
        """Handle file diffs."""
        if result._result.get('diff'):
            msg = f"diff: {result._result['diff']}"
            self._write_log(msg, 'INFO')
    
    def v2_runner_item_on_ok(self, result):
        """Handle loop item success."""
        msg = f"ok: [{result._host.get_name()}] => (item={result._result.get('item', 'unknown')})"
        self._write_log(msg, 'INFO')
    
    def v2_runner_item_on_failed(self, result):
        """Handle loop item failure."""
        msg = f"failed: [{result._host.get_name()}] => (item={result._result.get('item', 'unknown')}) => {result._result}"
        self._write_log(msg, 'ERROR')
    
    def v2_runner_item_on_skipped(self, result):
        """Handle loop item skip."""
        msg = f"skipping: [{result._host.get_name()}] => (item={result._result.get('item', 'unknown')})"
        self._write_log(msg, 'INFO')
    
    def v2_playbook_on_include(self, included_file):
        """Handle included file."""
        msg = f"included: {included_file._filename}"
        self._write_log(msg, 'INFO')
    
    def v2_playbook_on_import_for_host(self, result, imported_file):
        """Handle imported file for host."""
        msg = f"imported: {imported_file} for host {result._host.get_name()}"
        self._write_log(msg, 'INFO')
    
    def v2_playbook_on_not_import_for_host(self, result, missing_file):
        """Handle missing import for host."""
        msg = f"NOT imported: {missing_file} for host {result._host.get_name()}"
        self._write_log(msg, 'WARNING')
    
    def v2_playbook_on_play_start(self, play):
        """Handle play start."""
        msg = f"PLAY [{play.get_name()}]"
        self._write_log(msg, 'INFO')
    
    def v2_playbook_on_no_hosts_matched(self):
        """Handle no hosts matched."""
        msg = "no hosts matched"
        self._write_log(msg, 'WARNING')
    
    def v2_playbook_on_no_hosts_remaining(self):
        """Handle no hosts remaining."""
        msg = "NO MORE HOSTS LEFT"
        self._write_log(msg, 'ERROR')
    
    def v2_playbook_on_notify(self, handler, host):
        """Handle notification."""
        msg = f"NOTIFIED HANDLER {handler} for host {host}"
        self._write_log(msg, 'INFO')
