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

function flush_task() {
    if (!used_module) { return }

    applies = default_applies
    if (index(whentext, "distribution") > 0) {
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
    used_module = 0; inname = 0; inwhen = 0; npkgs = 0; whentext = ""
    delete pkgs
}

BEGIN {
    if (index(mod, "dnf") > 0) { default_applies = "fedora" } else { default_applies = "debian,ubuntu" }
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

/^[[:space:]]*when:/ { inwhen = 1; inname = 0; whentext = whentext " " $0; next }
inwhen && /^[[:space:]]*-[[:space:]]/ { whentext = whentext " " $0; next }
inwhen && /^[[:space:]]*[a-z_]+:/ { inwhen = 0 }

used_module && /^[[:space:]]*name:[[:space:]]*[^[:space:]]/ {
    line = $0
    sub(/^[[:space:]]*name:[[:space:]]*/, "", line)
    sub(/[[:space:]]+#.*$/, "", line)
    gsub(/["]/, "", line)
    gsub(/[\047]/, "", line)
    pkgs[++npkgs] = line
    next
}
used_module && /^[[:space:]]*name:[[:space:]]*$/ { inname = 1; next }
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
