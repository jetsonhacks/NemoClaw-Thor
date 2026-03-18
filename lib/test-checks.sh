#!/usr/bin/env bash
# test-checks.sh — Validate lib/checks.sh functions
#
# Run this on the Thor to confirm checks.sh behaves correctly before
# building check-prerequisites.sh and install.sh on top of it.
#
# Usage:
#   bash lib/test-checks.sh
#
# Output: each test prints PASS, FAIL, or SKIP with a description.
# Exit code: 0 if all non-skipped tests pass, 1 if any fail.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/checks.sh"

# ── Test framework ─────────────────────────────────────────────────────────────

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# expect_return <description> <expected_return> <function> [args...]
# Calls <function> [args...], checks its return code matches <expected_return>.
expect_return() {
    local description="$1"
    local expected="$2"
    shift 2

    TESTS_RUN=$((TESTS_RUN + 1))

    local actual
    local output
    output=$("$@" 2>&1) && actual=0 || actual=$?

    if [[ "${actual}" -eq "${expected}" ]]; then
        echo "  PASS  ${description}"
        echo "        (returned ${actual} as expected)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "  FAIL  ${description}"
        echo "        (expected return ${expected}, got ${actual})"
        echo "        output: ${output}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

skip() {
    local description="$1"
    local reason="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    echo "  SKIP  ${description}"
    echo "        (${reason})"
}

section() {
    echo ""
    echo "── $* ──"
}

# ── Guard: direct execution prevention ────────────────────────────────────────

section "Guard against direct execution"
if grep -q 'BASH_SOURCE\[0\].*==.*\${0}' "${SCRIPT_DIR}/checks.sh"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  PASS  Direct execution guard is present in checks.sh"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL  Direct execution guard is missing from checks.sh"
fi

# ── Output helpers ─────────────────────────────────────────────────────────────

section "Output helper functions exist"
for fn in pass fail warn info header fix; do
    TESTS_RUN=$((TESTS_RUN + 1))
    if declare -f "${fn}" &>/dev/null; then
        echo "  PASS  Function '${fn}' is defined"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "  FAIL  Function '${fn}' is not defined"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
done

section "Output helpers produce output"
for fn in pass fail warn info fix; do
    TESTS_RUN=$((TESTS_RUN + 1))
    output=$("${fn}" "test message" 2>&1)
    if [[ -n "${output}" ]]; then
        echo "  PASS  '${fn} test message' produces output"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "  FAIL  '${fn} test message' produces no output"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
done

# ── OpenShell checks ───────────────────────────────────────────────────────────

section "OpenShell checks"
if command -v openshell &>/dev/null; then
    expect_return "check_openshell_installed passes when openshell is present" \
        0 check_openshell_installed

    TESTS_RUN=$((TESTS_RUN + 1))
    output=$(check_openshell_gateway 2>&1) && gw_ret=0 || gw_ret=$?
    if [[ "${gw_ret}" -eq 0 || "${gw_ret}" -eq 1 ]]; then
        echo "  PASS  check_openshell_gateway returns 0 or 1 (got ${gw_ret})"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "  FAIL  check_openshell_gateway returned unexpected code ${gw_ret}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
else
    skip "check_openshell_installed (pass case)" "openshell not installed in this environment"
    skip "check_openshell_gateway"               "openshell not installed in this environment"
fi

# ── openshell-thor fix checks ──────────────────────────────────────────────────

section "openshell-thor fix: iptable_raw"
if command -v lsmod &>/dev/null; then
    TESTS_RUN=$((TESTS_RUN + 1))
    output=$(check_fix_iptable_raw 2>&1) && ret=0 || ret=$?
    if [[ "${ret}" -eq 0 || "${ret}" -eq 1 ]]; then
        status=$([[ "${ret}" -eq 0 ]] && echo "LOADED" || echo "NOT LOADED")
        echo "  PASS  check_fix_iptable_raw returns valid code (module: ${status})"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "  FAIL  check_fix_iptable_raw returned unexpected code ${ret}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
else
    skip "check_fix_iptable_raw" "lsmod not available"
fi

section "openshell-thor fix: iptables legacy"
if command -v update-alternatives &>/dev/null; then
    TESTS_RUN=$((TESTS_RUN + 1))
    output=$(check_fix_iptables_legacy 2>&1) && ret=0 || ret=$?
    if [[ "${ret}" -eq 0 || "${ret}" -eq 1 ]]; then
        status=$([[ "${ret}" -eq 0 ]] && echo "legacy" || echo "not legacy")
        echo "  PASS  check_fix_iptables_legacy returns valid code (backend: ${status})"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "  FAIL  check_fix_iptables_legacy returned unexpected code ${ret}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
else
    skip "check_fix_iptables_legacy" "update-alternatives not available"
fi

section "openshell-thor fix: br_netfilter"
if command -v lsmod &>/dev/null; then
    TESTS_RUN=$((TESTS_RUN + 1))
    output=$(check_fix_br_netfilter 2>&1) && ret=0 || ret=$?
    if [[ "${ret}" -eq 0 || "${ret}" -eq 1 ]]; then
        status=$([[ "${ret}" -eq 0 ]] && echo "LOADED" || echo "NOT LOADED")
        echo "  PASS  check_fix_br_netfilter returns valid code (module: ${status})"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "  FAIL  check_fix_br_netfilter returned unexpected code ${ret}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
else
    skip "check_fix_br_netfilter" "lsmod not available"
fi

section "openshell-thor fix: Docker IPv6 disabled"
DAEMON_JSON_TEST="/tmp/test-daemon-$$.json"

# Test 1: file absent
TESTS_RUN=$((TESTS_RUN + 1))
rm -f "${DAEMON_JSON_TEST}"
if ! python3 -c "
import json, sys
with open('${DAEMON_JSON_TEST}') as f:
    d = json.load(f)
sys.exit(0 if d.get('ipv6') == False else 1)
" 2>/dev/null; then
    echo "  PASS  JSON parser: absent file correctly fails"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "  FAIL  JSON parser: absent file should fail but passed"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 2: ipv6 explicitly false — should pass
echo '{"ipv6": false}' > "${DAEMON_JSON_TEST}"
TESTS_RUN=$((TESTS_RUN + 1))
if python3 -c "
import json, sys
with open('${DAEMON_JSON_TEST}') as f:
    d = json.load(f)
sys.exit(0 if d.get('ipv6') == False else 1)
" 2>/dev/null; then
    echo "  PASS  JSON parser: ipv6=false is correctly detected"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "  FAIL  JSON parser: ipv6=false was not detected"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 3: ipv6 absent — should fail
echo '{"log-driver": "json-file"}' > "${DAEMON_JSON_TEST}"
TESTS_RUN=$((TESTS_RUN + 1))
if ! python3 -c "
import json, sys
with open('${DAEMON_JSON_TEST}') as f:
    d = json.load(f)
sys.exit(0 if d.get('ipv6') == False else 1)
" 2>/dev/null; then
    echo "  PASS  JSON parser: missing ipv6 key correctly fails"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "  FAIL  JSON parser: missing ipv6 key should fail but passed"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 4: ipv6 true — should fail
echo '{"ipv6": true}' > "${DAEMON_JSON_TEST}"
TESTS_RUN=$((TESTS_RUN + 1))
if ! python3 -c "
import json, sys
with open('${DAEMON_JSON_TEST}') as f:
    d = json.load(f)
sys.exit(0 if d.get('ipv6') == False else 1)
" 2>/dev/null; then
    echo "  PASS  JSON parser: ipv6=true correctly fails"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "  FAIL  JSON parser: ipv6=true should fail but passed"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

rm -f "${DAEMON_JSON_TEST}"

# ── Docker checks ──────────────────────────────────────────────────────────────

section "Docker checks"
if command -v docker &>/dev/null; then
    expect_return "check_docker_installed passes when docker is present" \
        0 check_docker_installed

    TESTS_RUN=$((TESTS_RUN + 1))
    output=$(check_docker_running 2>&1) && ret=0 || ret=$?
    if [[ "${ret}" -eq 0 || "${ret}" -eq 1 ]]; then
        status=$([[ "${ret}" -eq 0 ]] && echo "running" || echo "not running")
        echo "  PASS  check_docker_running returns valid code (daemon: ${status})"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "  FAIL  check_docker_running returned unexpected code ${ret}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    TESTS_RUN=$((TESTS_RUN + 1))
    output=$(check_docker_nvidia_runtime 2>&1) && ret=0 || ret=$?
    if [[ "${ret}" -eq 0 || "${ret}" -eq 1 ]]; then
        status=$([[ "${ret}" -eq 0 ]] && echo "present" || echo "not present")
        echo "  PASS  check_docker_nvidia_runtime returns valid code (runtime: ${status})"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "  FAIL  check_docker_nvidia_runtime returned unexpected code ${ret}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
else
    skip "check_docker_installed"       "docker not available in this environment"
    skip "check_docker_running"         "docker not available in this environment"
    skip "check_docker_nvidia_runtime"  "docker not available in this environment"
fi

# ── Node / nvm checks ──────────────────────────────────────────────────────────

section "nvm check"
TESTS_RUN=$((TESTS_RUN + 1))
output=$(check_nvm_installed 2>&1) && ret=0 || ret=$?
if [[ "${ret}" -eq 0 || "${ret}" -eq 1 ]]; then
    status=$([[ "${ret}" -eq 0 ]] && echo "installed" || echo "not installed")
    echo "  PASS  check_nvm_installed returns valid code (nvm: ${status})"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "  FAIL  check_nvm_installed returned unexpected code ${ret}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

section "Node version check"
if command -v node &>/dev/null; then
    TESTS_RUN=$((TESTS_RUN + 1))
    output=$(check_node_version 2>&1) && ret=0 || ret=$?
    node_ver=$(node --version)
    if [[ "${ret}" -eq 0 || "${ret}" -eq 1 || "${ret}" -eq 2 ]]; then
        echo "  PASS  check_node_version returns valid code for ${node_ver} (returned ${ret})"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "  FAIL  check_node_version returned unexpected code ${ret} for ${node_ver}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    section "Node version routing logic"
    for test_ver in 18 22 24 20; do
        TESTS_RUN=$((TESTS_RUN + 1))
        output=$(
            node() { echo "v${test_ver}.0.0"; }
            export -f node
            check_node_version 2>&1
        ) && ret=0 || ret=$?
        case "${test_ver}" in
            22) expected=0 ;;
            18) expected=1 ;;
            24) expected=1 ;;
            *)  expected=2 ;;
        esac
        if [[ "${ret}" -eq "${expected}" ]]; then
            echo "  PASS  Node v${test_ver} correctly returns ${ret}"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            echo "  FAIL  Node v${test_ver} returned ${ret}, expected ${expected}"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
    done
