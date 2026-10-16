# Extracts package names from role tasks that use a given module, together with which
# distributions the task actually applies to.
#
# Buffers a whole task before deciding anything, because the when clause that says which
# distribution a task targets usually appears after the package list. A line-by-line version had no
# way to see it, so it reported Ubuntu-only language packs as missing on Debian and had to be thrown
# away.
#
# Applicability is decided with index() rather than regex, deliberately. The first version used
# regex literals containing single quotes, which are awkward to get right in an awk source file and
# silently matched nothing, so every task came out as applying everywhere. index() has no quoting
# pitfalls at all.
#
# Emits: <applies>\t<file>\t<package>, where applies is drawn from debian,ubuntu,fedora.
#
# Usage: awk -v mod="ansible.builtin.apt:" -f extract_tasks.awk <files...>
#
# The second mode reads the role tasks that include setup/ansible/tasks/install_role_packages.yaml,
# which is how a role installs its own packages since 2026-10-15, one package per call. Those tasks
# carry no package module, so the module mode above could never see their names, and every name a
# role writes would have gone unresolved. The list is under role_packages, and the family comes from
# the include's own when, since the module no longer says it: arch, fedora or debian,ubuntu, narrowed
# by ih_base like a module task. An include whose when names no family is labelled none, and
# resolve_role_packages.sh fails on a literal name labelled none rather than resolve it nowhere.
#
# Usage: awk -v mod="install_role_packages.yaml" -v listkey="role_packages" -f extract_tasks.awk <files...>

function flush_task() {
    if (!used_module) { return }

    applies = default_applies
    if (listkey != "name") {
        # Every family the when names, because one include can serve several, `ih_family in
        # ['Debian', 'RedHat', 'Archlinux']` for instance, and labelling it with the first alone left the
        # names unresolved for the others. macos is a label of its own: tier 2 resolves no Homebrew
        # name, and a macOS include is not a list that names no family.
        applies = ""
        if (index(whentext, "'Archlinux'") > 0) { applies = applies ",arch" }
        if (index(whentext, "'RedHat'") > 0) { applies = applies ",fedora" }
        if (index(whentext, "'Debian'") > 0) { applies = applies ",debian,ubuntu" }
        if (index(whentext, "'Darwin'") > 0) { applies = applies ",macos" }
        applies = (applies == "") ? "none" : substr(applies, 2)
        # A list handed to a manager other than the family's own, snap, flatpak or Homebrew, is labelled
        # with that manager, because its names are not apt, dnf or pacman names: the core snap on Arch
        # is not a pacman package called core.
        if (manager != "" && manager != "apt" && manager != "dnf" && manager != "pacman") {
            applies = manager
        }
    }
    if (index(applies, "debian") == 0) {
        # Narrowing to Debian or Ubuntu only means something for a task that applies to them.
    } else if (index(whentext, "distribution") > 0) {
        if (index(whentext, "!=") > 0 && index(whentext, "Ubuntu") > 0) {
            applies = "debian"
        } else if (index(whentext, "Ubuntu") > 0) {
            applies = "ubuntu"
        } else if (index(whentext, "Debian") > 0) {
            applies = "debian"
        }
    } else if (index(whentext, "ih_base") > 0) {
        # The derived facts replaced Ansible's own distribution fact across this repository, because
        # os_family answers with the distribution's own name on any derivative its table has never
        # heard of. This branch was missing afterwards, so a task gated `ih_base == 'ubuntu'` kept the
        # default label of debian,ubuntu and Debian was then checked for four Ubuntu language packs
        # that never apply to it. Four false failures, which is worse than none: a check that cries
        # wolf gets ignored, and this one guards names that really do disappear.
        if (index(whentext, "!=") > 0 && index(whentext, "ubuntu") > 0) {
            applies = "debian"
        } else if (index(whentext, "ubuntu") > 0) {
            applies = "ubuntu"
        }
    }

    for (i = 1; i <= npkgs; i++) {
        print applies "\t" taskfile "\t" pkgs[i]
    }
}

