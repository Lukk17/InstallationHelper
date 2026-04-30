# dependency-check-system

## Context
The playbook must check that dependencies are installed BEFORE running tasks that need them.

## Problem
- curl not installed before Antigravity key download
- Flatpak not installed before flatpak packages
- Java not installed before tools that need JVM
- SDKMAN not installed before Gradle installation
- Docker not installed before virtualization_config

## Solution
Add dependency checks at beginning of each task:

### For Debian/Ubuntu - curl dependency
```yaml
- name: Ensure curl is installed
  apt:
    name: curl
    state: present
  become: yes
```

### For Flatpak packages
```yaml
- name: Check flatpak is installed
  command: flatpak --version
  register: flatpak_check
  failed_when: false
  changed_when: false
  
- name: Install flatpak if not present
  dnf:
    name: flatpak
    state: present
  when: flatpak_check.rc != 0
```

### For virtualization_config role
```yaml
- name: Check docker is running
  command: systemctl is-active docker
  register: docker_check
  failed_when: false
  changed_when: false
  
- name: Fail if docker not installed
  fail:
    msg: "Docker must be installed before running virtualization_config"
  when: docker_check.rc != 0
```

## Implementation
1. Add pre-task checks in site.yaml for each role2. Add inline dependency checks in role tasks3. Use failed_when/changed_when patterns

## References
- Ansible documentation on register and failed_when