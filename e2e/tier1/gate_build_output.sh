#!/usr/bin/env bash
#
# Tier 1: a gate image build that fails says which download failed.
#
# Sweep run 39850886667 lost three stage 2 cells to `RUN bash e2e/gate/provision.sh tools` ending with
# `exit code: 22`, which is curl -f answering an HTTP status of 400 or more, and nobody could tell which
# of the two downloads in that step it was. e2e/lib/gate.sh built the image with `docker build -q`,
# which drops the output of every RUN step, and fetch_verified in e2e/gate/provision.sh let curl end
# the step without naming the address.
#
# Three things are asserted. The gate build in e2e/lib/gate.sh is not quiet and asks for plain
# progress, so every step's own lines reach the log. Its failure branch prints the curl and provision
# lines before the tail, so a long build cannot push them out of the window. And fetch_verified, run
# against a fake curl that fails with 22, returns 1, names the address and the status, removes the
# partial file and asked curl to retry every error.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

GATE_SH="${REPO_ROOT}/e2e/lib/gate.sh"
PROVISION_SH="${REPO_ROOT}/e2e/gate/provision.sh"
COMMON_SH="${REPO_ROOT}/e2e/lib/common.sh"

info "Tier 1: a failed gate image build names the download that failed"

gate_build_body="$(sed -n '/^gate_build() {/,/^}/p' "${GATE_SH}")"
build_calls="$(printf '%s\n' "${gate_build_body}" | sed -e ':join' -e '/\\$/{N;s/\\\n//;b join' -e '}' | grep -E 'docker build' | tr -s ' ' || true)"

if [[ -z "${build_calls}" ]]; then
    fail "gate_build in e2e/lib/gate.sh calls docker build" "no docker build found in gate_build, so nothing below means anything"
else
    if grep -qE '(^|[[:space:]])(-q|--quiet)([[:space:]=]|$)' <<<"${build_calls}"; then
        fail "the gate image build is not quiet" "gate_build calls docker build with -q or --quiet, which drops every RUN step's output: ${build_calls}"
    else
        pass "the gate image build is not quiet"
    fi
    if grep -qE -- '--progress[= ]plain' <<<"${build_calls}"; then
        pass "the gate image build asks for plain progress"
    else
        fail "the gate image build asks for plain progress" "gate_build calls docker build without --progress=plain: ${build_calls}"
    fi
fi

if grep -E 'grep .*curl:.*provision:|grep .*provision:.*curl:' <<<"${gate_build_body}" >/dev/null; then
    pass "a failed gate build prints the curl and provision lines before the tail"
else
    fail "a failed gate build prints the curl and provision lines before the tail" "gate_build has no grep for curl: and provision: lines, so a tail window can miss the failing step"
fi

work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT
mkdir -p "${work}/bin"
cat >"${work}/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"${FAKE_CURL_ARGS}"
while [[ $# -gt 0 ]]; do
    if [[ "$1" == -o ]]; then
        printf 'partial' >"$2"
        shift
    fi
    shift
done
exit 22
EOF
chmod +x "${work}/bin/curl"

resolved="$(PATH="${work}/bin:${PATH}" bash -c 'command -v curl')"
if [[ "${resolved}" != "${work}/bin/curl" ]]; then
    fail "the fake curl resolves before fetch_verified runs" "curl resolved to [${resolved}], so nothing was run"
    finish "gate build output"
fi
pass "the fake curl resolves before fetch_verified runs"

url="https://downloads.example.invalid/pester.nupkg"
destination="${work}/download"
fetch_status=0
FAKE_CURL_ARGS="${work}/curl_args" PATH="${work}/bin:${PATH}" \
    bash -c 'set -euo pipefail
             source "$1"
             eval "$(sed -n "/^fetch_verified() {/,/^}/p" "$2")"
             fetch_verified "$3" 0000000000000000000000000000000000000000000000000000000000000000 "$4"' \
        _ "${COMMON_SH}" "${PROVISION_SH}" "${url}" "${destination}" >"${work}/stdout" 2>"${work}/stderr" \
    || fetch_status=$?

assert_eq "fetch_verified returns 1 when curl fails" 1 "${fetch_status}"
wanted="provision: downloading ${url} failed, curl exited 22"
if grep -qxF "${wanted}" "${work}/stderr"; then
    pass "fetch_verified names the address and curl's status"
else
    fail "fetch_verified names the address and curl's status" "expected the line [${wanted}] on stderr, got [$(tr '\n' ' ' <"${work}/stderr")]"
fi
if [[ -e "${destination}" ]]; then
    fail "fetch_verified removes the partial download" "${destination} is still there after curl failed"
else
    pass "fetch_verified removes the partial download"
fi
if grep -qxF -- '--retry-all-errors' "${work}/curl_args" 2>/dev/null; then
    pass "fetch_verified asks curl to retry every error"
else
    fail "fetch_verified asks curl to retry every error" "curl was called with [$(tr '\n' ' ' <"${work}/curl_args" 2>/dev/null)]"
fi

finish "gate build output"
