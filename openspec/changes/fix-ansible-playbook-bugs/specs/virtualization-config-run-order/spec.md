# virtualization-config-run-order

## Context
The `virtualization_config` role requires Docker to be already installed and running. Currently, the role runs before docker installation completes, causing failures.

## Problem
- virtualization_config task fails with "Could not find the requested service docker"
- The task tries to configure libvirt/containers before docker is installed

## Solution
Reorder site.yaml so virtualization_config runs AFTER software_installer (which installs docker):

```
# In site.yaml order:
- import_playbook: roles/software_installer     # Docker installed HERE
- import_playbook: roles/virtualization_config  # Runs AFTER docker
```

## Implementation
1. Ensure docker is installed in software_installer role2. Move virtualization_config import to AFTER software_installer in site.yaml3. Add conditional: only run virtualization_config if docker is installed

## Testing
- Test on Fedora (docker-ce)
- Test on Ubuntu 
- Test on Debian
- Test on Arch Linux

## References
- https://docs.docker.com/engine/install/
- https://libvirt.org/