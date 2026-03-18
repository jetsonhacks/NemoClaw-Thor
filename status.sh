#!/usr/bin/env bash
# status.sh — NemoClaw-Thor system health check
#
# Checks the health of all components in the NemoClaw stack:
#   - OpenShell gateway
#   - vLLM inference server
#   - OpenShell sandbox
#   - Inference route configuration
#
# After all checks pass, prints the command to run a manual
# end-to-end inference test from inside the sandbox.
#
# Usage:
#   ./status.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/checks.sh"

# ── Header ─────────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}NemoClaw-Thor System Status${NC}"
echo -e "JetsonHacks — https://github.com/JetsonHacks/NemoClaw-Thor"
echo ""

# ── Tracking ───────────────────────────────────────────────────────────────────

CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNED=0

record() {
    local ret="$1"
    case "${ret}" in
        0) CHECKS_PASSED=$((CHECKS_PASSED + 1)) ;;
        2) CHECKS_WARNED=$((CHECKS_WARNED  + 1)) ;;
        *) CHECKS_FAILED=$((CHECKS_FAILED  + 1)) ;;
    esac
}

# ── OpenShell gateway ──────────────────────────────────────────────────────────

header "OpenShell Gateway"
echo ""

check_openshell_installed && record 0 || record 1

if command -v openshell &>/dev/null; then
    if openshell gateway info &>/dev/null; then
        pass "OpenShell gateway is running"
        record 0
    else
        fail "OpenShell gateway is not running"
        fix "Run: openshell gateway start"
        record 1
    fi
fi

# ── vLLM inference server ──────────────────────────────────────────────────────

header "vLLM Inference Server"
echo ""

vllm_response=$(curl -s --max-time 10 http://localhost:8000/v1/models 2>/dev/null || echo "")

if [[ -z "${vllm_response}" ]]; then
    fail "vLLM server is not reachable at http://localhost:8000"
    info "The inference server is not running or is still starting up."
    fix "Start one in a separate terminal:"
    fix "  ./nemotron3-thor-no-thinking.sh  (Fast — recommended)"
    fix "  ./nemotron3-thor.sh               (Thinking — slower, more accurate)"
    fix "Wait for: \"Application startup complete.\""
    record 1
else
    expected_model="nvidia/nemotron-3-nano-30b-a3b"
    if echo "${vllm_response}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
models = [m['id'] for m in data.get('data', [])]
sys.exit(0 if '${expected_model}' in models else 1)
" 2>/dev/null; then
        pass "vLLM server is running"
        pass "Model serving as: ${expected_model}"
        record 0
        record 0
    else
        actual=$(echo "${vllm_response}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
models = [m['id'] for m in data.get('data', [])]
print(', '.join(models) if models else 'unknown')
" 2>/dev/null || echo "unknown")
        warn "vLLM server is running but serving unexpected model: ${actual}"
        info "NemoClaw expects model: ${expected_model}"
        fix "Check --served-model-name in nemotron3-thor.sh"
        record 2
    fi
fi

# ── OpenShell sandbox ──────────────────────────────────────────────────────────

header "OpenShell Sandbox"
echo ""

sandbox_name=""
if ! command -v openshell &>/dev/null; then
    fail "openshell not found — cannot check sandbox status"
    record 1
else
    sandbox_list=$(openshell sandbox list 2>/dev/null || echo "")
    sandbox_name=$(echo "${sandbox_list}" \
        | sed 's/\x1b\[[0-9;]*m//g' \
        | awk 'NR>1 && $1 != "" {print $1; exit}')
    sandbox_phase=$(echo "${sandbox_list}" \
        | sed 's/\x1b\[[0-9;]*m//g' \
        | awk 'NR>1 && $1 != "" {print $NF; exit}')

    if [[ -z "${sandbox_name}" ]]; then
        fail "No sandbox found"
        info "Run ./install.sh to create a sandbox."
        record 1
    elif [[ "${sandbox_phase}" == "Ready" ]]; then
        pass "Sandbox '${sandbox_name}' is Ready"
        record 0
    else
        fail "Sandbox '${sandbox_name}' is in phase: ${sandbox_phase}"
        fix "Check logs: nemoclaw ${sandbox_name} logs --follow"
        fix "Check status: openshell sandbox list"
        record 1
    fi
fi

# ── Inference route ────────────────────────────────────────────────────────────

header "Inference Route"
echo ""

if ! command -v openshell &>/dev/null; then
    fail "openshell not found — cannot check inference route"
    record 1
else
    inference=$(openshell inference get 2>/dev/null || echo "")
    provider=$(echo "${inference}" | grep 'Provider:' | awk '{print $2}')
    model=$(echo "${inference}"    | grep 'Model:'    | awk '{print $2}')

    if [[ -z "${provider}" ]]; then
        fail "No inference route configured"
        fix "Run: openshell provider create --name vllm-local --type openai \\"
        fix "       --credential OPENAI_API_KEY=dummy \\"
        fix "       --config OPENAI_BASE_URL=http://host.openshell.internal:8000/v1"
        fix "Then: openshell inference set --provider vllm-local \\"
        fix "        --model nvidia/nemotron-3-nano-30b-a3b --no-verify"
        record 1
    elif [[ "${provider}" == "vllm-local" ]]; then
        pass "Inference provider: ${provider}"
        pass "Inference model:    ${model}"
        record 0
        record 0
    else
        warn "Inference provider is '${provider}' — expected 'vllm-local'"
        info "The stack is configured for cloud inference, not local vLLM."
        fix "Switch to local: openshell inference set --provider vllm-local \\"
        fix "  --model nvidia/nemotron-3-nano-30b-a3b --no-verify"
        record 2
    fi
fi

# ── Summary ────────────────────────────────────────────────────────────────────

echo ""
echo "══════════════════════════════════════════════════════════════"
echo ""

total=$((CHECKS_PASSED + CHECKS_WARNED + CHECKS_FAILED))

if [[ "${CHECKS_FAILED}" -eq 0 && "${CHECKS_WARNED}" -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}  All ${total} checks passed — system is healthy.${NC}"
    echo ""
elif [[ "${CHECKS_FAILED}" -eq 0 ]]; then
    echo -e "${YELLOW}${BOLD}  ${CHECKS_PASSED} passed, ${CHECKS_WARNED} warning(s) — system is mostly healthy.${NC}"
    echo ""
    echo "  Review warnings above."
    echo ""
else
    echo -e "${RED}${BOLD}  ${CHECKS_PASSED} passed, ${CHECKS_WARNED} warning(s), ${CHECKS_FAILED} failed.${NC}"
    echo ""
    echo "  Review the failures above and check the fix hints."
    echo ""
    exit 1
fi

# ── Manual end-to-end test ─────────────────────────────────────────────────────
# OpenClaw runs inside the sandbox and cannot be reached non-interactively.
# Print the commands the user needs to run to verify end-to-end inference.

if [[ -n "${sandbox_name}" ]]; then
    echo -e "${BOLD}  To verify end-to-end inference:${NC}"
    echo ""
    echo "  Connect to the sandbox:"
    echo "    nemoclaw ${sandbox_name} connect"
    echo ""
    echo "  Then inside the sandbox:"
    echo "    openclaw agent --agent main --local \\"
    echo '      -m "Reply with one word: working" --session-id test'
    echo ""
    echo "  Expected: a single word reply from Nemotron 3 Nano."
    echo '  Note: "No reply from agent" on the first attempt is normal'
    echo "  while the model warms up — wait a moment and try again."
    echo ""
fi