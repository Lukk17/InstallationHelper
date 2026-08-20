# The Ansible end of the pinned values port. A shim over setup/pinned_values/pinned_values.py and
# nothing else: it resolves no reference, parses no TOML and knows no key names.
#
# A vars plugin rather than a lookup or a filter, because this injects names into the variable space,
# so every `{{ minikube_url }}` in every role and the dispatcher's runtime-built
# `lookup('vars', item.key ~ '_url')` keep working with no callsite edited. See
# docs/pinned_values_adapter_design.md section 3.

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

from ansible.errors import AnsibleError
from ansible.module_utils.common.text.converters import to_native
from ansible.plugins.vars import BaseVarsPlugin
from ansible.utils.unsafe_proxy import wrap_var

DOCUMENTATION = """
    name: pinned_values
    short_description: Pinned versions, download locations and vendor identifiers
    description:
      - Injects every value from setup/pinned_values/pinned_values.toml as a host variable, fully
        resolved, plus the checksum table as C(download_checksums).
      - The file is located from this plugin's own path, never from the playbook's basedir, because
        site.yaml and verify_install.yaml have different basedirs and the pins are the same for both.
    extends_documentation_fragment:
      - vars_plugin_staging
"""

# setup/ansible/vars_plugins/ -> setup/ansible/ -> setup/
CORE = Path(__file__).resolve().parents[2] / "pinned_values" / "pinned_values.py"

CHECKSUMS_VAR = "download_checksums"


def _core():
    """Import the reader by path, so no PYTHONPATH or package layout has to be arranged."""
    module = sys.modules.get("installation_helper_pinned_values")
    if module is not None:
        return module

    spec = importlib.util.spec_from_file_location("installation_helper_pinned_values", CORE)
    if spec is None or spec.loader is None:
        raise AnsibleError(f"cannot load the pinned values reader at {CORE}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class VarsModule(BaseVarsPlugin):
    """Hands every pinned value to every host and group."""

    def get_vars(self, loader, path, entities, cache=True):
        super().get_vars(loader, path, entities)

        core = _core()
        try:
            # The reader caches on the file's modification time, so this is one parse per process
            # however many hosts and groups Ansible asks about.
            values = dict(core.pins())
            values[CHECKSUMS_VAR] = core.checksums()
        except core.PinnedValuesError as exc:
            raise AnsibleError(to_native(exc)) from exc

        # Every value arrives already resolved, so marking it unsafe stops a second templating pass
        # from treating a brace inside a URL as a template.
        return {name: wrap_var(value) for name, value in values.items()}
