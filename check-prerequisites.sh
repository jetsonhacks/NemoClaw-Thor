#!/usr/bin/env bash
# check-prerequisites.sh — Verify system prerequisites for NemoClaw-Thor
#
# Diagnostic tool: runs all prerequisite checks and reports results.
# Does NOT abort on failure — shows all problems at once so you can
# address them before running install.sh.
#
# Usage:
#   ./check-prerequisites.sh
#
# Exit codes:
#   0 — all checks passed (warnings are acceptable)
#   1 — one or more checks failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/checks.sh"

# ── Tracking ───────────────────────────────────────────────────────────────────

CHECKS_PASSED=0
CHECKS_WARNED=0
CHECKS_FAILED=0

# Parallel arrays: failed check name and its fix hint(s)
FAILED_NAMES=()
FAILED_FIXES=()

# run_check <display_name> <function> [args...]
# Runs the check, tracks pass/warn/fail, and captures fix hints for the
# ToDo summary by extracting '→' lines from the function output.
run_check() {
    local display_name="$1"
    shift
    local ret
    local output
    output=$("$@" 2>&1) && ret=0 || ret=$?

    # Print the check output
    echo "${output}"

    case "${ret}" in
        0)
            CHECKS_PASSED=$((CHECKS_PASSED + 1))
            ;;
        2)
            CHECKS_WARNED=$((CHECKS_WARNED + 1))
            local fixes
            fixes=$(echo "${output}" | sed 's/\x1b\[[0-9;]*m//g' | grep '→' | sed 's/.*→ //')
            FAILED_NAMES+=("${display_name} (warning)")
            FAILED_FIXES+=("${fixes}")
            ;;
        *)
            CHECKS_FAILED=$((CHECKS_FAILED + 1))
            local fixes
            fixes=$(echo "${output}" | sed 's/\x1b\[[0-9;]*m//g' | grep '→' | sed 's/.*→ //')
            FAILED_NAMES+=("${display_name}")
            FAILED_FIXES+=("${fixes}")
            ;;
    esac
    return 0  # never abort — always continue to next check
}

# ── Header ─────────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}NemoClaw-Thor Prerequisite Check${NC}"
echo -e "JetsonHacks — https://github.com/JetsonHacks/NemoClaw-Thor"
echo ""
echo "This script checks whether your system is ready to run install.sh."
echo "All checks are read-only — nothing will be changed."
echo ""
echo "Prerequisites this script does NOT check:"
echo "  • JetPack 7.1 / L4T 38.4 / Ubuntu 24.04 Noble"
echo "  • openshell-thor fixes applied"
echo "    See: https://github.com/JetsonHacks/openshell-thor"
echo ""

# ── OpenShell ──────────────────────────────────────────────────────────────────

header "OpenShell"
echo "  The NemoClaw installer requires OpenShell to be installed."
echo "  The installer will start the OpenShell gateway automatically"
echo "  during the install process — it does not need to be running now."
echo ""
run_check "OpenShell installed" check_openshell_installed

# ── openshell-thor fixes ───────────────────────────────────────────────────────

header "openshell-thor Fixes"
echo "  These five fixes are required for OpenShell to function on JetPack 7.1."
echo "  See: https://github.com/JetsonHacks/openshell-thor"
echo ""
run_check "iptable_raw module"    check_fix_iptable_raw
run_check "iptables legacy"       check_fix_iptables_legacy
run_check "br_netfilter module"   check_fix_br_netfilter
run_check "Docker IPv6 disabled"  check_fix_docker_ipv6
run_check "Docker cgroupns host"   check_fix_cgroupns

# ── Docker ─────────────────────────────────────────────────────────────────────

header "Docker"
run_check "Docker installed"          check_docker_installed
run_check "Docker daemon running"     check_docker_running
run_check "NVIDIA container runtime"  check_docker_nvidia_runtime

# ── Node.js / nvm ──────────────────────────────────────────────────────────────

header "Node.js and nvm"
echo "  NemoClaw requires Node.js 22 installed via nvm."
echo "  Do not use the system Node.js from apt (version 18)."
echo "  Run ./install-node.sh to install both automatically."
echo ""
run_check "nvm installed"   check_nvm_installed
run_check "Node.js version" check_node_version

# ── Build tools ────────────────────────────────────────────────────────────────

header "Build Tools"
echo "  OpenClaw's npm install may build the 'sharp' image library from"
echo "  source on aarch64 if a prebuilt binary is unavailable."
echo ""
run_check "Build tools" check_build_tools

# ── HuggingFace ────────────────────────────────────────────────────────────────

header "HuggingFace"
echo "  HF_TOKEN is required if you plan to use local vLLM inference."
echo "  You must also have accepted the model license at:"
echo "  https://huggingface.co/nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B-NVFP4"
echo ""
echo "  If you are using the NVIDIA cloud API profile instead, HF_TOKEN"
echo "  is not required and this check can be ignored."
echo ""
run_check "HF_TOKEN set" check_hf_token
run_check "Disk space"   check_disk_space

# ── Network ────────────────────────────────────────────────────────────────────

header "Network Connectivity"
run_check "huggingface.co reachable" check_connectivity_huggingface
run_check "github.com reachable"     check_connectivity_github

# ── Summary ────────────────────────────────────────────────────────────────────

echo ""
echo "══════════════════════════════════════════════════════════════"
echo ""

total=$((CHECKS_PASSED + CHECKS_WARNED + CHECKS_FAILED))

if [[ "${CHECKS_FAILED}" -eq 0 && "${CHECKS_WARNED}" -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}  All ${total} checks passed.${NC}"
    echo ""
    echo "  Your system is ready. Run ./install.sh to continue."
    echo ""
    exit 0

elif [[ "${CHECKS_FAILED}" -eq 0 ]]; then
    echo -e "${YELLOW}${BOLD}  ${CHECKS_PASSED} passed, ${CHECKS_WARNED} warning(s), 0 failed.${NC}"
    echo ""
    echo -e "${YELLOW}${BOLD}  To Do (warnings):${NC}"
    for i in "${!FAILED_NAMES[@]}"; do
        echo ""
        echo -e "  ${YELLOW}▸ ${FAILED_NAMES[$i]}${NC}"
        while IFS= read -r fix_line; do
            [[ -n "${fix_line}" ]] && echo "    → ${fix_line}"
        done <<< "${FAILED_FIXES[$i]}"
    done
    echo ""
    echo "  Warnings are non-blocking. Run ./install.sh when ready."
    echo ""
    exit 0

else
    echo -e "${RED}${BOLD}  ${CHECKS_PASSED} passed, ${CHECKS_WARNED} warning(s), ${CHECKS_FAILED} failed.${NC}"
    echo ""
    echo -e "${BOLD}  To Do before running ./install.sh:${NC}"
    for i in "${!FAILED_NAMES[@]}"; do
        echo ""
        if [[ "${FAILED_NAMES[$i]}" == *"(warning)"* ]]; then
            echo -e "  ${YELLOW}▸ ${FAILED_NAMES[$i]}${NC}"
        else
            echo -e "  ${RED}▸ ${FAILED_NAMES[$i]}${NC}"
        fi
        while IFS= read -r fix_line; do
            [[ -n "${fix_line}" ]] && echo "    → ${fix_line}"
        done <<< "${FAILED_FIXES[$i]}"
    done
    echo ""
    exit 1
fi