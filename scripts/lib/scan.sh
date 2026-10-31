# shellcheck shell=bash
# Sourced by the gates that grep the tree. `scan` runs grep with its
# arguments and prints what it matched. grep exits 1 for no match, which is
# an answer, and 2 when it could not read a file or a folder it was given,
# which is not one: a gate that read part of the tree cannot say ok, and
# grep exits 2 even when it matched in the files it did read. So 2 ends the
# gate, with grep's own complaint left on stderr.
#
# Call it alone, as `found=$(scan …)` under `set -e`, so its status is the
# assignment's and stops the script. Inside an `if` or a pipeline its status
# is read as "no match" or thrown away, which is the hole this closes, so
# filter what it found afterwards, from the variable.
scan() {
    local found
    local code=0
    found=$(grep "$@") || code=$?
    if [ "$code" -gt 1 ]; then
        echo "$(basename "$0"): grep could not read everything it was given (exit $code), so this gate read only part of the tree" >&2
        return "$code"
    fi
    printf '%s\n' "$found"
}