else
    skip "check_node_version"   "node not available in this environment"
    skip "Node version routing" "node not available in this environment"
fi

# ── Build tools ────────────────────────────────────────────────────────────────

section "Build tools check"
TESTS_RUN=$((TESTS_RUN + 1))
output=$(check_build_tools 2>&1) && ret=0 || ret=$?
if [[ "${ret}" -eq 0 || "${ret}" -eq 1 ]]; then
    status=$([[ "${ret}" -eq 0 ]] && echo "all present" || echo "some missing")
    echo "  PASS  check_build_tools returns valid code (tools: ${status})"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "  FAIL  check_build_tools returned unexpected code ${ret}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# ── HF_TOKEN ───────────────────────────────────────────────────────────────────

section "HF_TOKEN checks"

# Test: token unset returns 1
TESTS_RUN=$((TESTS_RUN + 1))
output=$(HF_TOKEN="" check_hf_token 2>&1) && ret=0 || ret=$?
if [[ "${ret}" -eq 1 ]]; then
    echo "  PASS  check_hf_token returns 1 when HF_TOKEN is empty"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "  FAIL  check_hf_token should return 1 when HF_TOKEN is empty (got ${ret})"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test: token set returns 0
TESTS_RUN=$((TESTS_RUN + 1))
output=$(HF_TOKEN="hf_testTokenValue1234567890abcdef" check_hf_token 2>&1) && ret=0 || ret=$?
if [[ "${ret}" -eq 0 ]]; then
    echo "  PASS  check_hf_token returns 0 when HF_TOKEN is set"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "  FAIL  check_hf_token should return 0 when HF_TOKEN is set (got ${ret})"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test: output does not contain any part of the token value