function reset_task() {
    used_module = 0; inname = 0; inwhen = 0; npkgs = 0; whentext = ""; manager = ""
    delete pkgs
}

BEGIN {
    if (index(mod, "dnf") > 0) { default_applies = "fedora" } else { default_applies = "debian,ubuntu" }
    if (listkey == "") { listkey = "name" }
    reset_task()
}

# A task boundary is any list item that starts a task, at any indentation. Matching only column zero
# was wrong: dynamic_install.yaml wraps every task inside a block, so its tasks are indented and the
# boundary never fired, which left used_module set across task boundaries and attributed the flatpak
# remote name "flathub" to pacman, apt and dnf alike.
/^[[:space:]]*-[[:space:]]+name:/ { flush_task(); reset_task(); taskfile = FILENAME }

# A module key. If it is the one we want, start collecting. If it is a different module, stop
# collecting names, though the task's when clause still applies to anything already collected.
/^[[:space:]]*(ansible\.builtin\.|ansible\.windows\.|community\.[a-z]+\.|chocolatey\.|kewlfft\.)/ {
    inwhen = 0
    if (index($0, mod) > 0) { used_module = 1; inname = 0; taskfile = FILENAME; next }
    inname = 0
    next
}

# The include names the task file on its file: line, not on the module line, so in the second mode any
# line naming it starts collecting.
listkey != "name" && index($0, mod) > 0 { used_module = 1; inname = 0; taskfile = FILENAME; next }

/^[[:space:]]*role_packages_manager:/ {
    manager = $0
    sub(/^[[:space:]]*role_packages_manager:[[:space:]]*/, "", manager)
    gsub(/["\047[:space:]]/, "", manager)
    inname = 0
    next
}

/^[[:space:]]*when:/ { inwhen = 1; inname = 0; whentext = whentext " " $0; next }
inwhen && /^[[:space:]]*-[[:space:]]/ { whentext = whentext " " $0; next }
inwhen && /^[[:space:]]*[a-z_]+:/ { inwhen = 0 }

used_module && $0 ~ ("^[[:space:]]*" listkey ":[[:space:]]*[^[:space:]]") {
    line = $0
    sub("^[[:space:]]*" listkey ":[[:space:]]*", "", line)
    sub(/[[:space:]]+#.*$/, "", line)
    # A block scalar indicator, `>-` or `|`, is not a name: the value is the template on the lines
    # below it, as the software installer's pacman list is since 2026-10-15, and it was read as a
    # package called ">-". It is recorded as the template it is, so it is reported as one not checked.
    if (line ~ /^[|>][-+0-9]*$/) {
        pkgs[++npkgs] = "{{ " listkey " block scalar }}"
        next
    }
    gsub(/["]/, "", line)
    gsub(/[\047]/, "", line)
    # A flow sequence, `role_packages: [snapd]`, which the single-package includes use: every entry is
    # a name, and the brackets are not part of any of them.
    if (line ~ /^\[.*\]$/) {
        line = substr(line, 2, length(line) - 2)
        n = split(line, flow, /[[:space:]]*,[[:space:]]*/)
        for (k = 1; k <= n; k++) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", flow[k])
            if (flow[k] != "") { pkgs[++npkgs] = flow[k] }
        }
        next
    }
    pkgs[++npkgs] = line
    next
}
used_module && $0 ~ ("^[[:space:]]*" listkey ":[[:space:]]*$") { inname = 1; next }
inname && /^[[:space:]]*(#|$)/ { next }
inname && /^[[:space:]]*-[[:space:]]/ {
    line = $0
    sub(/^[[:space:]]*-[[:space:]]*/, "", line)
    sub(/[[:space:]]+#.*$/, "", line)
    gsub(/["]/, "", line)
    gsub(/[\047]/, "", line)
    pkgs[++npkgs] = line
    next
}
inname && !/^[[:space:]]*-/ { inname = 0 }

END { flush_task() }
