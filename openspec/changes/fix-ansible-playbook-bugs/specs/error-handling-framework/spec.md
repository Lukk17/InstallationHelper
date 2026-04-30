# error-handling-framework

## Context
The playbook should handle errors gracefully and provide clear messages when failures occur.

## Problem
- Silent failures - playbook continues without indication
- Error messages not helpful for debugging
- No recovery options for optional failures

## Solution

### Pre-task Error Handling
Use `failed_when` and rescue blocks:

```yaml
- name: Task that might fail
  command: some-command
  register: result
  failed_when: result.rc != 0 and 'optional' not in result.stdout

- name: Handle failure
  fail:
    msg: "Error: {{ result.stderr }}"
  when: result.rc != 0
```

### Package Not Found Handling
```yaml
- name: Try package install
  dnf:
    name: "{{ package_name }}"
    state: present
  register: package_install
  failed_when: false
  changed_when: package_install.changed

- name: Report fallback needed
  debug:
    msg: "Package {{ package_name }} not available. Manual install may be required."
  when: package_install.rc != 0
```

### Idempotency
- Use `changed_when: false` for commands
- Check if already configured before applying
- Use `creates:` parameter to skip if exists

## Implementation
1. Add rescue blocks to critical tasks2. Add debug messages for fallback packages
3. Use `changed_when` for command modules

## References
- Ansible error handling: https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_handlers.html#controlling-failures