TESTS_RUN=$((TESTS_RUN + 1))
test_token="hf_SECRETSECRETVALUE9876"
output=$(HF_TOKEN="${test_token}" check_hf_token 2>&1)
if echo "${output}" | grep -q "hf_\|SECRET\|9876"; then
    echo "  FAIL  check_hf_token output contains part of the token value"
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    echo "  PASS  check_hf_token output contains no part of the token value"
    TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# ── Disk space ─────────────────────────────────────────────────────────────────

section "Disk space check"
TESTS_RUN=$((TESTS_RUN + 1))
output=$(check_disk_space 2>&1) && ret=0 || ret=$?
if [[ "${ret}" -eq 0 || "${ret}" -eq 1 ]]; then
    status=$([[ "${ret}" -eq 0 ]] && echo "sufficient" || echo "insufficient")
    echo "  PASS  check_disk_space returns valid code (space: ${status})"
    echo "        ${output}" | head -2
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo "  FAIL  check_disk_space returned unexpected code ${ret}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# ── Connectivity ───────────────────────────────────────────────────────────────

section "Network connectivity checks"
expect_return "check_connectivity_huggingface" 0 check_connectivity_huggingface
expect_return "check_connectivity_github"      0 check_connectivity_github

# ── Summary ────────────────────────────────────────────────────────────────────

echo ""
echo "══════════════════════════════════════════"
echo "  Results: ${TESTS_RUN} tests"
echo "  ${TESTS_PASSED} passed  |  ${TESTS_FAILED} failed  |  ${TESTS_SKIPPED} skipped"
echo "══════════════════════════════════════════"
echo ""

if [[ "${TESTS_FAILED}" -gt 0 ]]; then
    echo "Some tests failed. Review the output above."
    exit 1
else
    echo "All tests passed (or skipped)."
    exit 0
fi